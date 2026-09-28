import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../stores/data/store_repository.dart';

/// Time selection — the availability engine's output (spec §17).
///
/// Slots are fetched fresh every time this step is shown, never cached in the
/// app: an hour-old slot list is a booking failure waiting to happen.
class TimeStep extends ConsumerStatefulWidget {
  const TimeStep({
    super.key,
    required this.storeToken,
    required this.serviceId,
    required this.date,
    required this.onSelected,
    this.branchId,
    this.staffId,
    this.selectedSlot,
  });

  final String storeToken;
  final int serviceId;
  final DateTime date;
  final int? branchId;
  final int? staffId;
  final void Function(Slot) onSelected;

  /// `starts_at` of an already-chosen slot, so re-entering this step shows it.
  final String? selectedSlot;

  @override
  ConsumerState<TimeStep> createState() => _TimeStepState();
}

class _TimeStepState extends ConsumerState<TimeStep> {
  late Future<List<Slot>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Slot>> _load() => ref.read(storeRepositoryProvider).availability(
        storeToken: widget.storeToken,
        serviceId: widget.serviceId,
        date: widget.date,
        branchId: widget.branchId,
        staffId: widget.staffId,
      );

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return FutureBuilder<List<Slot>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.availabilityError, style: const TextStyle(color: AppColors.ink500)),
                const SizedBox(height: 12),
                OutlinedButton(
                  // Block body on purpose — see DateTimeStep's retry.
                  onPressed: () => setState(() {
                    _future = _load();
                  }),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
                  child: Text(s.retry),
                ),
              ],
            ),
          );
        }

        final slots = snapshot.data ?? const <Slot>[];

        // A fully booked day is normal, not an error — same message and same
        // guidance as the combined screen.
        if (slots.isEmpty) {
          return Center(child: NoSlotsMessage(s: s));
        }

        /*
         * Grouped by part of the day rather than one long wall of times.
         *
         * Nobody scans forty chips looking for 14:15 — they think "something
         * in the afternoon". A salon open 10:00–22:00 emits ~48 slots, and an
         * undifferentiated Wrap of them is the single densest thing in the app.
         */
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              s.chooseTime,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink900,
              ),
            ),
            const SizedBox(height: 20),
            SlotPicker(
              slots: slots,
              s: s,
              selectedStartsAt: widget.selectedSlot,
              onSelected: widget.onSelected,
            ),
          ],
        );
      },
    );
  }
}

/// The fully-booked-day message, shared for the same reason as SlotPicker:
/// the standalone step used to show a bare sentence with no guidance while
/// the combined screen had icon + explanation + "try another day", and the
/// two drifted apart because they were written twice.
class NoSlotsMessage extends StatelessWidget {
  const NoSlotsMessage({super.key, required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
      child: Column(
        children: [
          const Icon(Icons.event_busy_rounded, size: 40, color: AppColors.ink300),
          const SizedBox(height: 14),
          Text(
            s.noSlots,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.tryAnotherDay,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: AppColors.ink500),
          ),
        ],
      ),
    );
  }
}

/// The grouped slot list, shared by the standalone time step and the combined
/// date+time screen so the two never drift apart.
class SlotPicker extends StatelessWidget {
  const SlotPicker({
    super.key,
    required this.slots,
    required this.s,
    required this.onSelected,
    this.selectedStartsAt,
  });

  final List<Slot> slots;
  final Strings s;
  final void Function(Slot) onSelected;

  /// The already-chosen slot's `starts_at`, so returning to this screen shows
  /// what the customer picked instead of a list with nothing marked.
  final String? selectedStartsAt;

  @override
  Widget build(BuildContext context) {
    /*
     * ONE TIME, ONE CHIP.
     *
     * When the customer asked for "any available" stylist, the server sends
     * one slot per (time, stylist) pair — so 12:00 arrived twice, identical
     * but for a small name, and the count doubled with it. The customer
     * already said they do not care who; collapse to distinct start times,
     * keeping the FIRST slot so its stylist still becomes the assignment.
     *
     * Safe unconditionally: a request filtered to one stylist cannot contain
     * duplicate start times, so this is a no-op everywhere else.
     */
    final visible = _dedupeByStart(slots);
    final periods = _groupByPeriod(visible);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.slotsAvailable(visible.length),
          style: const TextStyle(fontSize: 13.5, color: AppColors.ink500),
        ),
        const SizedBox(height: 16),
        for (final entry in periods.entries) ...[
          Row(
            children: [
              Icon(entry.key.icon, size: 15, color: AppColors.ink400),
              const SizedBox(width: 7),
              Text(
                entry.key.label(s),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: AppColors.ink100)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final slot in entry.value)
                _SlotChip(
                  slot: slot,
                  selected: selectedStartsAt != null && slot.startsAt == selectedStartsAt,
                  onTap: () => onSelected(slot),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

/// Distinct start times, first occurrence wins (see SlotPicker.build).
List<Slot> _dedupeByStart(List<Slot> slots) {
  final seen = <String>{};

  return [
    for (final slot in slots)
      if (seen.add(slot.startsAt)) slot,
  ];
}

/// Morning / afternoon / evening — the way people describe an appointment.
enum _Period {
  morning(Icons.wb_twilight_rounded),
  afternoon(Icons.wb_sunny_rounded),
  evening(Icons.nightlight_round);

  const _Period(this.icon);

  final IconData icon;

  String label(Strings s) => switch (this) {
        _Period.morning => s.morning,
        _Period.afternoon => s.afternoon,
        _Period.evening => s.evening,
      };
}

/// Bucket slots by hour, preserving order and dropping empty periods.
Map<_Period, List<Slot>> _groupByPeriod(List<Slot> slots) {
  final grouped = <_Period, List<Slot>>{};

  for (final slot in slots) {
    // slot.time is "HH:mm" in the store's own timezone, already localised by
    // the server — parsing the hour here avoids a second timezone conversion.
    final hour = int.tryParse(slot.time.split(':').first) ?? 0;

    final period = hour < 12
        ? _Period.morning
        : hour < 17
            ? _Period.afternoon
            : _Period.evening;

    grouped.putIfAbsent(period, () => []).add(slot);
  }

  // Stable order regardless of what the server sent first.
  return {
    for (final period in _Period.values)
      if (grouped[period] != null) period: grouped[period]!,
  };
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.onTap, this.selected = false});

  final Slot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Matches the day tile's selected treatment, so a chosen time and a chosen
    // day read as the same kind of answer.
    return Material(
      color: selected ? AppColors.ink900 : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          // vertical 13 lifts the chip past the 44pt/48dp minimum touch
          // target; at 11 the most-tapped control in the app was ~40px tall.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.ink900 : AppColors.ink200,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                slot.time,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.ink900,
                ),
              ),
              // Only present when the merchant exposes staff — otherwise the
              // server sent times only (spec §9).
              if (slot.staffName != null && slot.staffName!.isNotEmpty)
                Text(
                  slot.staffName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: selected ? Colors.white70 : AppColors.ink400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
