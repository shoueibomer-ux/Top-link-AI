import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'root_gate.dart';

/// Which side of the marketplace this device is using. Chosen once on the role
/// screen and remembered locally, so the app opens straight into it.
enum AppRole { client, provider }

class RoleStorage {
  static const _key = 'app_role';

  static Future<AppRole?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    for (final role in AppRole.values) {
      if (role.name == name) return role;
    }
    return null;
  }

  static Future<void> save(AppRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, role.name);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Forgets the saved choice and returns to the role screen. Rebuilds the app's
/// root rather than popping to it, because the client flow replaces its own
/// first route when a request is submitted.
Future<void> switchRole(BuildContext context) async {
  final navigator = Navigator.of(context);
  await RoleStorage.clear();
  navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RootGate()), (route) => false);
}
