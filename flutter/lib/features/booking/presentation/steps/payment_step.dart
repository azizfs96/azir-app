import 'package:flutter/material.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';

/// Payment step (spec §20).
///
/// Online payment is out of scope for the MVP, so the server always sends
/// mode 'pay_at_store'. The step still exists — the customer should know how
/// and when they pay before confirming, not discover it at the counter.
///
/// The `deposit` / `full` branches are the seam for turning payments on later.
class PaymentStep extends StatelessWidget {
  const PaymentStep({super.key, required this.mode, required this.onContinue});

  final String mode;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                s.payment,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink900,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.ink200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: AppColors.ink500),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.payAtStore,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.payAtStoreHint,
                            style: const TextStyle(fontSize: 13, color: AppColors.ink500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton(onPressed: onContinue, child: Text(s.next)),
          ),
        ),
      ],
    );
  }
}
