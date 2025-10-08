import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/heatmap_service.dart';
import 'heatmap_legend.dart';

class Heatmap2D extends StatelessWidget {
  final List<List<double>> grid;
  final bool showGridLines;
  final String metricLabel;
  final double minValue;
  final double maxValue;

  const Heatmap2D({
    super.key,
    required this.grid,
    this.showGridLines = false,
    required this.metricLabel,
    required this.minValue,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (grid.isEmpty || grid[0].isEmpty) {
      return Center(
          child: Text("No data",
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)));
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: CustomPaint(
                    painter: _HeatmapPainter(
                        grid, showGridLines, isDark, metricLabel, minValue, maxValue),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: double.infinity,
            width: 60,
            child: HeatmapLegend(
              minValue: minValue,
              maxValue: maxValue,
              metricLabel: metricLabel,
              isDark: isDark,
              axis: Axis.vertical,
            ),
          )
        ],
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<List<double>> grid;
  final bool showGridLines;
  final bool isDark;
  final String metricLabel;
  final double minValue;
  final double maxValue;

  _HeatmapPainter(this.grid, this.showGridLines, this.isDark,
      this.metricLabel, this.minValue, this.maxValue);

  @override
  void paint(Canvas canvas, Size size) {
    final rows = grid.length;
    final cols = grid[0].length;
    final paint = Paint();

    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        paint.color = valueToColor(grid[r][c], minValue, maxValue, metricLabel);
        final double x0 = c * cellWidth;
        final double y0 = r * cellHeight;
        final double x1 = (c == cols - 1) ? size.width : (c + 1) * cellWidth;
        final double y1 = (r == rows - 1) ? size.height : (r + 1) * cellHeight;
        final rect = Rect.fromLTWH(x0, y0, x1 - x0, y1 - y0);
        canvas.drawRect(rect, paint);

        if (showGridLines) {
          final border = Paint()
            ..color = isDark ? Colors.white24 : Colors.black12
            ..style = PaintingStyle.stroke;
          canvas.drawRect(rect, border);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.grid != grid ||
      old.isDark != isDark ||
      old.metricLabel != metricLabel ||
      old.minValue != minValue ||
      old.maxValue != maxValue;
}

// Render the heatmap to an offscreen image suitable for saving as PNG
Future<ui.Image> renderHeatmapImage({
  required List<List<double>> grid,
  required String metricLabel,
  required double minValue,
  required double maxValue,
  int cellSize = 16,
  bool showGridLines = false,
}) async {
  if (grid.isEmpty || grid[0].isEmpty) {
    // Create a tiny placeholder image
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(2, 2);
    final painter = _HeatmapPainter(
      [[double.nan]],
      showGridLines,
      false,
      metricLabel,
      minValue,
      maxValue,
    );
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    return picture.toImage(2, 2);
  }

  final rows = grid.length;
  final cols = grid[0].length;
  final width = (cols * cellSize).clamp(1, 8192);
  final height = (rows * cellSize).clamp(1, 8192);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  final painter = _HeatmapPainter(
    grid,
    showGridLines,
    false,
    metricLabel,
    minValue,
    maxValue,
  );
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}
