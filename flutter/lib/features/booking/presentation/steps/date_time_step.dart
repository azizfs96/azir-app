import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../stores/data/store_repository.dart';
import 'date_step.dart';
import 'time_step.dart';

/// ============================================================================
/// DATE AND TIME ON ONE SCREEN (spec §41 "do not add unnecessary screens")
///
///   اختر الموعد
///   أغسطس ٢٠٢٦
///   ┌────┐ ┌────┐ ┌────┐
///   │ سبت│ │ أحد│ │إثنين│      ← pick a day
///   │ ١٦ │ │ ١٧ │ │ ١٨ │
///   └────┘ └────┘ └────┘
///   ─────────────────────
///   🌅 صباحاً
///   [١٠:٠٠] [١٠:١٥] [١٠:٣٠]     ← times reload under it
///
/// Two taps that used to be two screens. Seeing times appear under the day you
/// just picked also makes a fully booked date obvious immediately, instead of
/// after a screen transition that has to be undone.
///
/// NOTE ON THE SERVER-DRIVEN FLOW: the server still decides whether `date` and
/// `time` exist and in what order. This screen is only a PRESENTATION choice —
/// when those two steps happen to be adjacent, they are drawn together and the
/// controller advances past both. An engine that sends a date without a time
/// still gets the plain DateStep.
/// ============================================================================
class DateTimeStep extends ConsumerStatefulWidget {
  const DateTimeStep({
    super.key,
    required this.storeToken,
    required this.serviceId,
    required this.s,
    required this.brand,
    required this.selectedDate,
    required this.onPicked,
    this.selectedSlot,
    this.branchId,
    this.staffId,
    this.maxAdvanceDays = 30,
    this.leadTimeMinutes = 0,
  });

  final String storeToken;
  final int serviceId;
  final Strings s;
  final Color brand;
  final DateTime? selectedDate;

  /// `starts_at` of an already-chosen slot. Returning to this screen used to
  /// show the right day with nothing marked in the slot list, so the customer
  /// had to remember which time they had picked.
  final String? selectedSlot;

  final int? branchId;
  final int? staffId;
  final int maxAdvanceDays;
  final int leadTimeMinutes;

  /// Fires once, carrying both answers.
  final void Function(DateTime date, Slot slot) onPicked;

  @override
  ConsumerState<DateTimeStep> createState() => _DateTimeStepState();
}

class _DateTimeStepState extends ConsumerState<DateTimeStep> {
  late DateTime _date;
  late Future<List<Slot>> _slots;

  @override
  void initState() {
    super.initState();

    /*
     * Default to the first day that can actually have slots. Defaulting to
     * plain "today" meant a customer opening the flow late in the evening —
     * or at a merchant needing a day's notice — landed on a day the engine
     * always answers with an empty list, and read it as "fully booked".
     */
    _date = widget.selectedDate ??
        firstBookableDay(DateTime.now(), widget.leadTimeMinutes);
    _slots = _load();
  }

  Future<List<Slot>> _load() => ref.read(storeRepositoryProvider).availability(
        storeToken: widget.storeToken,
        serviceId: widget.serviceId,
        date: _date,
        branchId: widget.branchId,
        staffId: widget.staffId,
      );

  void _pickDate(DateTime date) {
    setState(() {
      _date = date;
      // Slots are refetched on every date change and never cached in the app —
      // an hour-old slot list is a booking failure waiting to happen.
      _slots = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            s.chooseDateTime,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink900,
            ),
          ),
        ),
        const SizedBox(height: 14),

        DateStrip(
          selected: _date,
          onSelected: _pickDate,
          maxAdvanceDays: widget.maxAdvanceDays,
          leadTimeMinutes: widget.leadTimeMinutes,
        ),

        const SizedBox(height: 22),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(height: 1, color: AppColors.ink200),
        ),
        const SizedBox(height: 20),

        FutureBuilder<List<Slot>>(
          future: _slots,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.availabilityError,
                          style: const TextStyle(color: AppColors.ink500)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        // Block body on purpose: an arrow body RETURNS the
                        // Future from _load(), and setState() asserts on a
                        // returned Future — the press threw instead of
                        // retrying.
                        onPressed: () => setState(() {
                          _slots = _load();
                        }),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
                        child: Text(s.retry),
                      ),
                    ],
                  ),
                ),
              );
            }

            final slots = snapshot.data ?? const <Slot>[];

            // A fully booked day is normal, not an error — and here the
            // customer can just tap another day without leaving the screen.
            if (slots.isEmpty) {
              return NoSlotsMessage(s: s);
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SlotPicker(
                slots: slots,
                s: s,
                selectedStartsAt: widget.selectedSlot,
                onSelected: (slot) => widget.onPicked(_date, slot),
              ),
            );
          },
        ),
      ],
    );
  }
}
