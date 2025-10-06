import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class MultiLineChartWidget extends StatelessWidget {
  final List<double> pHData;
  final List<double> nData;
  final List<double> pData;
  final List<double> kData;
  final List<double> temperatureData;
  final List<double> humidityData;
  final List<double> ecData;
  final List<DateTime> timestamps;

  final double zoomLevel;
  final int scrollIndex;

  const MultiLineChartWidget({
    super.key,
    required this.pHData,
    required this.nData,
    required this.pData,
    required this.kData,
    required this.temperatureData,
    required this.humidityData,
    required this.ecData,
    required this.timestamps,
    this.zoomLevel = 1.0,
    this.scrollIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (timestamps.isEmpty) return const Center(child: Text("No data"));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final axisColor = isDark ? Colors.white70 : Colors.black87;
    final gridColor = isDark ? Colors.white24 : Colors.black26;

    int visibleCount = (timestamps.length ~/ zoomLevel).clamp(6, timestamps.length);
    int start = scrollIndex.clamp(0, (timestamps.length - visibleCount).clamp(0, timestamps.length));
    int end = (start + visibleCount).clamp(0, timestamps.length);

    final shownTimestamps = timestamps.sublist(start, end);

    List<LineChartBarData> lines = [
      _buildLine(pHData.sublist(start, end), Colors.green),
      _buildLine(nData.sublist(start, end), Colors.blue),
      _buildLine(pData.sublist(start, end), Colors.orange),
      _buildLine(kData.sublist(start, end), Colors.purple),
      _buildLine(temperatureData.sublist(start, end), Colors.red),
      _buildLine(humidityData.sublist(start, end), Colors.cyan),
      _buildLine(ecData.sublist(start, end), Colors.indigo),
    ];

    // Derive global min/max across visible series for better scaling
    final List<List<double>> visibleSeries = [
      pHData.sublist(start, end),
      nData.sublist(start, end),
      pData.sublist(start, end),
      kData.sublist(start, end),
      temperatureData.sublist(start, end),
      humidityData.sublist(start, end),
      ecData.sublist(start, end),
    ];

    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final series in visibleSeries) {
      if (series.isEmpty) continue;
      minY = math.min(minY, series.reduce(math.min));
      maxY = math.max(maxY, series.reduce(math.max));
    }
    if (!minY.isFinite || !maxY.isFinite) {
      minY = 0;
      maxY = 1;
    }
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    } else {
      final padding = (maxY - minY) * 0.1;
      minY -= padding;
      maxY += padding;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.of(context).size.height;
        final chartHeight = (constraints.maxHeight.isFinite
                ? constraints.maxHeight * 0.6
                : screenHeight * 0.38)
            .clamp(240.0, 460.0) as double;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: chartHeight,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: isDark ? const Color(0xFF111315) : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 18, 8),
                        child: LineChart(
                          LineChartData(
                            minY: minY,
                            maxY: maxY,
                            gridData: FlGridData(
                              show: true,
                              drawHorizontalLine: true,
                              drawVerticalLine: true,
                              getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 0.6),
                              getDrawingVerticalLine: (_) => FlLine(color: gridColor, strokeWidth: 0.6),
                            ),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 24,
                                  interval: (shownTimestamps.length / 6)
                                      .floorToDouble()
                                      .clamp(1, shownTimestamps.length.toDouble()),
                                  getTitlesWidget: (value, meta) {
                                    int index = value.toInt();
                                    if (index < 0 || index >= shownTimestamps.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      "${shownTimestamps[index].month}/${shownTimestamps[index].day}",
                                      style: TextStyle(fontSize: 10, color: axisColor),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 48,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toStringAsFixed(1),
                                      style: TextStyle(fontSize: 10, color: axisColor),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            lineTouchData: LineTouchData(
                              handleBuiltInTouches: true,
                              touchTooltipData: LineTouchTooltipData(
                                tooltipRoundedRadius: 8,
                                tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    return LineTooltipItem(
                                      spot.y.toStringAsFixed(2),
                                      TextStyle(
                                        color: isDark ? Colors.white : Colors.black,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            lineBarsData: lines
                                .map((bar) => bar.copyWith(
                                      barWidth: 2,
                                      isCurved: true,
                                      dotData: const FlDotData(show: false),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        gradient: LinearGradient(
                                          colors: [
                                            (bar.color ?? Colors.blue).withOpacity(0.14),
                                            (bar.color ?? Colors.blue).withOpacity(0.0),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Legend
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _LegendRow(axisColor: axisColor),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  LineChartBarData _buildLine(List<double> values, Color color) {
    return LineChartBarData(
      spots: List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i])),
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color axisColor;
  const _LegendRow({required this.axisColor});

  @override
  Widget build(BuildContext context) {
    const items = <(Color, String)>[
      (Colors.green, 'pH'),
      (Colors.blue, 'Nitrogen'),
      (Colors.orange, 'Phosphorus'),
      (Colors.purple, 'Potassium'),
      (Colors.red, 'Temperature'),
      (Colors.cyan, 'Humidity'),
      (Colors.indigo, 'EC'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPerRow = constraints.maxWidth ~/ 180; // keep it compact
        final rows = <List<(Color, String)>>[];
        var current = <(Color, String)>[];
        for (final item in items) {
          current.add(item);
          if (current.length >= (maxPerRow == 0 ? 3 : maxPerRow)) {
            rows.add(current);
            current = <(Color, String)>[];
          }
        }
        if (current.isNotEmpty) rows.add(current);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final (color, label) in row)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          Text(label, style: TextStyle(color: axisColor)),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
