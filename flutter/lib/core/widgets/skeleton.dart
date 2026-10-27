import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A lightweight loading placeholder — no external package. A single quiet pulse
/// (opacity only, so it is cheap) hints "content is coming" in the exact shape
/// the real content will take, which avoids both a bare spinner and a white
/// flash. Honours reduce-motion: the block is drawn static, never pulsing.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.color,
  });

  final double? width;
  final double height;
  final double radius;
  final Color? color;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? AppColors.ink100;
    final box = DecoratedBox(
      decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(widget.radius)),
      child: SizedBox(width: widget.width, height: widget.height),
    );

    // Reduce-motion: a still block, no pulse.
    if (AppMotion.reduced(context)) return box;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: box,
    );
  }
}

/// A full-width skeleton "card" block, matching the rounded white cards used
/// across the order screens so the swap to real content causes no layout jump.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 96});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(height: height, radius: 20, color: Colors.white);
  }
}
