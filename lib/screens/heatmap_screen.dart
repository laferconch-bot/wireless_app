import 'dart:async';
import 'package:flutter/material.dart';
import '../services/heatmap_service.dart';
import '../widgets/heatmap_2d.dart';
import '../widgets/heatmap_3d.dart';

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
  String currentMetric = 'pH';
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
      final points = await HeatmapService.parseCsvAsset('assets/simulated_soil_square.csv');
      heatmapService.setPoints(points);

      if (points.isNotEmpty) {
        setState(() {
          // Set initial timeline to a recent, tighter window for better visibility
          startTime = points.last.t.subtract(const Duration(hours: 12));
          endTime = points.last.t;
          isLoading = false;
        });
        _updateGridAndValues();
      }
    } catch (e) {
      print('Error loading data: $e');
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

      setState(() {
        gridData = newGrid;
        minValue = min;
        maxValue = max;
      });

      if (minValue == maxValue) {
        minValue = minValue - 0.01;
        maxValue = maxValue + 0.01;
      }
    } else {
      setState(() {
        gridData = newGrid;
        minValue = 0;
        maxValue = 0;
      });
    }
  }

  void _onMetricChanged(String newMetric) {
    setState(() {
      currentMetric = newMetric;
    });
    _updateGridAndValues();
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
                            ? Heatmap3D(grid: gridData!, metricLabel: currentMetric, minValue: minValue, maxValue: maxValue)
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
                ],
              ),
            ),
    );
  }
}
