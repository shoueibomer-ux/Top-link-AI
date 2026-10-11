import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/pages/settings_page.dart';
import 'package:toplinkai_app/widgets/app_drawer.dart';

// Providers have one way in: Google sign-in, then review. The old email and
// password sign-up and its "Business Profile" screen are gone, so nothing in
// the client menus may lead to them.
void main() {
  testWidgets('the drawer no longer offers the email/password Business Profile', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(drawer: AppDrawer())));
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Business Profile'), findsNothing);
    for (final item in ['About Us', 'Mission & Vision', 'Settings', 'Switch role']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
  });

  testWidgets('Settings no longer has an Account row that logs in with a password', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsNothing);
    expect(find.text('ACCOUNT'), findsNothing); // section headers are upper-cased
    expect(find.text('Edit profile and email'), findsNothing);
    expect(find.text('Notifications'), findsOneWidget); // the rest of the page is still there
  });
}
