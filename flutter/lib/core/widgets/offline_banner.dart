import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connectivity.dart';
import '../localization/strings.dart';
import '../theme/app_theme.dart';

/// A slim global bar that slides down from the top whenever the device is
/// offline, and slides away when the connection returns. Mounted once, above
/// every screen (via the app's builder), so no screen has to handle it.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider).value ?? false;
    final s = Strings.of(context);

    return IgnorePointer(
      child: AnimatedSlide(
        offset: offline ? Offset.zero : const Offset(0, -1),
        duration: AppMotion.dur(context, AppMotion.base),
        curve: AppMotion.curve,
        child: AnimatedOpacity(
          opacity: offline ? 1 : 0,
          duration: AppMotion.dur(context, AppMotion.base),
          child: Material(
            color: AppColors.ink900,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      s.offline,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
