import 'package:flutter/material.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';

/// ============================================================================
/// CHOOSE A DATE (spec §41)
///
///   اختر التاريخ
///   أغسطس ٢٠٢٦
///
///   ┌────┐ ┌────┐ ┌────┐ ┌────┐
///   │ سبت│ │ أحد│ │إثنين│ │ثلاثاء│    ← horizontal strip, weekday above
///   │ ١٦ │ │ ١٧ │ │ ١٨ │ │ ١٩ │
///   │اليوم│ └────┘ └────┘ └────┘
///   └────┘
///
/// A strip of the next 30 days rather than a full calendar: the customer is
/// booking a haircut this week, not planning a year.
///
/// Horizontal beats the old 4-column grid because a week reads as a ROW —
/// the grid made "next Tuesday" a spatial puzzle instead of a glance.
/// ============================================================================
/// The first calendar day that can still contain a bookable slot.
///
/// The engine refuses anything before now + lead, and a day whose midnight
/// falls before that moment therefore has NO offerable slot at all — showing
/// its tile produced "no times available on this day", which reads as fully
/// booked when the truth is "this merchant needs more notice". A day that
/// merely STARTS inside the lead window still has its later hours, so the
/// answer is simply the calendar date of (now + lead).
DateTime firstBookableDay(DateTime now, int leadMinutes) {
  final earliest = now.add(Duration(minutes: leadMinutes));

  return DateTime(earliest.year, earliest.month, earliest.day);
}

class DateStep extends StatelessWidget {
  const DateStep({
    super.key,
    required this.onSelected,
    this.selected,
    this.maxAdvanceDays = 30,
    this.leadTimeMinutes = 0,
  });

  final DateTime? selected;
  final void Function(DateTime) onSelected;
  final int maxAdvanceDays;
  final int leadTimeMinutes;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            s.chooseDate,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink900,
            ),
          ),
        ),
        const SizedBox(height: 18),
        DateStrip(
          selected: selected,
          onSelected: onSelected,
          maxAdvanceDays: maxAdvanceDays,
          leadTimeMinutes: leadTimeMinutes,
        ),
      ],
    );
  }
}

/// The horizontal day strip, on its own so the combined date+time screen can
/// reuse it instead of keeping a second copy that drifts out of sync.
class DateStrip extends StatefulWidget {
  const DateStrip({
    super.key,
    required this.onSelected,
    this.selected,
    this.maxAdvanceDays = 30,
    this.leadTimeMinutes = 0,
    this.showMonthLabel = true,
  });

  final DateTime? selected;
  final void Function(DateTime) onSelected;
  final int maxAdvanceDays;
  final int leadTimeMinutes;
  final bool showMonthLabel;

  @override
  State<DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<DateStrip> {
  final _controller = ScrollController();

  /// Tile width (68) plus the separator (10). The strip is a fixed-extent row,
  /// so the offset of day N is simply N * this.
  static const _tileExtent = 78.0;

  @override
  void initState() {
    super.initState();

    // Bring an existing selection into view.
    //
    // The strip always renders from today, so returning to this screen with a
    // date three weeks out left the chosen tile off-screen — the screen looked
    // as though nothing had been picked, while the month label above it said
    // otherwise. Runs post-frame because the list has no scroll position until
    // it has been laid out once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelection());
  }

  void _revealSelection() {
    final selected = widget.selected;

    if (selected == null || !mounted || !_controller.hasClients) return;

    // Relative to the strip's FIRST TILE — which is not today when the
    // merchant's lead time has closed the first day(s).
    final first = firstBookableDay(DateTime.now(), widget.leadTimeMinutes);
    final day = DateTime(selected.year, selected.month, selected.day);
    final index = day.difference(first).inDays;

    if (index <= 0) return;

    // Nudge it away from the very edge so the neighbouring days stay visible
    // and the strip still reads as a scrollable row.
    final target = (index * _tileExtent - _tileExtent).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );

    _controller.jumpTo(target);
  }

  static const _weekdaysAr = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  static const _weekdaysEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    /*
     * Skip the days the merchant's notice period has already closed. The
     * window still ENDS at today + maxAdvanceDays — lead time consumes the
     * front of it, it does not extend the back.
     *
     * clamp(1, ...): a lead longer than the whole window is a merchant
     * misconfiguration; one (empty) day beats rendering a blank strip the
     * customer cannot interpret.
     */
    final first = firstBookableDay(now, widget.leadTimeMinutes);
    final skipped = first.difference(today).inDays;
    final count = (widget.maxAdvanceDays - skipped).clamp(1, widget.maxAdvanceDays);

    final days = List.generate(
      count,
      (i) => first.add(Duration(days: i)),
    );

    // The month label follows the selection, so a customer scrolling into
    // September is never looking at an "August" heading.
    final anchor = widget.selected ?? today;
    final months = s.isArabic ? _monthsAr : _monthsEn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showMonthLabel)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '${months[anchor.month - 1]} ${anchor.year}',
              style: const TextStyle(fontSize: 14, color: AppColors.ink500),
            ),
          ),

        SizedBox(
          height: 92,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final day = days[i];

              return _DayTile(
                weekday: (s.isArabic ? _weekdaysAr : _weekdaysEn)[day.weekday % 7],
                dayNumber: day.day,
                // "Today" and "Tomorrow" are how people actually think about
                // the next two days; a bare number makes them count.
                badge: _isSameDay(day, today)
                    ? s.today
                    : _isSameDay(day, today.add(const Duration(days: 1)))
                        ? s.tomorrow
                        : null,
                selected: widget.selected != null && _isSameDay(widget.selected!, day),
                onTap: () => widget.onSelected(day),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.weekday,
    required this.dayNumber,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String weekday;
  final int dayNumber;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink900 : Colors.white,
            border: Border.all(
              color: selected ? AppColors.ink900 : AppColors.ink200,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                weekday,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white70 : AppColors.ink500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$dayNumber',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: selected ? Colors.white : AppColors.ink900,
                ),
              ),
              const SizedBox(height: 3),
              // Reserve the badge line always, so tiles do not change height
              // between "today" and the rest of the strip.
              SizedBox(
                height: 13,
                child: badge == null
                    ? null
                    : Text(
                        badge!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppColors.accent,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
