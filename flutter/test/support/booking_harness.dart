import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/booking/data/booking_repository.dart';
import 'package:wasla/features/booking/data/store_bookings_provider.dart';
import 'package:wasla/features/booking/presentation/booking_flow_screen.dart';
import 'package:wasla/features/stores/data/store_repository.dart';
import 'package:wasla/features/stores/domain/storefront.dart';

/// ============================================================================
/// WIDGET-TEST HARNESS FOR THE BOOKING FLOW
///
/// The flow's unit tests cover BookingFlow's answer map, which is why the
/// domain rules have held up. Every bug this file exists for lived one layer
/// up — in navigation, widget state restoration and what the screens actually
/// ASK the API for — so these tests mount the real screens against a fake
/// repository and drive them the way a customer does.
///
/// The booking flow is ONE route with internal step state, so the harness
/// pushes it onto a stack: popping the route is then observable as landing
/// back on the storefront stub.
/// ============================================================================

/// A StoreRepository that answers from memory and RECORDS what it was asked.
///
/// The recording is the point: several bugs were about the app requesting
/// availability with the wrong parameters, which no assertion on rendered
/// pixels would ever catch.
class FakeStoreRepository implements StoreRepository {
  FakeStoreRepository({required this.storefront, this.slotsFor});

  final Storefront storefront;

  /// Slots keyed by the request, so a test can make date/staff actually matter.
  final List<Slot> Function(AvailabilityQuery query)? slotsFor;

  /// Every availability call, in order.
  final List<AvailabilityQuery> queries = [];

  /// Set to fail the next resolve() — for the storefront error path.
  Object? resolveError;

  /// How many times the storefront was actually fetched, so a test can tell a
  /// fresh request from a session-cached value.
  int resolveCalls = 0;

  @override
  Future<Storefront> resolve(String token) async {
    resolveCalls++;
    if (resolveError != null) throw resolveError!;
    return storefront;
  }

  @override
  Future<List<Slot>> availability({
    required String storeToken,
    required int serviceId,
    required DateTime date,
    int? branchId,
    int? staffId,
  }) async {
    final query = AvailabilityQuery(
      storeToken: storeToken,
      serviceId: serviceId,
      date: date,
      branchId: branchId,
      staffId: staffId,
    );

    queries.add(query);

    return slotsFor?.call(query) ?? const <Slot>[];
  }

  AvailabilityQuery get lastQuery => queries.last;
}

/// One recorded availability request.
class AvailabilityQuery {
  const AvailabilityQuery({
    required this.storeToken,
    required this.serviceId,
    required this.date,
    this.branchId,
    this.staffId,
  });

  final String storeToken;
  final int serviceId;
  final DateTime date;
  final int? branchId;
  final int? staffId;

  @override
  String toString() =>
      'AvailabilityQuery(date: ${date.toIso8601String()}, staffId: $staffId, branchId: $branchId)';
}

/// A BookingRepository that can succeed or fail on demand.
class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({this.createError, this.result});

  Object? createError;
  BookingResult? result;

  int createCalls = 0;

  @override
  Future<BookingResult> create(Map<String, dynamic> payload) async {
    createCalls++;
    lastPayload = payload;

    if (createError != null) throw createError!;

    return result ??
        const BookingResult(
          id: 1,
          reference: 'WSL-1',
          status: 'confirmed',
          startsAt: '2026-09-01T12:00:00+03:00',
          price: 100,
          currency: 'SAR',
        );
  }

  Map<String, dynamic>? lastPayload;

  @override
  Future<List<BookingResult>> list({String filter = 'upcoming'}) async => const [];

  @override
  Future<void> cancel(int id, {String? reason}) async {}
}

/// Build a storefront the way the SERVER sends it, so parsing is exercised
/// too rather than bypassed by constructing Storefront directly.
Storefront storefrontFixture({
  String token = 'ABC12345',
  bool staffSelection = true,
  bool allowAny = true,
  bool customerNotes = false,
  List<Map<String, dynamic>>? staff,
  int? maxAdvanceDays,
  int? minLeadMinutes,

  /// Exact step list to send instead of the standard one — for server shapes
  /// the current engine never emits but the contract allows.
  List<Map<String, dynamic>>? flowOverride,
}) {
  return Storefront.fromJson({
    'store': {
      'token': token,
      'name': 'Glow Beauty',
      'timezone': 'Asia/Riyadh',
      'currency': 'SAR',
    },
    'configuration': {
      'staff_selection': staffSelection,
      'customer_notes': customerNotes,
    },
    'flow': flowOverride ??
        [
      {'step': 'service', 'required': true},
      if (staffSelection)
        {'step': 'staff', 'required': true, 'allow_any': allowAny},
      {'step': 'date', 'required': true},
      {'step': 'time', 'required': true},
      if (customerNotes) {'step': 'notes', 'required': false},
      {'step': 'payment', 'required': false, 'mode': 'pay_at_store'},
      {'step': 'confirm', 'required': true},
        ],
    'services': [
      {'id': 1, 'name': 'Hair Cut', 'price': 100, 'duration_minutes': 60},
    ],
    'staff': staff ??
        (staffSelection
            ? [
                {'id': 5, 'name': 'Sara'},
                {'id': 6, 'name': 'Reem'},
              ]
            : const []),
    'branches': const [],
    if (maxAdvanceDays != null || minLeadMinutes != null)
      'policies': {
        'booking_window': {
          'min_lead_time_minutes': minLeadMinutes ?? 0,
          'max_advance_days': ?maxAdvanceDays,
        },
      },
  });
}

/// A slot as the availability endpoint serialises it.
Slot slot(String time, {int? staffId, String? staffName, DateTime? day}) {
  final date = day ?? DateTime.now().add(const Duration(days: 1));
  final parts = time.split(':');

  final startsAt = DateTime(
    date.year,
    date.month,
    date.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );

  return Slot(
    startsAt: startsAt.toIso8601String(),
    time: time,
    staffId: staffId,
    staffName: staffName,
  );
}

/// Mount the booking flow on a route stack, exactly as the app does:
/// storefront -> push('/s/{token}/book').
///
/// Returns the router so a test can inspect the current location after a pop.
Future<GoRouter> pumpBookingFlow(
  WidgetTester tester, {
  required FakeStoreRepository stores,
  FakeBookingRepository? bookings,
  String token = 'ABC12345',
  Locale locale = const Locale('ar'),

  /// Called every time the store-bookings provider rebuilds, so a test can
  /// prove the list was invalidated rather than served from the session cache.
  VoidCallback? onStoreBookingsBuild,
}) async {
  final router = GoRouter(
    initialLocation: '/storefront',
    routes: [
      GoRoute(
        path: '/storefront',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('STOREFRONT_STUB')),
        ),
      ),
      GoRoute(
        path: '/s/:token/book',
        // Mirrors the real route: a service tile passes its service as extra.
        builder: (context, state) => BookingFlowScreen(
          token: state.pathParameters['token']!,
          preselectedService: state.extra as StoreService?,
        ),
      ),
      GoRoute(
        path: '/booking/confirmed',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('CONFIRMED_STUB')),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeRepositoryProvider.overrideWithValue(stores),
        if (bookings != null)
          bookingRepositoryProvider.overrideWithValue(bookings),
        if (onStoreBookingsBuild != null)
          storeBookingsProvider.overrideWith((ref, token) async {
            onStoreBookingsBuild();
            return const StoreBookings(upcoming: [], past: []);
          }),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        supportedLocales: Strings.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );

  await tester.pumpAndSettle();

  router.push('/s/$token/book');
  await tester.pumpAndSettle();

  return router;
}

/// Fire the OS back signal — the iOS edge-swipe and the Android hardware
/// button both arrive here, which is precisely the path the AppBar arrow
/// does NOT exercise.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// The route currently on TOP of the stack.
///
/// Deliberately not `currentConfiguration.uri`: for an imperatively pushed
/// route that still reports the base location ('/storefront'), which would make
/// a "did we leave the booking flow?" assertion pass no matter what happened.
String currentLocation(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;
