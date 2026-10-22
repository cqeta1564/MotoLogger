import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../core/motion/app_motion.dart';

/// Tactile Apple-style touch scale micro-interaction (scales to 0.97 on press).
/// Uses physical spring recovery and bypasses instantly when reduce_motion is enabled.
class AppleScaleButton extends StatefulWidget {
  const AppleScaleButton({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.hapticFeedback = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool hapticFeedback;
  final HitTestBehavior behavior;

  @override
  State<AppleScaleButton> createState() => _AppleScaleButtonState();
}

class _AppleScaleButtonState extends State<AppleScaleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _isReducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.pressedScale).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: const Cubic(0.175, 0.885, 0.32, 1.275), // Apple bounce-back
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isReducedMotion = AppMotion.isReducedMotion(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) {
    if (widget.onPressed == null && widget.onLongPress == null) return;
    if (!_isReducedMotion) {
      _controller.forward();
    }
  }

  void _onPointerUp(PointerUpEvent _) {
    if (widget.onPressed == null && widget.onLongPress == null) return;
    if (!_isReducedMotion) {
      _controller.reverse();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (widget.onPressed == null && widget.onLongPress == null) return;
    if (!_isReducedMotion) {
      _controller.reverse();
    }
  }

  void _onTap() {
    if (widget.onPressed == null) return;
    if (widget.hapticFeedback) {
      HapticFeedback.selectionClick();
    }
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null || widget.onLongPress != null;
    if (!enabled || _isReducedMotion) {
      return GestureDetector(
        onTap: widget.onPressed == null ? null : _onTap,
        onLongPress: widget.onLongPress,
        behavior: widget.behavior,
        child: widget.child,
      );
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      behavior: widget.behavior,
      child: GestureDetector(
        onTap: _onTap,
        onLongPress: widget.onLongPress,
        behavior: widget.behavior,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}
