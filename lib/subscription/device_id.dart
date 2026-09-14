import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _prefsKey = 'device_id';

/// Returns a UUID persisted locally for this installation, generating one
/// on first call. Stands in for "the user" since the app has no
/// login/signup — the backend keys Subscription rows off this value.
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_prefsKey);
  if (existing != null) return existing;

  final generated = const Uuid().v4();
  await prefs.setString(_prefsKey, generated);
  return generated;
}
