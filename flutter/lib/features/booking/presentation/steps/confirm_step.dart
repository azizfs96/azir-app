import 'package:flutter/material.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../stores/domain/storefront.dart';
import '../../../stores/presentation/store_avatar.dart';
import '../../domain/booking_flow.dart';

/// ============================================================================
/// CONFIRM THE BOOKING — the last screen before it is real (spec §41)
///
///   ┌──────────────────────────────────┐
///   │  🗓  الخميس ١٩ أغسطس              │  ← the appointment, given the
///   │      ٧:٠٠ م — ٩:٠٠ م              │     weight it actually carries
///   └──────────────────────────────────┘
///
///   الخدمة        صبغة شعر
///   الموظف        سارة
///   الفرع         العليا
///   ──────────────────────
///   الإجمالي      ٢٥٠ ر.س
///   الدفع في الفرع
///
///   يمكنك الإلغاء مجاناً حتى ٤ ساعات قبل موعدك.
///
///   [        تأكيد الحجز        ]
///
/// DATE AND TIME LEAD. The previous version buried them in a summary row
/// labelled "choose a time", so a booking whose slot had been silently dropped
/// looked no different from a valid one — which is exactly how a real bug went
/// unnoticed until the API rejected the request.
/// ============================================================================
class ConfirmStep extends StatelessWidget {
  const ConfirmStep({
    super.key,
    required this.store,
    required this.flow,
    required this.s,
    required this.submitting,
    required this.onConfirm,
  });

  final Storefront store;
  final BookingFlow flow;
  final Strings s;
  final bool submitting;
  final VoidCallback onConfirm;

  Color get _brand => brandColorOf(store.brandColor);

  static const _weekdaysAr = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  static const _weekdaysEn = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatDate(DateTime when) {
    final weekday = (s.isArabic ? _weekdaysAr : _weekdaysEn)[when.weekday % 7];
    final month = (s.isArabic ? _monthsAr : _monthsEn)[when.month - 1];

    return '$weekday ${when.day} $month';
  }

  String _formatTime(DateTime when) {
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    final period = s.isArabic
        ? (when.hour < 12 ? 'ص' : 'م')
        : (when.hour < 12 ? 'AM' : 'PM');

    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(flow.slotStartsAt ?? '');
    final service = flow.service;
    final end = (start != null && service != null)
        ? start.add(Duration(minutes: service.durationMinutes))
        : null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Text(
                s.confirmBooking,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink900,
                ),
              ),
              const SizedBox(height: 18),

              // Who it is with.
              Row(
                children: [
                  StoreAvatar(
                    name: store.name,
                    logoPath: store.logo,
                    brandColor: store.brandColor,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              /*
               * THE APPOINTMENT — the single most important fact on screen.
               *
               * If the slot is somehow missing, say so loudly instead of
               * rendering a confident-looking card with a hole in it.
               */
              if (start == null)
                _MissingSlotWarning(s: s)
              else
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _brand.withValues(alpha: 0.06),
                    border: Border.all(color: _brand.withValues(alpha: 0.25)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.event_rounded, size: 21, color: _brand),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatDate(start),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              end == null
                                  ? _formatTime(start)
                                  // Showing the end time answers "how long am
                                  // I here for" without arithmetic.
                                  : '${_formatTime(start)} — ${_formatTime(end)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 18),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.ink200),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    if (service != null)
                      _Row(
                        label: s.serviceLabel,
                        value: service.name,
                        trailing: s.minutes(service.durationMinutes),
                      ),

                    // Staff is shown only when the merchant exposes it (§9) —
                    // otherwise the customer never chose, and naming whoever
                    // the engine assigned would be a promise we did not make.
                    if (flow.staff != null && store.configuration.staffSelection)
                      _Row(label: s.staffLabel, value: flow.staff!.name),

                    if (flow.branch != null)
                      _Row(label: s.branchLabel, value: flow.branch!.name),

                    if (flow.notes != null && flow.notes!.trim().isNotEmpty)
                      _Row(label: s.notesLabel, value: flow.notes!.trim()),

                    const Divider(height: 1, color: AppColors.ink200),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          Text(
                            s.total,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink900,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${service?.price.toStringAsFixed(0) ?? '0'} ${s.currency}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink900,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Payments are descoped for the MVP, so this is a statement
                    // of fact, not a payment method choice.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      decoration: const BoxDecoration(
                        color: AppColors.ink50,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_outlined,
                              size: 15, color: AppColors.ink500),
                          const SizedBox(width: 8),
                          Text(
                            s.payAtStore,
                            style: const TextStyle(fontSize: 13, color: AppColors.ink500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // The cancellation policy is shown BEFORE confirming (spec §21).
              if (store.cancellationPolicy?.text != null) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 15, color: AppColors.ink400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        store.cancellationPolicy!.text!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: AppColors.ink500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // The commit button sits on its own surface so it never scrolls away.
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.ink200)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton(
                // Refuse to submit a booking with no slot rather than letting
                // the API reject it after a spinner.
                onPressed: (submitting || start == null) ? null : onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  disabledBackgroundColor: AppColors.ink200,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        s.confirmBooking,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13.5, color: AppColors.ink500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: AppColors.ink900,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.ink400),
            ),
          ],
        ],
      ),
    );
  }
}

/// Should never appear — but if the slot went missing, saying so beats a
/// confident summary with a hole where the appointment ought to be.
class _MissingSlotWarning extends StatelessWidget {
  const _MissingSlotWarning({required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.badSoft,
        border: Border.all(color: AppColors.bad.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 19, color: AppColors.bad),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.missingSlot,
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.bad),
            ),
          ),
        ],
      ),
    );
  }
}
