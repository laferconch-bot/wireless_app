import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:csv/csv.dart';
import 'dart:math';
import 'package:intl/intl.dart';

// A single data point
class HeatmapPoint {
  final int x;
  final int y;
  final DateTime t;
  final Map<String, double> metrics;

  HeatmapPoint({
    required this.x,
    required this.y,
    required this.t,
    required this.metrics,
  });
}

// Service for creating the heatmap grid
class HeatmapService {
  late List<HeatmapPoint> points;

  HeatmapService() {
    points = [];
  }

  void setPoints(List<HeatmapPoint> newPoints) {
    points = newPoints;
  }

  static Future<List<HeatmapPoint>> parseCsvAsset(String path) async {
    final rawData = await rootBundle.loadString(path);
    final parser = const CsvToListConverter();
    final List<List<dynamic>> csvTable = parser.convert(rawData);

    if (csvTable.isEmpty) return [];

    final header = csvTable.first.map((e) => e.toString()).toList();
    final lowerHeader = header.map((e) => e.trim().toLowerCase()).toList();

    // Detect coordinate/time columns (support x,y,t or timestamp,lat,lon)
    final xIndex = lowerHeader.indexOf('x');
    final yIndex = lowerHeader.indexOf('y');
    final tIndex = lowerHeader.indexOf('t');

    final timestampIndex = lowerHeader.indexOf('timestamp');
    final latIndex = lowerHeader.indexOf('lat');
    final lonIndex = lowerHeader.indexOf('lon');

    final bool useXY = xIndex != -1 && yIndex != -1 && (tIndex != -1 || timestampIndex != -1);
    final bool useLatLon = latIndex != -1 && lonIndex != -1 && timestampIndex != -1;

    if (!useXY && !useLatLon) {
      throw Exception("CSV must contain either (x,y,t) or (timestamp,lat,lon) columns.");
    }

    // Identify metric columns and normalize display names
    final Map<int, String> metricIndexToName = {};
    for (int i = 0; i < header.length; i++) {
      if (useXY) {
        if (i == xIndex || i == yIndex || i == (tIndex != -1 ? tIndex : timestampIndex)) continue;
      }
      if (useLatLon) {
        if (i == latIndex || i == lonIndex || i == timestampIndex) continue;
      }
      final key = lowerHeader[i];
      // Map common header keys to user-facing metric labels
      String display;
      switch (key) {
        case 'ph':
          display = 'pH';
          break;
        case 'temperature':
          display = 'Temperature';
          break;
        case 'humidity':
          display = 'Humidity';
          break;
        case 'ec':
          display = 'EC';
          break;
        case 'n':
          display = 'N';
          break;
        case 'p':
          display = 'P';
          break;
        case 'k':
          display = 'K';
          break;
        default:
          // Keep original if unknown
          display = header[i];
      }
      metricIndexToName[i] = display;
    }

    // Helper parsers
    double _toDouble(dynamic v) {
      if (v == null) return double.nan;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return double.nan;
      return double.tryParse(s) ?? double.nan;
    }

    DateTime _parseDate(dynamic v) {
      final s = v.toString().trim();
      try {
        return DateTime.parse(s);
      } catch (_) {
        // Try common format
        try {
          return DateFormat('yyyy-MM-dd HH:mm:ss').parse(s, true).toLocal();
        } catch (e) {
          throw Exception("Unable to parse date: $s");
        }
      }
    }

    // First pass: collect raw rows
    final List<_RawPoint> raw = [];
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.isEmpty) continue;

      final DateTime t = _parseDate(row[useXY ? (tIndex != -1 ? tIndex : timestampIndex) : timestampIndex]);
      final Map<String, double> metrics = {};
      metricIndexToName.forEach((col, name) {
        metrics[name] = _toDouble(row[col]);
      });

      if (useXY) {
        raw.add(_RawPoint(
          x: (row[xIndex] as num).toInt(),
          y: (row[yIndex] as num).toInt(),
          t: t,
          metrics: metrics,
        ));
      } else {
        raw.add(_RawPoint(
          lat: _toDouble(row[latIndex]),
          lon: _toDouble(row[lonIndex]),
          t: t,
          metrics: metrics,
        ));
      }
    }

    if (raw.isEmpty) return [];

    // If using lat/lon, map to grid indices by sorting unique values
    if (useLatLon) {
      final uniqueLats = raw.map((r) => r.lat!).toSet().toList()..sort();
      final uniqueLons = raw.map((r) => r.lon!).toSet().toList()..sort();
      final Map<double, int> latToY = { for (int i = 0; i < uniqueLats.length; i++) uniqueLats[i] : i };
      final Map<double, int> lonToX = { for (int i = 0; i < uniqueLons.length; i++) uniqueLons[i] : i };

      return raw.map((r) => HeatmapPoint(
        x: lonToX[r.lon]!,
        y: latToY[r.lat]!,
        t: r.t,
        metrics: r.metrics,
      )).toList();
    }

    // Already x/y
    return raw.map((r) => HeatmapPoint(
      x: r.x!,
      y: r.y!,
      t: r.t,
      metrics: r.metrics,
    )).toList();
  }

  // Create a grid from the data points
  List<List<double>> createGrid({
    required String metric,
    required DateTime start,
    required DateTime end,
  }) {
    if (points.isEmpty) {
      return [
        [double.nan]
      ];
    }

    final filteredPoints = points.where((p) =>
        (p.t.isAfter(start) || p.t.isAtSameMomentAs(start)) &&
        (p.t.isBefore(end) || p.t.isAtSameMomentAs(end)) &&
        (metric == 'All' || p.metrics.containsKey(metric))).toList();

    if (filteredPoints.isEmpty) {
      return [
        [double.nan]
      ];
    }

    final maxX = filteredPoints.map((p) => p.x).reduce(max);
    final maxY = filteredPoints.map((p) => p.y).reduce(max);

    final grid = List.generate(maxY + 1, (i) => List.filled(maxX + 1, double.nan));

    final Map<String, List<double>> combinedValues = {};
    for (var p in filteredPoints) {
      final key = '${p.x}_${p.y}';
      if (!combinedValues.containsKey(key)) {
        combinedValues[key] = [];
      }
      if (metric == 'All') {
        // Average across all metrics available for this point
        final values = p.metrics.values.where((v) => v.isFinite).toList();
        if (values.isNotEmpty) {
          combinedValues[key]!.add(values.reduce((a, b) => a + b) / values.length);
        }
      } else {
        final v = p.metrics[metric];
        if (v != null && v.isFinite) combinedValues[key]!.add(v);
      }
    }

    for (var entry in combinedValues.entries) {
      final parts = entry.key.split('_');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);
      if (entry.value.isNotEmpty) {
        final avgValue = entry.value.reduce((a, b) => a + b) / entry.value.length;
        grid[y][x] = avgValue;
      }
    }

    return grid;
  }
}

class _RawPoint {
  final int? x;
  final int? y;
  final double? lat;
  final double? lon;
  final DateTime t;
  final Map<String, double> metrics;

  _RawPoint({this.x, this.y, this.lat, this.lon, required this.t, required this.metrics});
}

// This map defines the "optimal" range for each metric for color scaling.
final Map<String, List<double>> optimalRanges = {
  'pH': [6.0, 7.5],
  'Temperature': [20.0, 25.0],
  'Humidity': [40.0, 60.0],
  'EC': [1.0, 2.0],
  'N': [100.0, 150.0],
  'P': [20.0, 50.0],
  'K': [150.0, 250.0],
  'All': [0, 1]
};

// Converts a value to a color based on the optimal range for the metric
Color valueToColor(double value, double minValue, double maxValue, String metric) {
  if (value.isNaN) {
    return Colors.black.withOpacity(0.1);
  }

  final optimalRange = optimalRanges[metric] ?? [minValue, maxValue];
  final optimalMin = optimalRange[0];
  final optimalMax = optimalRange[1];

  // Map value to a 0-1 range based on the overall min/max of the data
  final clampedValue = value.clamp(minValue, maxValue);
  final normalizedValue = (clampedValue - minValue) / (maxValue - minValue);

  // Define stops for the gradient
  final optimalMinStop = (optimalMin - minValue) / (maxValue - minValue);
  final optimalMaxStop = (optimalMax - minValue) / (maxValue - minValue);

  if (normalizedValue < optimalMinStop) {
    // Transition from blue (min) to green (optimal min)
    final progress = normalizedValue / optimalMinStop;
    return Color.lerp(Colors.blue, Colors.green, progress)!;
  } else if (normalizedValue >= optimalMinStop && normalizedValue <= optimalMaxStop) {
    // Stay in the green range for optimal values
    return Colors.green;
  } else {
    // Transition from green (optimal max) to red (max)
    final progress = (normalizedValue - optimalMaxStop) / (1.0 - optimalMaxStop);
    return Color.lerp(Colors.green, Colors.red, progress)!;
  }
}
