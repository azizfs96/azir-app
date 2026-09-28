import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../data/booking_repository.dart';

/// Booking confirmed (spec §41 — the end of the journey).
class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key, required this.booking});

  final BookingResult booking;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final when = DateTime.tryParse(booking.startsAt);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.okSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, size: 40, color: AppColors.ok),
              ),
              const SizedBox(height: 24),
              Text(
                s.bookingConfirmed,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                booking.storeName ?? '',
                style: const TextStyle(fontSize: 15, color: AppColors.ink500),
              ),
              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.ink200),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      s.bookingReference,
                      style: const TextStyle(fontSize: 12, color: AppColors.ink400),
                    ),
                    const SizedBox(height: 4),
                    // Spoken over the phone, so it uses an unambiguous alphabet
                    // and is always rendered LTR.
                    Text(
                      booking.reference,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppColors.ink900,
                      ),
                    ),
                    if (when != null) ...[
                      const Divider(height: 28),
                      Text(
                        '${when.day}/${when.month}/${when.year} • '
                        '${when.hour.toString().padLeft(2, '0')}:'
                        '${when.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink900,
                        ),
                      ),
                    ],
                    if (booking.serviceName != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        booking.serviceName!,
                        style: const TextStyle(fontSize: 14, color: AppColors.ink500),
                      ),
                    ],
                  ],
                ),
              ),

              const Spacer(),
              FilledButton(
                /*
                 * Back to the STORE, not the app home.
                 *
                 * The customer just booked inside a merchant's storefront —
                 * their "back to the beginning" is that store's page (to see
                 * the booking now in "حجوزاتي", or book again), not the app's
                 * list of every store. go() replaces the whole stack so the
                 * finished booking flow cannot be swiped back into.
                 *
                 * The app home is the fallback only for a booking that somehow
                 * carries no store token.
                 */
                onPressed: () => context.go(
                  booking.storeToken != null ? '/s/${booking.storeToken}' : '/',
                ),
                child: Text(s.backToStore),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
