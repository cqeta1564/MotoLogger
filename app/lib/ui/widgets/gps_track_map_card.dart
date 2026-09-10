import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../core/theme/app_theme.dart';
import '../../models/fused_sample.dart';

enum GpsTrackColorMode {
  lean,
  speed,
}

/// Interactive GPS Track Map Card displaying the motorcycle trajectory on an offline vector canvas.
/// Supports dual-mode visualization:
/// 1. Lean angle in corners (gray -> blue -> orange -> red).
/// 2. Vehicle speed (blue -> green -> yellow -> red).
/// Includes start/finish badges, corner max-lean apex callouts, and interactive scrubbing.
class GpsTrackMapCard extends StatefulWidget {
  final List<FusedSample> samples;

  const GpsTrackMapCard({super.key, required this.samples});

  @override
  State<GpsTrackMapCard> createState() => _GpsTrackMapCardState();
}

class _GpsTrackMapCardState extends State<GpsTrackMapCard> {
  GpsTrackColorMode _mode = GpsTrackColorMode.lean;
  FusedSample? _scrubbedSample;
  Offset? _scrubbedPoint;

  @override
  Widget build(BuildContext context) {
    final validSamples = widget.samples
        .where((s) => s.latitude != 0.0 && s.longitude != 0.0)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Subtitle
          const Text(
            'TRASA JÍZDY (GPS)',
            style: TextStyle(
              color: AppTheme.appleBlack,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontFamily: '-apple-system',
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Barevná telemetrie v zatáčkách',
            style: TextStyle(
              color: AppTheme.appleMutedGray,
              fontSize: 12,
              fontFamily: '-apple-system',
            ),
          ),
          if (validSamples.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<GpsTrackColorMode>(
                groupValue: _mode,
                children: const {
                  GpsTrackColorMode.lean: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Klopení', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  GpsTrackColorMode.speed: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Rychlost', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                },
                onValueChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _mode = val;
                    });
                  }
                },
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (validSamples.length < 2)
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off_rounded, size: 36, color: AppTheme.appleMutedGray),
                  SizedBox(height: 8),
                  Text(
                    'Žádná GPS data pro vykreslení trasy',
                    style: TextStyle(
                      color: AppTheme.appleBlack,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: '-apple-system',
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Při této jízdě nebyl k dispozici signál satelitů.',
                    style: TextStyle(
                      color: AppTheme.appleMutedGray,
                      fontSize: 12,
                      fontFamily: '-apple-system',
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Canvas with touch listener
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 280,
                width: double.infinity,
                color: const Color(0xFFF8F8FA),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, constraints.maxHeight);
                    final projector = _TrackProjector(samples: validSamples, canvasSize: size);

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) => _handlePan(details.localPosition, projector),
                      onPanUpdate: (details) => _handlePan(details.localPosition, projector),
                      onPanEnd: (_) => setState(() {
                        _scrubbedSample = null;
                        _scrubbedPoint = null;
                      }),
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: size,
                            painter: _GpsTrackPainter(
                              samples: validSamples,
                              projector: projector,
                              mode: _mode,
                              scrubbedPoint: _scrubbedPoint,
                            ),
                          ),
                          // Floating inspection tooltip when scrubbing
                          if (_scrubbedSample != null && _scrubbedPoint != null)
                            Positioned(
                              top: 10,
                              left: 10,
                              right: 10,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C1C1E).withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${_scrubbedSample!.vehicleSpeedKmh} km/h • '
                                    '${_scrubbedSample!.leanAngleDeg.abs().toStringAsFixed(1)}° '
                                    '${_scrubbedSample!.leanAngleDeg < 0 ? 'vlevo' : 'vpravo'}'
                                    '${_scrubbedSample!.gear > 0 ? ' • ${_scrubbedSample!.gear}. st.' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: '-apple-system',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Dynamic Legend
            if (_mode == GpsTrackColorMode.lean)
              _buildLeanLegend()
            else
              _buildSpeedLegend(validSamples),
          ],
        ],
      ),
    );
  }

  void _handlePan(Offset localPos, _TrackProjector projector) {
    final nearest = projector.findNearestSample(localPos);
    if (nearest != null) {
      setState(() {
        _scrubbedSample = nearest.sample;
        _scrubbedPoint = nearest.screenPoint;
      });
    }
  }

  Widget _buildLeanLegend() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildLegendItem(const Color(0xFF8E8E93), 'Přímá (<15°)'),
        _buildLegendItem(AppTheme.appleBlue, 'Mírná (15–35°)'),
        _buildLegendItem(AppTheme.appleOrange, 'Ostrá (35–45°)'),
        _buildLegendItem(AppTheme.appleRed, 'Limit (>45°)'),
      ],
    );
  }

  Widget _buildSpeedLegend(List<FusedSample> samples) {
    int maxSpd = 0;
    for (final s in samples) {
      if (s.vehicleSpeedKmh > maxSpd) maxSpd = s.vehicleSpeedKmh;
    }
    if (maxSpd == 0) maxSpd = 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF007AFF),
                Color(0xFF34C759),
                Color(0xFFFF9500),
                Color(0xFFFF3B30),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('0 km/h', style: TextStyle(fontSize: 11, color: AppTheme.appleMutedGray)),
            Text('${(maxSpd / 2).round()} km/h', style: const TextStyle(fontSize: 11, color: AppTheme.appleMutedGray)),
            Text('$maxSpd km/h', style: const TextStyle(fontSize: 11, color: AppTheme.appleMutedGray, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.appleMutedGray,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFamily: '-apple-system',
          ),
        ),
      ],
    );
  }
}

/// Helper to project GPS Lat/Lon to 2D Canvas with Mercator aspect correction.
class _TrackProjector {
  final List<FusedSample> samples;
  final Size canvasSize;

  late double _minLat;
  late double _maxLat;
  late double _minLon;
  late double _maxLon;
  late double _scale;
  late double _offsetX;
  late double _offsetY;
  late double _cosLat;

  _TrackProjector({required this.samples, required this.canvasSize}) {
    _init();
  }

  void _init() {
    _minLat = samples.first.latitude;
    _maxLat = samples.first.latitude;
    _minLon = samples.first.longitude;
    _maxLon = samples.first.longitude;

    for (final s in samples) {
      if (s.latitude < _minLat) _minLat = s.latitude;
      if (s.latitude > _maxLat) _maxLat = s.latitude;
      if (s.longitude < _minLon) _minLon = s.longitude;
      if (s.longitude > _maxLon) _maxLon = s.longitude;
    }

    final centerLat = (_minLat + _maxLat) / 2.0;
    _cosLat = cos(centerLat * pi / 180.0);

    final deltaX = (_maxLon - _minLon) * _cosLat;
    final deltaY = _maxLat - _minLat;

    const padding = 32.0;
    final usableW = canvasSize.width - (padding * 2);
    final usableH = canvasSize.height - (padding * 2);

    final scaleX = deltaX > 0.00001 ? (usableW / deltaX) : 10000.0;
    final scaleY = deltaY > 0.00001 ? (usableH / deltaY) : 10000.0;
    _scale = min(scaleX, scaleY);

    final projectedW = deltaX * _scale;
    final projectedH = deltaY * _scale;

    _offsetX = padding + (usableW - projectedW) / 2.0;
    _offsetY = padding + (usableH - projectedH) / 2.0;
  }

  Offset project(double lat, double lon) {
    final x = _offsetX + ((lon - _minLon) * _cosLat * _scale);
    final y = _offsetY + ((_maxLat - lat) * _scale);
    return Offset(x, y);
  }

  ({FusedSample sample, Offset screenPoint})? findNearestSample(Offset pos) {
    if (samples.isEmpty) return null;

    FusedSample? bestSample;
    Offset? bestPoint;
    double bestDistSq = double.infinity;

    for (final s in samples) {
      final pt = project(s.latitude, s.longitude);
      final distSq = (pt.dx - pos.dx) * (pt.dx - pos.dx) + (pt.dy - pos.dy) * (pt.dy - pos.dy);
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestSample = s;
        bestPoint = pt;
      }
    }

    if (bestSample != null && bestPoint != null) {
      return (sample: bestSample, screenPoint: bestPoint);
    }
    return null;
  }
}

class _GpsTrackPainter extends CustomPainter {
  final List<FusedSample> samples;
  final _TrackProjector projector;
  final GpsTrackColorMode mode;
  final Offset? scrubbedPoint;

  _GpsTrackPainter({
    required this.samples,
    required this.projector,
    required this.mode,
    this.scrubbedPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    int maxSpeed = 0;
    int maxLeftIdx = 0;
    int maxRightIdx = 0;
    double maxLeftVal = 0.0;
    double maxRightVal = 0.0;

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      if (s.vehicleSpeedKmh > maxSpeed) maxSpeed = s.vehicleSpeedKmh;
      if (s.leanAngleDeg < maxLeftVal) {
        maxLeftVal = s.leanAngleDeg;
        maxLeftIdx = i;
      }
      if (s.leanAngleDeg > maxRightVal) {
        maxRightVal = s.leanAngleDeg;
        maxRightIdx = i;
      }
    }
    if (maxSpeed == 0) maxSpeed = 100;

    // 1. Draw track line segments with dynamic colors
    final linePaint = Paint()
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < samples.length - 1; i++) {
      final s1 = samples[i];
      final s2 = samples[i + 1];

      final p1 = projector.project(s1.latitude, s1.longitude);
      final p2 = projector.project(s2.latitude, s2.longitude);

      if (mode == GpsTrackColorMode.lean) {
        final avgLean = ((s1.leanAngleDeg.abs() + s2.leanAngleDeg.abs()) / 2.0);
        if (avgLean >= 45.0) {
          linePaint.color = AppTheme.appleRed;
        } else if (avgLean >= 35.0) {
          linePaint.color = AppTheme.appleOrange;
        } else if (avgLean >= 15.0) {
          linePaint.color = AppTheme.appleBlue;
        } else {
          linePaint.color = const Color(0xFFC7C7CC);
        }
      } else {
        final avgSpd = (s1.vehicleSpeedKmh + s2.vehicleSpeedKmh) / 2.0;
        final ratio = (avgSpd / maxSpeed).clamp(0.0, 1.0);
        if (ratio < 0.3) {
          linePaint.color = const Color(0xFF007AFF);
        } else if (ratio < 0.6) {
          linePaint.color = const Color(0xFF34C759);
        } else if (ratio < 0.85) {
          linePaint.color = const Color(0xFFFF9500);
        } else {
          linePaint.color = const Color(0xFFFF3B30);
        }
      }

      canvas.drawLine(p1, p2, linePaint);
    }

    // 2. Apex max lean callout pills on track
    if (maxLeftVal < -15.0) {
      final p = projector.project(samples[maxLeftIdx].latitude, samples[maxLeftIdx].longitude);
      _drawApexPill(canvas, p, '◀ ${maxLeftVal.abs().toStringAsFixed(0)}°', AppTheme.appleBlue);
    }
    if (maxRightVal > 15.0) {
      final p = projector.project(samples[maxRightIdx].latitude, samples[maxRightIdx].longitude);
      _drawApexPill(canvas, p, '${maxRightVal.toStringAsFixed(0)}° ▶', AppTheme.appleOrange);
    }

    // 3. Start Point Badge
    final startP = projector.project(samples.first.latitude, samples.first.longitude);
    final startPaint = Paint()..color = AppTheme.appleGreen..style = PaintingStyle.fill;
    canvas.drawCircle(startP, 6, startPaint);
    canvas.drawCircle(startP, 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);

    // 4. Finish Point Badge
    final finishP = projector.project(samples.last.latitude, samples.last.longitude);
    final finishPaint = Paint()..color = const Color(0xFF1C1C1E)..style = PaintingStyle.fill;
    canvas.drawCircle(finishP, 6, finishPaint);
    canvas.drawCircle(finishP, 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);

    // 5. Interactive Scrub Point
    if (scrubbedPoint != null) {
      final ringPaint = Paint()
        ..color = AppTheme.appleBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(scrubbedPoint!, 8, ringPaint);
      canvas.drawCircle(scrubbedPoint!, 4, Paint()..color = Colors.white..style = PaintingStyle.fill);
    }
  }

  void _drawApexPill(Canvas canvas, Offset pt, String text, Color accent) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        fontFamily: '-apple-system',
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final pillW = textPainter.width + 12;
    final pillH = textPainter.height + 6;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(pt.dx, pt.dy - 14), width: pillW, height: pillH),
      const Radius.circular(10),
    );

    canvas.drawRRect(
      pillRect,
      Paint()..color = accent..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      pillRect,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1,
    );

    textPainter.paint(canvas, Offset(pillRect.left + 6, pillRect.top + 3));
  }

  @override
  bool shouldRepaint(covariant _GpsTrackPainter oldDelegate) {
    return oldDelegate.mode != mode ||
        oldDelegate.scrubbedPoint != scrubbedPoint ||
        oldDelegate.samples != samples;
  }
}
