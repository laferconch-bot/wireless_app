import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/heatmap_service.dart';
import '../services/heatmap_cache_service.dart';
import '../widgets/heatmap_2d.dart';
import '../widgets/heatmap_3d.dart';
import '../widgets/heatmap_surface_3d.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final heatmapService = HeatmapService();
  final List<String> metrics = [
    'pH',
    'Temperature',
    'Humidity',
    'EC',
    'N',
    'P',
    'K',
    'All'
  ];
  String currentMetric = 'All';
  DateTime? startTime;
  DateTime? endTime;
  bool is3DView = false;
  bool isLoading = true;
  List<List<double>>? gridData;
  double minValue = 0.0;
  double maxValue = 0.0;
  String? gltfModelPath;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Use available default asset (lat/lon/timestamp grid)
      final csvAssetPath = 'assets/simulated_soil_square.csv';
      final points = await HeatmapService.parseCsvAsset(csvAssetPath);
      heatmapService.setPoints(points);

      if (!mounted) return;

      if (points.isNotEmpty) {
        // Compute full available time range from CSV
        final DateTime minT = points.map((p) => p.t).reduce((a, b) => a.isBefore(b) ? a : b);
        final DateTime maxT = points.map((p) => p.t).reduce((a, b) => a.isAfter(b) ? a : b);

        setState(() {
          startTime = minT;
          endTime = maxT;
          // Start with 'All' to ensure visibility by default
          currentMetric = 'All';
          isLoading = false;
        });
        _updateGridAndValues();
        // After grid computed, auto-generate PNG for default metric if missing
        await _ensurePngForCurrent(csvAssetPath);
        // Fallback: if grid looks empty, try metric 'pH' then 'All' with full range again
        if (!_hasFinite(gridData)) {
          setState(() { currentMetric = 'pH'; });
          _updateGridAndValues();
          if (!_hasFinite(gridData)) {
            setState(() { currentMetric = 'All'; startTime = minT; endTime = maxT; });
            _updateGridAndValues();
          }
        }
      } else {
        // Ensure spinner clears even when dataset is empty
        setState(() {
          startTime = null;
          endTime = null;
          gridData = [];
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  void _updateGridAndValues() {
    if (heatmapService.points.isEmpty || startTime == null || endTime == null) {
      setState(() {
        gridData = [];
        minValue = 0;
        maxValue = 0;
      });
      return;
    }

    final newGrid = heatmapService.createGrid(
      metric: currentMetric,
      start: startTime!,
      end: endTime!,
    );

    final allValues = newGrid.expand((row) => row).where((v) => !v.isNaN).toList();
    if (allValues.isNotEmpty) {
      final min = allValues.reduce((a, b) => a < b ? a : b);
      final max = allValues.reduce((a, b) => a > b ? a : b);

      double adjustedMin = min;
      double adjustedMax = max;
      if (adjustedMin == adjustedMax) {
        adjustedMin = adjustedMin - 0.01;
        adjustedMax = adjustedMax + 0.01;
      }

      setState(() {
        gridData = newGrid;
        minValue = adjustedMin;
        maxValue = adjustedMax;
      });
    } else {
      // When no finite values are present, still provide a non-zero range for UI
      setState(() {
        gridData = newGrid;
        minValue = 0;
        maxValue = 1;
      });
    }
  }

  Future<void> _ensurePngForCurrent(String csvKeySource) async {
    try {
      if (gridData == null || gridData!.isEmpty) return;
      // Create a stable key from CSV content + metric
      // If asset: read as string; if file later, read the file contents
      final csvContent = await DefaultAssetBundle.of(context).loadString(csvKeySource);
      final key = HeatmapCacheService.buildKey(csvContent: csvContent, metric: currentMetric);
      final exists = await HeatmapCacheService.existsPng(key);
      if (!exists) {
        final img = await renderHeatmapImage(
          grid: gridData!,
          metricLabel: currentMetric,
          minValue: minValue,
          maxValue: maxValue,
          cellSize: 24,
        );
        await HeatmapCacheService.writePng(key, img);
      }
    } catch (_) {
      // Ignore caching errors silently for now
    }
  }

  bool _hasFinite(List<List<double>>? grid) {
    if (grid == null || grid.isEmpty || grid.first.isEmpty) return false;
    for (final row in grid) {
      for (final v in row) {
        if (v.isFinite) return true;
      }
    }
    return false;
  }

  void _onMetricChanged(String newMetric) {
    setState(() {
      currentMetric = newMetric;
    });
    _updateGridAndValues();
    // Try generating PNG for this metric in background
    unawaited(_ensurePngForCurrent('assets/simulated_soil_square.csv'));
  }

  Future<void> _selectDateRange() async {
    // Show date picker first
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: startTime ?? DateTime.now(),
    );

    if (pickedDate != null) {
      // Then show time picker
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(startTime ?? DateTime.now()),
      );

      if (pickedTime != null) {
        final newStartTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setState(() {
          startTime = newStartTime;
          endTime = newStartTime.add(const Duration(hours: 1)); // Set a default end time
        });
        _updateGridAndValues();
      }
    }
  }

  void _toggleView() {
    setState(() {
      is3DView = !is3DView;
    });

    // In this app we render 3D with a custom painter instead of glTF assets
    gltfModelPath = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Heatmap Viewer'),
        backgroundColor: isDark ? Colors.grey[800] : Colors.blue,
        actions: [
          IconButton(
            icon: Icon(is3DView ? Icons.view_agenda : Icons.view_in_ar),
            onPressed: _toggleView,
            tooltip: 'Toggle 2D/3D View',
          ),
        ],
      ),
      body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: metrics.map((metric) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: ElevatedButton(
                            onPressed: () => _onMetricChanged(metric),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentMetric == metric
                                  ? Colors.blue.shade800
                                  : Colors.grey.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(metric),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _selectDateRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      startTime != null && endTime != null
                          ? 'Viewing Data from ${startTime!.toString().split('.')[0]} to ${endTime!.toString().split('.')[0]}'
                          : 'Select Date & Time Range',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: (gridData != null && gridData!.isNotEmpty)
                        ? (is3DView
                            ? HeatmapSurface3D(
                                grid: gridData!,
                                metricLabel: currentMetric,
                                minValue: minValue,
                                maxValue: maxValue,
                              )
                            : Heatmap2D(
                                grid: gridData!,
                                metricLabel: currentMetric,
                                minValue: minValue,
                                maxValue: maxValue,
                              ))
                        : const Center(
                            child: Text("No data to display for the selected metric and time range."),
                          ),
                  ),
                  const SizedBox(height: 12),
                  if (!is3DView && (gridData != null && gridData!.isNotEmpty))
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Export heatmap PNG'),
                      onPressed: () async {
                        try {
                          final img = await renderHeatmapImage(
                            grid: gridData!,
                            metricLabel: currentMetric,
                            minValue: minValue,
                            maxValue: maxValue,
                            cellSize: 16,
                            showGridLines: false,
                          );
                          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
                          if (bytes != null) {
                            final dir = await getApplicationDocumentsDirectory();
                            final safeMetric = currentMetric.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
                            final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
                            final path = '${dir.path}/heatmap_${safeMetric}_$timestamp.png';
                            final file = File(path);
                            await file.writeAsBytes(bytes.buffer.asUint8List());
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Saved PNG: $path')),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Failed to encode PNG bytes')),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to render PNG: $e')),
                            );
                          }
                        }
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
