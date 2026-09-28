import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../booking/data/booking_repository.dart';
import '../../booking/data/store_bookings_provider.dart';
import 'storefront_states.dart';

/// ============================================================================
/// THE CUSTOMER'S HISTORY AT THIS MERCHANT
///
/// Scoped by store_token, so a merchant's page shows that merchant's bookings
/// and nothing else — the customer's other merchants are none of this page's
/// business (spec §46).
/// ============================================================================
class StorefrontBookingsSliver extends ConsumerWidget {
  const StorefrontBookingsSliver({super.key, required this.token, required this.s});

  final String token;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(storeBookingsProvider(token));

    return bookings.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, _) => SliverToBoxAdapter(
        child: StorefrontPlaceholder(icon: Icons.error_outline_rounded, title: s.error),
      ),
      data: (data) {
        if (data.isEmpty) {
          return SliverToBoxAdapter(
            child: StorefrontPlaceholder(
              icon: Icons.event_note_outlined,
              title: s.noBookingsHere,
              hint: s.noBookingsHereHint,
            ),
          );
        }

        final rows = <Widget>[
          if (data.upcoming.isNotEmpty) ...[
            _SectionLabel(text: s.upcomingSection),
            ...data.upcoming.map((b) => BookingTile(booking: b, s: s, highlight: true)),
            const SizedBox(height: 18),
          ],
          if (data.past.isNotEmpty) ...[
            _SectionLabel(text: s.pastSection),
            ...data.past.map((b) => BookingTile(booking: b, s: s, highlight: false)),
          ],
        ];

        return SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
          sliver: SliverList.list(children: rows),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink500,
        ),
      ),
    );
  }
}

class BookingTile extends StatelessWidget {
  const BookingTile({
    super.key,
    required this.booking,
    required this.s,
    required this.highlight,
  });

  final BookingResult booking;
  final Strings s;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final when = DateTime.tryParse(booking.startsAt);
    final status = _statusStyle(booking.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.serviceName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    // Past bookings recede; the next appointment leads.
                    color: highlight ? AppColors.ink900 : AppColors.ink700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status.$2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  s.status(booking.status),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: status.$1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.ink400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  when == null ? booking.startsAt : _formatWhen(when),
                  style: const TextStyle(fontSize: 13, color: AppColors.ink500),
                ),
              ),
              Text(
                '${booking.price.toStringAsFixed(0)} ${s.currency}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink700,
                ),
              ),
            ],
          ),
          if (booking.staffName != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 13, color: AppColors.ink400),
                const SizedBox(width: 6),
                Text(
                  booking.staffName!,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink500),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // The reference is what a customer reads out at the counter.
          Text(
            booking.reference,
            style: const TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: AppColors.ink400,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatWhen(DateTime when) {
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    final period = when.hour < 12 ? 'AM' : 'PM';

    return '${when.day}/${when.month}/${when.year}  ·  $hour:$minute $period';
  }

  /// (foreground, background) per booking status (spec §19).
  static (Color, Color) _statusStyle(String status) => switch (status) {
        'confirmed' => (AppColors.info, AppColors.infoSoft),
        'pending' => (AppColors.warn, AppColors.warnSoft),
        'checked_in' => (AppColors.accent, AppColors.accentSoft),
        'completed' => (AppColors.ok, AppColors.okSoft),
        'no_show' => (AppColors.bad, AppColors.badSoft),
        _ => (AppColors.ink500, AppColors.ink100),
      };
}
