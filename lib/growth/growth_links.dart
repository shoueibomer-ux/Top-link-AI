import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/growth.dart';
import '../app_colors.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/service_category.dart';
import '../provider/provider_session.dart';

/// A link into the app from outside it: the website's "Request this service" and invite pages hand the visitor
/// `tabmatch://open/request?service=...&src=...&ref=...` or `tabmatch://open/invite?code=...&provider=...` (see
/// growth.links on the server), and Flutter's deep linking turns those into the route `/request?...` or
/// `/invite?...`. A seasonal reminder's push notification carries the same request link as data.
sealed class GrowthLink {
  const GrowthLink();
}

/// Open the request flow with [service] chosen, remembering where the person came from.
class RequestLink extends GrowthLink {
  const RequestLink({required this.service, this.attribution});

  final String service;
  final RequestAttribution? attribution;
}

/// Someone opened a friend's invite link.
class InviteLink extends GrowthLink {
  const InviteLink({required this.code, this.providerId});

  final String code;
  final int? providerId;
}

const _sources = {'seo', 'seasonal', 'invite'};
final _safe = RegExp(r'^[A-Za-z0-9_-]{1,120}$');

String _param(Map<String, String> query, String key) {
  final value = (query[key] ?? '').trim();
  return _safe.hasMatch(value) ? value : '';
}

RequestAttribution? _attribution(String source, String ref) =>
    _sources.contains(source) ? RequestAttribution(source: source, ref: ref) : null;

/// The link a route (`/request?...`) or a full `tabmatch://open/...` URL stands for, or null for anything else.
GrowthLink? parseGrowthLink(String? route) {
  if (route == null || route.isEmpty) return null;
  final uri = Uri.tryParse(route);
  if (uri == null) return null;
  var path = uri.path;
  if (uri.scheme == 'tabmatch') {
    if (uri.host != 'open') return null;
  } else if (uri.hasScheme) {
    return null;
  }
  path = path.replaceAll(RegExp(r'/+$'), '');
  final query = uri.queryParameters;
  switch (path) {
    case '/request':
      final service = _param(query, 'service');
      if (service.isEmpty) return null;
      return RequestLink(service: service, attribution: _attribution(_param(query, 'src'), _param(query, 'ref')));
    case '/invite':
      final code = _param(query, 'code').toUpperCase();
      if (code.isEmpty) return null;
      return InviteLink(code: code, providerId: int.tryParse(query['provider'] ?? ''));
  }
  return null;
}

/// The request link in a seasonal reminder's push data (growth.jobs sends `type: request_prefill`), or null.
RequestLink? requestLinkFromPush(Map<String, dynamic> data) {
  if (data['type'] != 'request_prefill') return null;
  final service = '${data['service'] ?? ''}';
  if (!_safe.hasMatch(service)) return null;
  final source = '${data['source'] ?? ''}';
  final ref = '${data['ref'] ?? ''}';
  return RequestLink(service: service, attribution: _attribution(source, _safe.hasMatch(ref) ? ref : ''));
}

/// The screen a link opens. An invite is also remembered, so it can be recorded once the person signs in.
Route<void> routeForGrowthLink(GrowthLink link, {RouteSettings? settings}) {
  switch (link) {
    case RequestLink(:final service, :final attribution):
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => OnboardingScreen(initialCategory: findCategoryBySlug(service), attribution: attribution),
      );
    case InviteLink(:final code, :final providerId):
      unawaited(PendingInvite.save(code, providerId: providerId));
      return MaterialPageRoute<void>(settings: settings, builder: (_) => InviteWelcomeScreen(code: code));
  }
}

/// MaterialApp.onGenerateRoute: the routes deep links arrive as.
Route<void>? growthRoute(RouteSettings settings) {
  final link = parseGrowthLink(settings.name);
  return link == null ? null : routeForGrowthLink(link, settings: settings);
}

/// An invite code waiting for the person to sign in (opened from a link, or typed in before signing in).
class PendingInvite {
  static const _codeKey = 'pending_invite_code';
  static const _providerKey = 'pending_invite_provider';

  static Future<void> save(String code, {int? providerId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
    if (providerId != null) {
      await prefs.setInt(_providerKey, providerId);
    } else {
      await prefs.remove(_providerKey);
    }
  }

  static Future<({String code, int? providerId})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    if (code == null || code.isEmpty) return null;
    return (code: code, providerId: prefs.getInt(_providerKey));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_codeKey);
    await prefs.remove(_providerKey);
  }
}

/// Records a waiting invite against the account that just signed in. A code the server refuses is dropped;
/// a network problem keeps it for the next sign-in. Returns whether it was recorded.
Future<bool> claimPendingInvite(AuthSession session) async {
  final pending = await PendingInvite.load();
  if (pending == null) return false;
  try {
    await session.authorized((token) => session.api.claimInvite(token, pending.code, providerId: pending.providerId));
    await PendingInvite.clear();
    return true;
  } on InviteClaimRejected {
    await PendingInvite.clear();
    return false;
  } catch (_) {
    return false;
  }
}

/// What an invite link opens: a short welcome, then on into the app.
class InviteWelcomeScreen extends StatelessWidget {
  const InviteWelcomeScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Welcome to Tabmatch')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.card_giftcard_outlined, size: 40, color: AppColors.turquoise),
              const SizedBox(height: 16),
              const Text(
                "A friend invited you",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 12),
              Text(
                'Tell us what you need, and Tabmatch sends your request to approved local providers. '
                'Your friend\'s invite ($code) is saved and counted when you sign in.',
                key: const Key('invite-welcome-text'),
                style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.navy),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('invite-get-started'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Get started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
