import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toplinkai_app/api/api_client.dart';
import 'package:toplinkai_app/api/subscription_status.dart';
import 'package:toplinkai_app/subscription/paywall_screen.dart';
import 'package:toplinkai_app/subscription/subscription_service.dart';

/// Records what the paywall asks the store/backend to do, without touching
/// either. `oneTimeProduct == null` models "no real store product configured
/// yet" (today's reality), which routes to the development fallback.
class _FakeService extends SubscriptionService {
  _FakeService({this.oneTimeProduct, this.oneTimeError}) : super(apiClient: ApiClient());

  final ProductDetails? oneTimeProduct;
  final Object? oneTimeError;
  final calls = <String>[];

  @override
  void listenToPurchaseUpdates({
    required String deviceId,
    required void Function() onActivated,
    required void Function(String message) onError,
  }) {}

  @override
  Future<ProductDetails?> queryMonthlyProduct() async => null;

  @override
  Future<void> simulatePurchaseForDevelopment(String deviceId) async => calls.add('simulateSubscription');

  @override
  Future<ProductDetails?> queryOneTimeUnlockProduct() async => oneTimeProduct;

  @override
  Future<void> buyOneTimeUnlock(ProductDetails product) async => calls.add('buyOneTime:${product.id}');

  @override
  Future<void> simulateOneTimePurchaseForDevelopment(String deviceId) async {
    calls.add('simulateOneTime');
    if (oneTimeError != null) throw oneTimeError!;
  }
}

final _storeProduct = ProductDetails(
  id: oneTimeUnlockProductId,
  title: 'One-time unlock',
  description: 'Unlock one provider',
  price: r'$4.99',
  rawPrice: 4.99,
  currencyCode: 'USD',
);

Widget _host({VoidCallback? onSubscribed, SubscriptionService? service}) => MaterialApp(
      home: PaywallScreen(onSubscribed: onSubscribed ?? () {}, subscriptionService: service),
    );

void main() {
  setUp(() {
    // getDeviceId() (device_id.dart) needs a plugin implementation to
    // resolve under flutter test — same requirement as the onboarding
    // flow's own test (see widget_test.dart).
    SharedPreferences.setMockInitialValues({});
  });

  // The default test surface (800x600) is far shorter than any real phone
  // screen and cuts off the CTA button below two plan cards — same fix
  // widget_test.dart already uses for the onboarding flow.
  void useRealisticDeviceSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> selectOneTimeAndTapCta(WidgetTester tester) async {
    await tester.tap(find.text('One-Time Unlock'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock one provider — \$4.99'));
    await tester.pump(); // start
    await tester.pump(const Duration(milliseconds: 50)); // let the fake's futures resolve
  }

  group('plan selection', () {
    testWidgets('shows both plans, clearly priced and labeled, with the subscription selected by default',
        (tester) async {
      useRealisticDeviceSize(tester);
      await tester.pumpWidget(_host());
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Monthly Plan'), findsOneWidget);
      expect(find.text('\$9.99 / month'), findsOneWidget);

      expect(find.text('One-Time Unlock'), findsOneWidget);
      expect(find.text('\$4.99 one-time'), findsOneWidget);
      expect(find.text('Full contact details for one provider'), findsOneWidget);

      // Subscription is the default selection, so its CTA shows first.
      expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsOneWidget);
    });

    testWidgets('selecting the one-time plan switches the CTA and price emphasis', (tester) async {
      useRealisticDeviceSize(tester);
      await tester.pumpWidget(_host());
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('One-Time Unlock'));
      await tester.pump();

      expect(find.widgetWithText(ElevatedButton, 'Unlock one provider — \$4.99'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsNothing);
    });

    testWidgets('switching back to the subscription plan restores its CTA', (tester) async {
      useRealisticDeviceSize(tester);
      await tester.pumpWidget(_host());
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('One-Time Unlock'));
      await tester.pump();
      await tester.tap(find.text('Monthly Plan'));
      await tester.pump();

      expect(find.widgetWithText(ElevatedButton, 'Subscribe'), findsOneWidget);
    });
  });

  group('buying the one-time unlock', () {
    testWidgets('with no store product yet, grants a credit via the dev fallback and lets the customer in',
        (tester) async {
      useRealisticDeviceSize(tester);
      final service = _FakeService();
      var entered = 0;
      await tester.pumpWidget(_host(service: service, onSubscribed: () => entered++));
      await tester.pump(const Duration(seconds: 1));

      await selectOneTimeAndTapCta(tester);

      expect(service.calls, ['simulateOneTime']);
      expect(entered, 1);
    });

    testWidgets('with a real store product, starts the store purchase and waits for the stream to finish it',
        (tester) async {
      useRealisticDeviceSize(tester);
      final service = _FakeService(oneTimeProduct: _storeProduct);
      var entered = 0;
      await tester.pumpWidget(_host(service: service, onSubscribed: () => entered++));
      await tester.pump(const Duration(seconds: 1));

      await selectOneTimeAndTapCta(tester);

      expect(service.calls, ['buyOneTime:$oneTimeUnlockProductId']);
      // Access is granted by the purchase stream once the store confirms —
      // not the moment the sheet opens.
      expect(entered, 0);
    });

    testWidgets('a failed grant shows the error, lets the customer in nowhere, and re-enables the button',
        (tester) async {
      useRealisticDeviceSize(tester);
      final service = _FakeService(oneTimeError: ApiException('Too many requests. Try again later.'));
      var entered = 0;
      await tester.pumpWidget(_host(service: service, onSubscribed: () => entered++));
      await tester.pump(const Duration(seconds: 1));

      await selectOneTimeAndTapCta(tester);

      expect(find.textContaining('Could not complete purchase'), findsOneWidget);
      expect(find.textContaining('Too many requests'), findsOneWidget);
      expect(entered, 0);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('buying the subscription is unchanged and never grants a credit', (tester) async {
      useRealisticDeviceSize(tester);
      final service = _FakeService();
      var entered = 0;
      await tester.pumpWidget(_host(service: service, onSubscribed: () => entered++));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Subscribe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(service.calls, ['simulateSubscription']);
      expect(entered, 1);
    });
  });

  group('purchase routing', () {
    test('the one-time product grants a credit; anything else is the subscription', () {
      expect(purchaseKindFor(oneTimeUnlockProductId), PurchaseKind.oneTimeUnlock);
      expect(purchaseKindFor(monthlySubscriptionProductId), PurchaseKind.subscription);
      expect(purchaseKindFor('something.else'), PurchaseKind.subscription);
    });
  });

  group('SubscriptionStatus.canEnterApp', () {
    SubscriptionStatus parse(Map<String, dynamic> json) => SubscriptionStatus.fromJson({'status': 'inactive', ...json});

    test('a one-time buyer gets in although they are not a subscriber', () {
      final status = parse({'unlock_credits': 1, 'has_access': true});
      expect(status.isActive, isFalse);
      expect(status.unlockCredits, 1);
      expect(status.canEnterApp, isTrue);
    });

    test('a device with neither a subscription nor a credit stays on the paywall', () {
      expect(parse({'unlock_credits': 0, 'has_access': false}).canEnterApp, isFalse);
    });

    test('the backend\'s verdict wins over a stale local reading of the subscription', () {
      // has_access false even though status says active: e.g. the backend
      // already expired it. The server is the source of truth.
      final status = parse({'status': 'active', 'has_access': false});
      expect(status.canEnterApp, isFalse);
    });

    test('against a backend that predates has_access it falls back to the subscription check', () {
      expect(parse({'status': 'active'}).canEnterApp, isTrue);
      expect(parse({'status': 'inactive'}).canEnterApp, isFalse);
      expect(parse({'status': 'inactive'}).unlockCredits, 0);
    });
  });
}
