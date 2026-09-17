import 'package:flutter/widgets.dart';
import '../../core/motion/app_motion.dart';

/// Fades the active destination without remounting the retained tab stack.
class TabContentTransition extends StatefulWidget {
  const TabContentTransition(
      {super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<TabContentTransition> createState() => _TabContentTransitionState();
}

class _TabContentTransitionState extends State<TabContentTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  late final Animation<double> _opacity = Tween(begin: .82, end: 1.0)
      .animate(CurvedAnimation(parent: _controller, curve: AppMotion.curve));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.duration(context, 180);
    if (_controller.duration == Duration.zero) _controller.value = 1;
  }

  @override
  void didUpdateWidget(TabContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (_controller.duration == Duration.zero) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
