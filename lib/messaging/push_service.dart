import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../provider/auth_storage.dart';
import '../provider/provider_session.dart';
import 'conversation_screen.dart';

/// The chat conversation a push notification is about, or null if it isn't a chat notification. The server
/// sends `type: chat` and the conversation id as text (messaging.push.notify_new_message).
int? conversationIdFromPush(Map<String, dynamic> data) {
  if (data['type'] != 'chat') return null;
  return int.tryParse('${data['conversation_id'] ?? ''}');
}

/// What push needs from Firebase, so the rest can be tested without it.
abstract class PushBackend {
  /// False when this build has no Firebase config (no google-services.json): push is simply off.
  Future<bool> init();

  /// Shows the system "allow notifications?" prompt (Android 13+; older versions say yes without asking).
  Future<void> requestPermission();

  /// Whether notifications are allowed right now. Never prompts.
  Future<bool> permissionGranted();
  Future<String?> token();
  Stream<String> get onTokenRefresh;
  Stream<Map<String, dynamic>> get onForegroundMessage;
  Stream<Map<String, dynamic>> get onOpenedFromNotification;
  Future<Map<String, dynamic>?> initialMessage();
  Future<void> deleteToken();
}

/// Uses the classic FCM registration token (getToken / onTokenRefresh / deleteToken). firebase_messaging 17
/// marks these deprecated in favour of register()/onRegistered, which hand out a Firebase Installation ID for
/// "direct send" instead. The server sends with the FCM HTTP v1 API to a registration token (messaging.push),
/// and that is the identifier this path is known to work with, so the deprecated calls are used on purpose
/// until the newer one is confirmed end to end on a real device.
class FirebasePushBackend implements PushBackend {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> init() async {
    try {
      await Firebase.initializeApp();
      return true;
    } catch (e) {
      debugPrint('[push] Firebase is not configured in this build, so push notifications are off ($e)');
      return false;
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _messaging.requestPermission(); // Android 13+ asks; older versions say yes
    } catch (_) {}
  }

  @override
  Future<bool> permissionGranted() async {
    try {
      final status = (await _messaging.getNotificationSettings()).authorizationStatus;
      return status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  // ignore: deprecated_member_use
  Future<String?> token() => _messaging.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage => FirebaseMessaging.onMessage.map((m) => m.data);

  @override
  Stream<Map<String, dynamic>> get onOpenedFromNotification => FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Future<Map<String, dynamic>?> initialMessage() async => (await _messaging.getInitialMessage())?.data;

  @override
  // ignore: deprecated_member_use
  Future<void> deleteToken() => _messaging.deleteToken();
}

/// Push notifications for new chat messages. It does nothing at all (and never throws) unless Firebase is
/// configured for the build, and it registers this phone with the server only while someone is signed in.
/// The notification never contains the message: the app fetches that itself when it opens.
class PushService {
  PushService({PushBackend? backend, AuthSession Function()? sessionFactory})
      : _backend = backend ?? FirebasePushBackend(),
        _sessionFactory = sessionFactory ?? AuthSession.new;

  /// The one the app uses. Not final so a test can swap in one with a fake backend.
  static PushService instance = PushService();

  /// Set once we have shown the system prompt, so a person is only ever asked at the moment it makes sense.
  static const _askedKey = 'push_permission_asked';

  /// The person's own on/off choice in Settings (on until they turn it off).
  static const _preferenceKey = 'push_notifications_enabled';

  /// Lets a tapped notification open the chat from anywhere in the app.
  static final navigatorKey = GlobalKey<NavigatorState>();

  final PushBackend _backend;
  final AuthSession Function() _sessionFactory;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _enabled = false;
  String? _token;

  bool get enabled => _enabled;

  /// Goes up each time a chat notification arrives while the app is open, so lists can refresh their unread counts.
  final chatActivity = ValueNotifier<int>(0);

  Future<void> start() async {
    if (_enabled) return;
    try {
      if (!await _backend.init()) return;
      _enabled = true;
      // No prompt here: asking before the person has done anything is asking for nothing. The prompt comes
      // later (askAfterFirstRequest). A phone that already allows notifications registers straight away.
      _subscriptions
        ..add(_backend.onTokenRefresh.listen((_) => register()))
        ..add(_backend.onForegroundMessage.listen((data) {
          if (conversationIdFromPush(data) != null) chatActivity.value++;
        }))
        ..add(_backend.onOpenedFromNotification.listen(_openFromPush));
      final initial = await _backend.initialMessage(); // the app was started by tapping a notification
      if (initial != null) _openFromPush(initial);
      if (await _backend.permissionGranted()) await register();
    } catch (e) {
      debugPrint('[push] could not start: $e');
    }
  }

  /// Asks for notification permission, but only once and only when it makes sense: right after the person sends
  /// their first request (a client) or accepts their first lead (a provider). If it is allowed, this phone is
  /// registered with the server. Returns whether notifications are now allowed.
  Future<bool> askAfterFirstRequest() => _askForPermission(onlyOnce: true);

  Future<bool> _askForPermission({required bool onlyOnce}) async {
    if (!_enabled) return false;
    try {
      if (!await _backend.permissionGranted()) {
        final prefs = await SharedPreferences.getInstance();
        if (onlyOnce && (prefs.getBool(_askedKey) ?? false)) return false;
        await prefs.setBool(_askedKey, true);
        await _backend.requestPermission();
        if (!await _backend.permissionGranted()) return false;
      }
      await register();
      return true;
    } catch (e) {
      debugPrint('[push] could not ask for permission: $e');
      return false;
    }
  }

  Future<bool> _preferenceOn() async => (await SharedPreferences.getInstance()).getBool(_preferenceKey) ?? true;

  /// What the Settings switch shows: this build has push, the phone allows it, and the person has not turned it off.
  Future<bool> notificationsOn() async {
    if (!_enabled) return false;
    return await _preferenceOn() && await _backend.permissionGranted();
  }

  /// The Settings switch. Turning it on asks the phone for permission if it hasn't been given (the system only
  /// shows its prompt a limited number of times). Returns what is true afterwards, so the switch never lies.
  Future<bool> setNotifications(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    if (!on) {
      await prefs.setBool(_preferenceKey, false);
      await unregister();
      return false;
    }
    await prefs.setBool(_preferenceKey, true);
    return _enabled && await _askForPermission(onlyOnce: false);
  }

  /// Tells the server this phone can receive the signed-in person's notifications.
  Future<void> register([AuthSession? session]) async {
    if (!_enabled) return;
    try {
      if (!await _preferenceOn()) return;
      if (!await AuthStorage.isLoggedIn()) return;
      final token = await _backend.token();
      if (token == null) return;
      _token = token;
      final s = session ?? _sessionFactory();
      await s.authorized((access) => s.api.registerDevice(access, token));
    } catch (e) {
      debugPrint('[push] could not register this phone: $e');
    }
  }

  /// Stops notifications for the person signing out. Call it *before* their login is cleared.
  Future<void> unregister([AuthSession? session]) async {
    if (!_enabled) return;
    try {
      final token = _token ?? await _backend.token();
      _token = null;
      if (token == null || !await AuthStorage.isLoggedIn()) return;
      final s = session ?? _sessionFactory();
      await s.authorized((access) => s.api.unregisterDevice(access, token));
    } catch (e) {
      debugPrint('[push] could not unregister this phone: $e');
    }
  }

  void _openFromPush(Map<String, dynamic> data) {
    final id = conversationIdFromPush(data);
    final navigator = navigatorKey.currentState;
    if (id == null || navigator == null) return;
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => ConversationScreen(session: _sessionFactory(), conversationId: id),
    ));
  }

  @visibleForTesting
  void disposeForTest() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }
}
