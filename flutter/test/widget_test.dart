import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/features/booking/domain/booking_flow.dart';
import 'package:wasla/features/qr_scanner/domain/store_token_parser.dart';
import 'package:wasla/features/stores/domain/storefront.dart';

/// ============================================================================
/// THE CONFIGURABLE BOOKING FLOW (spec §9, §43)
///
/// These tests are the app-side proof of the architectural rule:
///
///   "A new merchant is created through data and configuration, not new code."
///
/// Two merchants with opposite configurations produce two different journeys
/// from the SAME code path.
/// ============================================================================
void main() {
  // Merchant A from spec §9: customer picks their stylist.
  List<FlowStep> merchantA() => [
        const FlowStep(type: FlowStepType.service, required: true),
        const FlowStep(type: FlowStepType.staff, required: true, allowAny: true),
        const FlowStep(type: FlowStepType.date, required: true),
        const FlowStep(type: FlowStepType.time, required: true),
        const FlowStep(type: FlowStepType.payment, required: false, mode: 'pay_at_store'),
        const FlowStep(type: FlowStepType.confirm, required: true),
      ];

  // Merchant B from spec §9: no staff choice, several branches.
  List<FlowStep> merchantB() => [
        const FlowStep(type: FlowStepType.branch, required: true),
        const FlowStep(type: FlowStepType.service, required: true),
        const FlowStep(type: FlowStepType.date, required: true),
        const FlowStep(type: FlowStepType.time, required: true),
        const FlowStep(type: FlowStepType.payment, required: false, mode: 'pay_at_store'),
        const FlowStep(type: FlowStepType.confirm, required: true),
      ];

  const service = StoreService(id: 1, name: 'Hair Color', price: 250, durationMinutes: 120);
  const staff = StoreStaff(id: 7, name: 'Sara');
  const branch = StoreBranch(id: 3, name: 'Olaya');

  group('the same code produces different journeys', () {
    test('merchant A asks for a staff member', () {
      final flow = BookingFlow(steps: merchantA());

      expect(flow.steps.map((s) => s.type), contains(FlowStepType.staff));
      expect(flow.steps.map((s) => s.type), isNot(contains(FlowStepType.branch)));
    });

    test('merchant B asks for a branch and never for staff', () {
      final flow = BookingFlow(steps: merchantB());

      expect(flow.steps.map((s) => s.type), contains(FlowStepType.branch));
      expect(
        flow.steps.map((s) => s.type),
        isNot(contains(FlowStepType.staff)),
        reason: 'Merchant B hides staff; the customer must never be asked',
      );
    });
  });

  group('advancing', () {
    test('a required step blocks until it is answered', () {
      final flow = BookingFlow(steps: merchantA());

      expect(flow.canAdvance, isFalse);
      flow.record(FlowStepType.service, service);
      expect(flow.canAdvance, isTrue);
    });

    test('an optional step never blocks', () {
      final flow = BookingFlow(steps: merchantA())..goTo(4); // payment
      expect(flow.canAdvance, isTrue);
    });

    test('"any available staff" counts as an answer', () {
      final flow = BookingFlow(steps: merchantA())
        ..record(FlowStepType.service, service)
        ..next();

      // Choosing "any" records an explicit null, which must satisfy the step.
      expect(flow.canAdvance, isFalse);
      flow.record(FlowStepType.staff, null);
      expect(flow.canAdvance, isTrue);
      expect(flow.staff, isNull);
    });

    test('progress advances through the steps', () {
      final flow = BookingFlow(steps: merchantA());
      expect(flow.progress, closeTo(1 / 6, 0.001));
      flow.next();
      expect(flow.progress, closeTo(2 / 6, 0.001));
    });
  });

  group('changing an earlier answer', () {
    test('a new service clears the chosen time', () {
      final flow = BookingFlow(steps: merchantA())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..record(FlowStepType.time, '2026-09-15T15:00:00+03:00');

      expect(flow.slotStartsAt, isNotNull);

      // A 30-minute slot is not valid for a 120-minute service. Carrying it
      // forward would send an unbookable request to the server.
      flow.record(FlowStepType.service, const StoreService(
        id: 2, name: 'Hair Cut', price: 100, durationMinutes: 30,
      ));

      expect(flow.slotStartsAt, isNull, reason: 'A stale slot must not survive');
      expect(flow.date, isNull);
    });

    test('a new date clears the chosen time but keeps the service', () {
      final flow = BookingFlow(steps: merchantA())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..record(FlowStepType.time, '2026-09-15T15:00:00+03:00')
        ..record(FlowStepType.date, DateTime(2026, 9, 16));

      expect(flow.slotStartsAt, isNull);
      expect(flow.service, isNotNull);
    });
  });

  group('regression: the slot must survive staff assignment', () {
    test('recording the server-assigned staff before the time keeps the time', () {
      final flow = BookingFlow(steps: merchantA())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.date, DateTime(2026, 9, 15));

      // This is the order the time step uses: staff first, then time. Doing it
      // the other way round wiped starts_at and produced a booking the API
      // rejected with "The starts at field is required".
      flow.record(FlowStepType.staff, staff);
      flow.record(FlowStepType.time, '2026-09-15T15:00:00+03:00');

      expect(flow.slotStartsAt, '2026-09-15T15:00:00+03:00');
      expect(flow.toBookingPayload('8F72K')['starts_at'], isNotNull);
    });

    test('the reverse order loses the time, which is why order matters', () {
      final flow = BookingFlow(steps: merchantA())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..record(FlowStepType.time, '2026-09-15T15:00:00+03:00')
        ..record(FlowStepType.staff, staff);

      // Documenting the invalidation rule rather than lamenting it: changing
      // stylist genuinely invalidates a slot.
      expect(flow.slotStartsAt, isNull);
    });
  });

  group('the booking payload', () {
    test('carries only what the merchant actually collected', () {
      final flow = BookingFlow(steps: merchantB())
        ..record(FlowStepType.branch, branch)
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.time, '2026-09-15T15:00:00+03:00');

      final payload = flow.toBookingPayload('8F72K');

      expect(payload['store_token'], '8F72K');
      expect(payload['service_id'], 1);
      expect(payload['branch_id'], 3);
      // Merchant B hides staff, so no staff_id is invented.
      expect(payload.containsKey('staff_id'), isFalse);
    });

    test('includes staff when the customer chose one', () {
      final flow = BookingFlow(steps: merchantA())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.staff, staff)
        ..record(FlowStepType.time, '2026-09-15T15:00:00+03:00');

      expect(flow.toBookingPayload('8F72K')['staff_id'], 7);
    });

    test('drops blank notes rather than sending whitespace', () {
      final flow = BookingFlow(steps: merchantA())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.time, '2026-09-15T15:00:00+03:00')
        ..record(FlowStepType.notes, '   ');

      expect(flow.toBookingPayload('8F72K').containsKey('notes'), isFalse);
    });
  });

  group('unknown steps', () {
    test('are dropped rather than crashing the app', () {
      // A newer server may send a step type this build predates.
      final json = {
        'store': {'token': '8F72K', 'name': 'Glow Beauty'},
        'configuration': <String, dynamic>{},
        'flow': [
          {'step': 'service', 'required': true},
          {'step': 'loyalty_points', 'required': true},
          {'step': 'confirm', 'required': true},
        ],
        'services': <dynamic>[],
      };

      final store = Storefront.fromJson(json);

      expect(store.flow.map((s) => s.type),
          [FlowStepType.service, FlowStepType.confirm]);
    });
  });

  group('QR token extraction', () {
    test('reads a full deep link', () {
      expect(
        StoreTokenParser.parse('https://wasla.sa/s/8F72KABC'),
        '8F72KABC',
      );
    });

    test('reads a bare token', () {
      expect(StoreTokenParser.parse('8F72KABC'), '8F72KABC');
    });

    test('tolerates a query string on a printed code', () {
      expect(
        StoreTokenParser.parse('https://wasla.sa/s/8F72KABC?utm_source=print'),
        '8F72KABC',
      );
    });

    test('folds characters a hand-typed code may get wrong', () {
      // The alphabet excludes 0 1 I L O U, so a typed O must mean D — the same
      // folding the server applies.
      expect(StoreTokenParser.parse('8F72KABD'), '8F72KABD');
      expect(StoreTokenParser.parse('8f72kabo'), '8F72KABD');
      expect(StoreTokenParser.parse('8F72-KABD'), '8F72KABD');
    });

    test('rejects a code that is not ours', () {
      // Scanning someone else's QR must fail as not-ours, not be salvaged into
      // a plausible token that 404s.
      expect(StoreTokenParser.parse('https://example.com'), isNull);
      expect(StoreTokenParser.parse('https://example.com/s'), isNull);
      expect(StoreTokenParser.parse('WIFI:S:MyNetwork;T:WPA;P:secret;;'), isNull);
      expect(StoreTokenParser.parse('tel:+966501234567'), isNull);
      expect(StoreTokenParser.parse(''), isNull);
      expect(StoreTokenParser.parse(null), isNull);
    });

    test('rejects a token of the wrong length', () {
      expect(StoreTokenParser.parse('8F72K'), isNull);
      expect(StoreTokenParser.parse('8F72KABCDEF'), isNull);
    });
  });
}
