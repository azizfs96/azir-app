import 'package:flutter/material.dart';

import '../localization/strings.dart';
import '../theme/app_theme.dart';

/// A calm, in-context error surfaced right next to the action that failed —
/// a clear message plus an optional retry — instead of a transient snackbar that
/// floats away from the button the customer just pressed. RTL-aware by default.
///
/// Reused by the checkout bar and anywhere an action needs a local failure state.
class InlineError extends StatelessWidget {
  const InlineError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
    this.icon = Icons.wifi_off_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.badSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x33B42318)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.bad, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.bad, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.bad,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(retryLabel ?? s.retry, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
