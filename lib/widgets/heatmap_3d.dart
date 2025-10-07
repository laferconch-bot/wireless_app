import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/heatmap_service.dart';

class Heatmap3D extends StatelessWidget {
  final List<List<double>> grid;
  final String metricLabel;
  final double minValue;
  final double maxValue;

  const Heatmap3D({super.key, required this.grid, required this.metricLabel, required this.minValue, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: isDark ? const Color(0xFF121418) : Colors.white,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: CustomPaint(
                  painter: _IsoSurfacePainter(
                    grid: grid,
                    metricLabel: metricLabel,
                    minValue: minValue,
                    maxValue: maxValue,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IsoSurfacePainter extends CustomPainter {
  final List<List<double>> grid;
  final String metricLabel;
  final double minValue;
  final double maxValue;
  final bool isDark;

  _IsoSurfacePainter({
    required this.grid,
    required this.metricLabel,
    required this.minValue,
    required this.maxValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rows = grid.length;
    final cols = grid[0].length;

    // Simple isometric projection parameters
    final double cell = size.width / (cols + rows);
    final double heightScale = cell * 0.8;
    final Offset origin = Offset(size.width * 0.5, size.height * 0.15);

    // Draw base grid assumed as ground plane
    final Paint stroke = Paint()
      ..color = isDark ? Colors.white12 : Colors.black12
      ..style = PaintingStyle.stroke;

    // Compute 3D isometric positions and draw columns
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final v = grid[r][c];
        if (!v.isFinite) continue;
        final color = valueToColor(v, minValue, maxValue, metricLabel);
        final double h = ((v - minValue) / (maxValue - minValue)).clamp(0.0, 1.0) * heightScale + 1.0;

        // Isometric projection from grid coords to screen
        final double x = (c - r) * cell * 0.866; // cos(30°)
        final double y = (c + r) * cell * 0.5;   // sin(30°)
        final Offset base = origin + Offset(x, y);

        // Column corners for a prism
        final Path top = Path();
        top.addPolygon([
          base + Offset(0, -h),
          base + Offset(cell * 0.866, -h + cell * 0.5),
          base + Offset(0, -h + cell),
          base + Offset(-cell * 0.866, -h + cell * 0.5),
        ], true);

        final Path left = Path()
          ..moveTo(base.dx, base.dy)
          ..lineTo(base.dx - cell * 0.866, base.dy + cell * 0.5)
          ..lineTo(base.dx - cell * 0.866, base.dy + cell * 0.5 - h)
          ..lineTo(base.dx, base.dy - h)
          ..close();

        final Path right = Path()
          ..moveTo(base.dx, base.dy)
          ..lineTo(base.dx + cell * 0.866, base.dy + cell * 0.5)
          ..lineTo(base.dx + cell * 0.866, base.dy + cell * 0.5 - h)
          ..lineTo(base.dx, base.dy - h)
          ..close();

        // Paint shading
        final Paint faceTop = Paint()..color = color.withOpacity(0.9);
        final Paint faceLeft = Paint()..color = darken(color, 0.18);
        final Paint faceRight = Paint()..color = lighten(color, 0.10);

        canvas.drawPath(left, faceLeft);
        canvas.drawPath(right, faceRight);
        canvas.drawPath(top, faceTop);

        // Optional stroke for definition
        canvas.drawPath(left, stroke);
        canvas.drawPath(right, stroke);
        canvas.drawPath(top, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IsoSurfacePainter oldDelegate) {
    return oldDelegate.grid != grid ||
        oldDelegate.metricLabel != metricLabel ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.isDark != isDark;
  }

  Color darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

  Color lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return hslLight.toColor();
  }
}
