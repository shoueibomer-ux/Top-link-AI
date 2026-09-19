import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _prefsKey = 'provider_id';

/// Returns a UUID persisted locally identifying "this provider signing up",
/// generating one on first call. Separate from device_id (subscription/device_id.dart)
/// since the same device could plausibly be used both as a client and as a
/// provider filling out the sign-up wizard — same "no real accounts yet"
/// pattern as device_id, applied to the provider side.
Future<String> getProviderId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_prefsKey);
  if (existing != null) return existing;

  final generated = const Uuid().v4();
  await prefs.setString(_prefsKey, generated);
  return generated;
}
