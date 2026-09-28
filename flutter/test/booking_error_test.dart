import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/network/api_client.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-3 — NEVER SHOW THE CUSTOMER A STACK TRACE
///
/// _submit rendered ApiFailure.message straight into the error banner. Only the
/// server-body path is localized; the other two are transport detail or an
/// exception's toString, so a timeout produced
///
///   "The request connection took longer than 0:00:15.000000."
///
/// and any non-Dio error produced "Instance of 'TypeError'" — in an Arabic,
/// right-to-left screen, with no way to retry.
/// ============================================================================
void main() {
  DioException timeout() => DioException(
        requestOptions: RequestOptions(path: '/bookings'),
        type: DioExceptionType.connectionTimeout,
        message: 'The request connection took longer than 0:00:15.000000.',
      );

  DioException serverError(String code, String message) => DioException(
        requestOptions: RequestOptions(path: '/bookings'),
        response: Response(
          requestOptions: RequestOptions(path: '/bookings'),
          statusCode: 409,
          data: {'error_code': code, 'message': message},
        ),
      );

  Future<void> bookThrough(WidgetTester tester) async {
    await tester.tap(find.text('Hair Cut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الحجز').last);
    await tester.pumpAndSettle();
  }

  Future<FakeBookingRepository> pumpWithFailure(
    WidgetTester tester,
    Object error,
  ) async {
    final stores = FakeStoreRepository(
      storefront: storefrontFixture(staffSelection: false),
      slotsFor: (_) => [slot('12:00')],
    );
    final bookings = FakeBookingRepository(createError: error);

    await pumpBookingFlow(tester, stores: stores, bookings: bookings);
    await bookThrough(tester);

    return bookings;
  }

  group('BUG-3 ApiFailure marks what is safe to show', () {
    test('a server body is flagged as localized', () {
      final failure = ApiFailure.from(serverError('SLOT_TAKEN', 'عذراً'));

      expect(failure.fromServer, isTrue);
      expect(failure.code, 'SLOT_TAKEN');
    });

    test('a transport failure is not', () {
      expect(ApiFailure.from(timeout()).fromServer, isFalse);
    });

    test('an arbitrary exception is not', () {
      expect(ApiFailure.from(TypeError()).fromServer, isFalse);
    });

    test('an error_code with no message keeps the code but not the trust', () {
      final failure = ApiFailure.from(
        DioException(
          requestOptions: RequestOptions(path: '/bookings'),
          response: Response(
            requestOptions: RequestOptions(path: '/bookings'),
            statusCode: 409,
            data: const {'error_code': 'SLOT_TAKEN'},
          ),
        ),
      );

      expect(failure.code, 'SLOT_TAKEN');
      expect(failure.fromServer, isFalse);
    });
  });

  group('BUG-3 the banner', () {
    testWidgets('shows a localized message for a timeout, not Dio text',
        (tester) async {
      await pumpWithFailure(tester, timeout());

      expect(find.text('تعذّر إتمام الحجز. تحقق من اتصالك وحاول مرة أخرى.'),
          findsOneWidget);
      expect(find.textContaining('0:00:15'), findsNothing);
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('never leaks an exception toString', (tester) async {
      await pumpWithFailure(tester, TypeError());

      expect(find.textContaining('TypeError'), findsNothing);
      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.text('تعذّر إتمام الحجز. تحقق من اتصالك وحاول مرة أخرى.'),
          findsOneWidget);
    });

    testWidgets('still shows a genuine server message', (tester) async {
      await pumpWithFailure(
        tester,
        serverError('VALIDATION_FAILED', 'هذه الخدمة لم تعد متاحة'),
      );

      expect(find.text('هذه الخدمة لم تعد متاحة'), findsOneWidget);
    });

    testWidgets('offers Retry, and retrying resubmits', (tester) async {
      final bookings = await pumpWithFailure(tester, timeout());

      expect(bookings.createCalls, 1);
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      // Let the retry succeed this time.
      bookings.createError = null;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      expect(bookings.createCalls, 2, reason: 'Retry did not resubmit.');
      expect(find.text('CONFIRMED_STUB'), findsOneWidget);
    });

    testWidgets('does not offer Retry for a lost slot', (tester) async {
      await pumpWithFailure(
        tester,
        serverError('SLOT_TAKEN', 'عذراً، تم حجز هذا الوقت للتو. اختر وقتاً آخر.'),
      );

      // The customer is sent back to choose another time, so retrying the same
      // slot would only fail again.
      expect(find.text('إعادة المحاولة'), findsNothing);
      expect(find.text('اختر الموعد'), findsOneWidget);
    });
  });
}
