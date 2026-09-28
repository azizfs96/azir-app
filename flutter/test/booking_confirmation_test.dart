import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/booking/data/booking_repository.dart';
import 'package:wasla/features/booking/presentation/confirmation_screen.dart';

/// ============================================================================
/// "العودة للمتجر" GOES BACK TO THE STORE, NOT THE APP HOME
///
/// The customer books inside a merchant's storefront. When the confirmation
/// screen's button sent them to '/' they landed on the app's list of every
/// store — losing the store they had just booked at, and the "حجوزاتي" list
/// that now holds their new booking. It must return to that store's page.
/// ============================================================================
void main() {
  BookingResult bookingWith({String? storeToken}) => BookingResult(
        id: 1,
        reference: 'WSL-1',
        status: 'confirmed',
        startsAt: '2026-09-10T12:00:00+03:00',
        price: 100,
        currency: 'SAR',
        storeName: 'Glow Beauty',
        storeToken: storeToken,
      );

  Future<GoRouter> pumpConfirmation(WidgetTester tester, BookingResult booking) async {
    final router = GoRouter(
      // Start deep in the flow, as pushReplacement to /booking/confirmed does.
      initialLocation: '/booking/confirmed',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('APP_HOME')),
        GoRoute(
          path: '/s/:token',
          builder: (_, state) => Text('STORE_${state.pathParameters['token']}'),
        ),
        GoRoute(
          path: '/booking/confirmed',
          builder: (_, _) => ConfirmationScreen(booking: booking),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      locale: const Locale('ar'),
      supportedLocales: Strings.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ));
    await tester.pumpAndSettle();

    return router;
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

  testWidgets('the button returns to the store page', (tester) async {
    final router = await pumpConfirmation(tester, bookingWith(storeToken: 'FGEE5Y2M'));

    expect(find.text('العودة للمتجر'), findsOneWidget);

    await tester.tap(find.text('العودة للمتجر'));
    await tester.pumpAndSettle();

    expect(location(router), '/s/FGEE5Y2M');
    expect(find.text('STORE_FGEE5Y2M'), findsOneWidget);
    expect(find.text('APP_HOME'), findsNothing,
        reason: 'The customer was dumped on the app home instead of the store.');
  });

  testWidgets('the finished flow cannot be swiped back into', (tester) async {
    final router = await pumpConfirmation(tester, bookingWith(storeToken: 'FGEE5Y2M'));

    await tester.tap(find.text('العودة للمتجر'));
    await tester.pumpAndSettle();

    // go() replaced the stack — a system back from the store must not return
    // to the confirmation screen.
    final popped = await router.routerDelegate.popRoute();

    expect(popped, isFalse, reason: 'The booking flow is still on the stack.');
    expect(find.text('بتاريخ'), findsNothing);
    expect(find.text('STORE_FGEE5Y2M'), findsOneWidget);
  });

  testWidgets('a booking without a store token falls back to app home',
      (tester) async {
    final router = await pumpConfirmation(tester, bookingWith(storeToken: null));

    await tester.tap(find.text('العودة للمتجر'));
    await tester.pumpAndSettle();

    expect(location(router), '/');
    expect(find.text('APP_HOME'), findsOneWidget);
  });
}
