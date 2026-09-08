import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Horizontal Slide to Unlock slider widget.
/// 
/// The user drags the black thumb from left to right.
/// If released before completion, it springs back smoothly.
/// When reaching the end threshold, it triggers [onUnlocked] with haptic feedback.
class SlideToUnlock extends StatefulWidget {
  final VoidCallback onUnlocked;
  final String label;
  final double height;
  final double width;

  const SlideToUnlock({
    super.key,
    required this.onUnlocked,
    this.label = 'PŘEJETÍM ODEMKNOUT ➔',
    this.height = 68.0,
    this.width = double.infinity,
  });

  @override
  State<SlideToUnlock> createState() => _SlideToUnlockState();
}

class _SlideToUnlockState extends State<SlideToUnlock>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  late final AnimationController _resetController;
  Animation<double>? _resetAnimation;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (_resetAnimation != null) {
          setState(() {
            _dragPosition = _resetAnimation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (_resetController.isAnimating) return;
    setState(() {
      _dragPosition = (_dragPosition + details.primaryDelta!).clamp(0.0, maxDrag);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details, double maxDrag) {
    if (_dragPosition >= maxDrag * 0.85) {
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
      // Spring back to start
      _resetAnimation = Tween<double>(
        begin: _dragPosition,
        end: 0.0,
      ).animate(CurvedAnimation(parent: _resetController, curve: Curves.easeOutCubic));
      _resetController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    const thumbPadding = 6.0;
    final thumbSize = widget.height - (thumbPadding * 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = widget.width.isFinite ? widget.width : constraints.maxWidth;
        final maxDrag = (totalWidth - thumbSize - (thumbPadding * 2)).clamp(0.0, double.infinity);

        final progress = maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return SizedBox(
          width: totalWidth,
          height: widget.height,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: Border.all(color: const Color(0xFFE5E5EA), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Centered Label (fades slightly as thumb covers it)
                Center(
                  child: Opacity(
                    opacity: (1.0 - progress * 1.2).clamp(0.0, 1.0),
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                        fontFamily: '-apple-system',
                      ),
                    ),
                  ),
                ),

                // Draggable Black Thumb
                Positioned(
                  left: thumbPadding + _dragPosition,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, maxDrag),
                    onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, maxDrag),
                    child: Container(
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
