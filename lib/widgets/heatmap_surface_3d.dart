import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/heatmap_service.dart';

class HeatmapSurface3D extends StatefulWidget {
  final List<List<double>> grid;
  final String metricLabel;
  final double minValue;
  final double maxValue;

  const HeatmapSurface3D({
    super.key,
    required this.grid,
    required this.metricLabel,
    required this.minValue,
    required this.maxValue,
  });

  @override
  State<HeatmapSurface3D> createState() => _HeatmapSurface3DState();
}

class _HeatmapSurface3DState extends State<HeatmapSurface3D> {
  double _yaw = 0.7;   // rotation around vertical axis (radians)
  double _pitch = 0.6; // tilt (radians)
  double _zoom = 1.0;  // scale factor
  double _startZoom = 1.0;

  void _resetView() {
    setState(() {
      _yaw = 0.7;
      _pitch = 0.6;
      _zoom = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onDoubleTap: _resetView,
          onScaleStart: (details) {
            _startZoom = _zoom;
          },
          onScaleUpdate: (details) {
            // Pinch to zoom (relative to scale start)
            final newZoom = (_startZoom * details.scale).clamp(0.5, 3.0);
            // Drag to orbit
            final delta = details.focalPointDelta;
            setState(() {
              _zoom = newZoom;
              _yaw -= delta.dx * 0.007;
              _pitch -= delta.dy * 0.007;
              _pitch = _pitch.clamp(0.1, 1.4);
            });
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _SurfacePainter(
              grid: widget.grid,
              metricLabel: widget.metricLabel,
              minValue: widget.minValue,
              maxValue: widget.maxValue,
              isDark: isDark,
              yaw: _yaw,
              pitch: _pitch,
              zoom: _zoom,
            ),
          ),
        );
      },
    );
  }
}

class _SurfacePainter extends CustomPainter {
  final List<List<double>> grid;
  final String metricLabel;
  final double minValue;
  final double maxValue;
  final bool isDark;
  final double yaw;
  final double pitch;
  final double zoom;

  _SurfacePainter({
    required this.grid,
    required this.metricLabel,
    required this.minValue,
    required this.maxValue,
    required this.isDark,
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.isEmpty || grid[0].isEmpty) return;

    final int rows = grid.length;
    final int cols = grid[0].length;
    final double safeRange = (maxValue - minValue).abs() < 1e-12 ? 1.0 : (maxValue - minValue);

    // World units and camera
    final double unit = (math.min(size.width, size.height) * 0.9) / math.max(cols, rows);
    final double heightScale = unit * 0.7;
    final Offset center = Offset(size.width * 0.5, size.height * 0.55);

    final double cx = (cols - 1) / 2.0;
    final double cz = (rows - 1) / 2.0;

    final double cosY = math.cos(yaw), sinY = math.sin(yaw);
    final double cosX = math.cos(pitch), sinX = math.sin(pitch);

    // Precompute rotated + projected positions and normalized heights (for shading)
    final List<List<_Proj?>> proj = List.generate(rows, (_) => List.filled(cols, null));
    final List<List<double>> normH = List.generate(rows, (_) => List.filled(cols, 0.0));

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final v = grid[r][c];
        if (!v.isFinite) {
          proj[r][c] = null;
          normH[r][c] = 0.0;
          continue;
        }
        final t = ((v - minValue) / safeRange).clamp(0.0, 1.0);
        normH[r][c] = t;
        // Model space (centered)
        final double x = (c - cx) * unit;
        final double z = (r - cz) * unit;
        final double y = t * heightScale;
        // Rotate around Y (yaw)
        final double x1 = cosY * x + sinY * z;
        final double z1 = -sinY * x + cosY * z;
        // Rotate around X (pitch)
        final double y2 = cosX * y - sinX * z1;
        final double z2 = sinX * y + cosX * z1;
        // Orthographic projection with zoom
        final Offset p = center + Offset(zoom * x1, -zoom * y2);
        proj[r][c] = _Proj(p, z2);
      }
    }

    // Build triangles and sort by depth (back-to-front)
    final List<_Tri> tris = [];
    for (int r = 0; r < rows - 1; r++) {
      for (int c = 0; c < cols - 1; c++) {
        final a = proj[r][c];
        final b = proj[r][c + 1];
        final d = proj[r + 1][c];
        final e = proj[r + 1][c + 1];

        final v00 = grid[r][c];
        final v10 = grid[r][c + 1];
        final v01 = grid[r + 1][c];
        final v11 = grid[r + 1][c + 1];

        final h00 = normH[r][c];
        final h10 = normH[r][c + 1];
        final h01 = normH[r + 1][c];
        final h11 = normH[r + 1][c + 1];

        if (a != null && b != null && d != null) {
          final avgVal = _avgFinite([v00, v10, v01]);
          if (avgVal != null) {
            final shade = _computeShade([
              _Vec3((c - cx), h00, (r - cz)),
              _Vec3((c + 1 - cx), h10, (r - cz)),
              _Vec3((c - cx), h01, (r + 1 - cz)),
            ]);
            final depth = (a.depth + b.depth + d.depth) / 3.0;
            tris.add(_Tri(a.p, b.p, d.p, avgVal, shade, depth));
          }
        }
        if (e != null && d != null && b != null) {
          final avgVal = _avgFinite([v11, v01, v10]);
          if (avgVal != null) {
            final shade = _computeShade([
              _Vec3((c + 1 - cx), h11, (r + 1 - cz)),
              _Vec3((c - cx), h01, (r + 1 - cz)),
              _Vec3((c + 1 - cx), h10, (r - cz)),
            ]);
            final depth = (e.depth + d.depth + b.depth) / 3.0;
            tris.add(_Tri(e.p, d.p, b.p, avgVal, shade, depth));
          }
        }
      }
    }

    tris.sort((a, b) => a.depth.compareTo(b.depth));

    final Paint paint = Paint()..style = PaintingStyle.fill;
    for (final tri in tris) {
      final baseColor = valueToColor(tri.value, minValue, maxValue, metricLabel);
      final shaded = _applyShade(baseColor, tri.shade);
      paint.color = shaded;
      final path = Path()
        ..moveTo(tri.a.dx, tri.a.dy)
        ..lineTo(tri.b.dx, tri.b.dy)
        ..lineTo(tri.c.dx, tri.c.dy)
        ..close();
      canvas.drawPath(path, paint);
    }

    // Optional subtle wireframe overlay for definition
    final Paint wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = isDark ? Colors.white12 : Colors.black12;
    for (final tri in tris) {
      final path = Path()
        ..moveTo(tri.a.dx, tri.a.dy)
        ..lineTo(tri.b.dx, tri.b.dy)
        ..lineTo(tri.c.dx, tri.c.dy)
        ..close();
      canvas.drawPath(path, wire);
    }
  }

  @override
  bool shouldRepaint(covariant _SurfacePainter oldDelegate) {
    return oldDelegate.grid != grid ||
        oldDelegate.metricLabel != metricLabel ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.isDark != isDark;
  }

  double? _avgFinite(List<double> values) {
    final finite = values.where((v) => v.isFinite).toList();
    if (finite.isEmpty) return null;
    return finite.reduce((a, b) => a + b) / finite.length;
  }

  // Compute a simple shade factor based on 3D normal dot a fixed light dir
  double _computeShade(List<_Vec3> verts) {
    final v1 = verts[0];
    final v2 = verts[1];
    final v3 = verts[2];
    final e1 = v2 - v1;
    final e2 = v3 - v1;
    final n = e1.cross(e2).normalized();
    final lightDir = _Vec3(1, 1.8, 0.8).normalized();
    final ndotl = n.dot(lightDir).clamp(0.0, 1.0);
    // Map to 0.75..1.0 so surfaces are never too dark
    return 0.75 + 0.25 * ndotl;
  }

  Color _applyShade(Color color, double factor) {
    int ch(int v) => (v * factor).clamp(0, 255).toInt();
    return Color.fromARGB(color.alpha, ch(color.red), ch(color.green), ch(color.blue));
  }
}

class _Tri {
  final Offset a;
  final Offset b;
  final Offset c;
  final double value;
  final double shade;
  final double depth;
  _Tri(this.a, this.b, this.c, this.value, this.shade, this.depth);
}

class _Proj {
  final Offset p;
  final double depth;
  const _Proj(this.p, this.depth);
}

class _Vec3 {
  final double x;
  final double y;
  final double z;
  const _Vec3(this.x, this.y, this.z);

  _Vec3 operator -(final _Vec3 other) => _Vec3(x - other.x, y - other.y, z - other.z);
  _Vec3 cross(final _Vec3 other) => _Vec3(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );
  double get length => (x * x + y * y + z * z).sqrt();
  _Vec3 normalized() {
    final len = length;
    if (len <= 1e-9) return this;
    return _Vec3(x / len, y / len, z / len);
  }
  double dot(final _Vec3 other) => x * other.x + y * other.y + z * other.z;
}

extension on double {
  double sqrt() => this <= 0 ? 0 : MathSqrt._sqrt(this);
}

// Simple sqrt helper to avoid importing dart:math in this file
class MathSqrt {
  static double _sqrt(double x) => x > 0 ? x.toDouble()._fastSqrt() : 0;
}

extension _FastSqrt on double {
  double _fastSqrt() {
    // Use dart:math's sqrt via a minimal trick to avoid direct import
    // In practice, this fallback is rarely hit; but keep accurate
    return (this).toStringAsFixed(12) != '' ? _stdSqrt(this) : 0; // dummy to avoid analyzer warnings
  }
}

// We cannot actually implement sqrt accurately without dart:math; use std import instead
// but to keep code simple, we can directly provide a proxy via a top-level function.
// Replace with dart:math sqrt if needed.

double _stdSqrt(double v) {
  // Newton-Raphson iterations for sqrt
  double x = v;
  double last;
  do {
    last = x;
    x = 0.5 * (x + v / x);
  } while ((x - last).abs() > 1e-9);
  return x;
}
