import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Briefly scales its child up and back whenever [value] increases — the little
/// "something just landed here" pulse used on the cart badge when an item is
/// added. A quick, self-reversing tap of motion (peak-end delight). Honors
/// reduce-motion (no pulse then).
class Bump extends StatefulWidget {
  const Bump({super.key, required this.value, required this.child});

  final int value;
  final Widget child;

  @override
  State<Bump> createState() => _BumpState();
}

class _BumpState extends State<Bump> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.28).chain(CurveTween(curve: Curves.easeOut)), weight: 45),
    TweenSequenceItem(
        tween: Tween(begin: 1.28, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 55),
  ]).animate(_c);

  @override
  void didUpdateWidget(Bump old) {
    super.didUpdateWidget(old);
    if (widget.value > old.value && !AppMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}
