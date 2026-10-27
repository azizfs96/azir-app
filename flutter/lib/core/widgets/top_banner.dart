import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A heads-up notification that slides down from the top of the screen, floats
/// above everything (app bar included), and dismisses itself after a moment —
/// the in-app equivalent of a system push banner. Tap or swipe up to dismiss.
///
/// Reusable: any screen can announce a moment without giving up layout space.
/// Honours reduce-motion (appears/leaves instantly) and is RTL-safe.
void showTopBanner(
  BuildContext context, {
  required String title,
  String? message,
  IconData icon = Icons.check_circle_rounded,
  Color accent = AppColors.ok,
  Duration stay = const Duration(seconds: 4),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopBanner(
      title: title,
      message: message,
      icon: icon,
      accent: accent,
      stay: stay,
      onGone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _TopBanner extends StatefulWidget {
  const _TopBanner({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
    required this.stay,
    required this.onGone,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Color accent;
  final Duration stay;
  final VoidCallback onGone;

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Duration is resolved in didChangeDependencies where MediaQuery (and the
    // reduce-motion flag) is available.
    _timer = Timer(widget.stay, _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.duration = AppMotion.dur(context, AppMotion.base);
    if (_c.status == AnimationStatus.dismissed && !_leaving) _c.forward();
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted) await _c.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: AppMotion.curve);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(curve),
            child: FadeTransition(
              opacity: curve,
              child: _card(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _dismiss,
        // Swipe up to dismiss, like a real heads-up notification.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < 0) _dismiss();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: Color(0x24000000), blurRadius: 22, offset: Offset(0, 10)),
            ],
            border: Border.all(color: AppColors.ink100),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: widget.accent, shape: BoxShape.circle),
                child: Icon(widget.icon, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                    if (widget.message != null && widget.message!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(widget.message!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.ink500, height: 1.35)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.ink300, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
