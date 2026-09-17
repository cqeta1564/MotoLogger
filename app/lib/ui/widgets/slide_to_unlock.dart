import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Drag control with an accessible action and no decorative looping motion.
class SlideToUnlock extends StatefulWidget {
  final VoidCallback onUnlocked;
  final String label;
  final double height;
  final double width;

  const SlideToUnlock({
    super.key,
    required this.onUnlocked,
    this.label = 'PŘEJETÍM ODEMKNOUT ➔',
    this.height = 64.0,
    this.width = double.infinity,
  });

  @override
  State<SlideToUnlock> createState() => _SlideToUnlockState();
}

class _SlideToUnlockState extends State<SlideToUnlock>
    with TickerProviderStateMixin {
  double _dragPosition = 0.0;
  AnimationController? _resetController;
  Animation<double>? _resetAnimation;

  AnimationController get resetController =>
      _resetController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
      )..addListener(() {
          if (_resetAnimation != null) {
            setState(() {
              _dragPosition = _resetAnimation!.value;
            });
          }
        });

  @override
  void initState() {
    super.initState();
    resetController;
  }

  @override
  void dispose() {
    _resetController?.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (resetController.isAnimating) return;
    setState(() {
      _dragPosition =
          (_dragPosition + details.primaryDelta!).clamp(0.0, maxDrag);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details, double maxDrag) {
    if (_dragPosition >= maxDrag * 0.70) {
      // Completed unlock!
      HapticFeedback.heavyImpact();
      widget.onUnlocked();
      // Reset position after brief delay so it's ready when re-locked
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _dragPosition = 0.0);
        }
      });
    } else {
      if (MediaQuery.disableAnimationsOf(context)) {
        setState(() => _dragPosition = 0);
        return;
      }
      // Return the thumb after an incomplete gesture.
      _resetAnimation = Tween<double>(
        begin: _dragPosition,
        end: 0.0,
      ).animate(
          CurvedAnimation(parent: resetController, curve: Curves.easeOutCubic));
      resetController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    const thumbPadding = 5.0;
    final thumbSize = widget.height - (thumbPadding * 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth =
            widget.width.isFinite ? widget.width : constraints.maxWidth;
        final maxDrag = (totalWidth - thumbSize - (thumbPadding * 2))
            .clamp(0.0, double.infinity);

        final progress =
            maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return SizedBox(
          width: totalWidth,
          height: widget.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, maxDrag),
            onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, maxDrag),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(widget.height / 2),
                border: Border.all(color: const Color(0xFFE5E5EA), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Centered Shimmering Label (Iconic Apple "Slide to unlock" shimmer effect)
                  Center(
                    child: Opacity(
                      opacity: (1.0 - progress * 1.3).clamp(0.0, 1.0),
                      child: Padding(
                        padding: EdgeInsets.only(left: thumbSize),
                        child: Text(widget.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF63636B))),
                      ),
                    ),
                  ),

                  // Draggable Tactile Apple Knob
                  Positioned(
                    left: thumbPadding + _dragPosition,
                    child: Container(
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFF000000),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
