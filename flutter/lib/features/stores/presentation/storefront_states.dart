import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';

/// Empty / error states shared across the storefront.
class StorefrontPlaceholder extends StatelessWidget {
  const StorefrontPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.ink300),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.ink900,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.ink500),
            ),
          ],
        ],
      ),
    );
  }
}

/// The server could not be reached at all — offer a retry, not a dead end.
class StorefrontUnreachable extends StatelessWidget {
  const StorefrontUnreachable({super.key, required this.s, required this.onRetry});

  final Strings s;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.ink300),
            const SizedBox(height: 16),
            Text(
              s.cannotReachServer,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.cannotReachServerHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.ink500),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
              child: Text(s.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class StorefrontNotFound extends StatelessWidget {
  const StorefrontNotFound({super.key, required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 48, color: AppColors.ink300),
            const SizedBox(height: 16),
            Text(
              s.invalidCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink900,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => context.go('/'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
              child: Text(s.backToHome),
            ),
          ],
        ),
      ),
    );
  }
}
