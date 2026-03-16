// lib/screens/graph_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/line_chart.dart';
import '../widgets/multi_line_chart.dart';
import '../providers/csv_data_provider.dart';
import '../services/run_segmentation.dart';

class GraphScreen extends StatefulWidget {
  final bool embedded;
  const GraphScreen({super.key, this.embedded = false});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  double zoomLevel = 3;
  int scrollIndex = 0;
  int _dataLength = 0;
  int? _selectedFarmId;

  void zoomIn() => setState(() { if (zoomLevel < 5) zoomLevel += 1; });
  void zoomOut() => setState(() { if (zoomLevel > 1) zoomLevel -= 1; });
  void scrollLeft() => setState(() { if (scrollIndex > 0) scrollIndex--; });
  void scrollRight() {
    if (scrollIndex < _dataLength - 10) scrollIndex++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CSVDataProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = Theme.of(context).iconTheme.color ?? (isDark ? Colors.white70 : Colors.black87);

    if (!provider.hasData) {
      final Widget body = const Center(child: Text("No data available."));
      return widget.embedded ? body : Scaffold(body: body);
    }

    // Compute run segmentation and per-run averages
    final segments = RunSegmentationService.segmentRuns(
      timestamps: provider.timestamps,
      lats: provider.latitudes,
      lons: provider.longitudes,
    );
    final summaries = RunSegmentationService.summarizeRuns(provider: provider, segments: segments);
    final runTimestamps = segments.map((s) => s.startTime).toList();
    _dataLength = runTimestamps.length;

    List<double> _buildCombinedIdealSeries(
      List<double> pH,
      List<double> temperature,
      List<double> humidity,
      List<double> ec,
    ) {
      final int len = [pH, temperature, humidity, ec].map((s) => s.length).fold<int>(0, (a, b) => a == 0 ? b : (a < b ? a : b));
      final List<double> out = List.filled(len, double.nan);
      double score(double value, double min, double max) {
        if (!value.isFinite) return double.nan;
        if (max <= min) return 1.0;
        if (value >= min && value <= max) return 1.0;
        final double mid = (min + max) / 2.0;
        final double half = (max - min) / 2.0;
        final double dist = (value - mid).abs();
        final double s = 1.0 - (dist / (half * 2.0));
        return s.clamp(0.0, 1.0);
      }
      for (int i = 0; i < len; i++) {
        final vals = <double>[
          score(pH[i], 6.0, 7.5),
          score(temperature[i], 20.0, 25.0),
          score(humidity[i], 40.0, 60.0),
          score(ec[i], 1.0, 2.0),
        ].where((v) => v.isFinite).toList();
        out[i] = vals.isEmpty ? double.nan : vals.reduce((a, b) => a + b) / vals.length;
      }
      return out;
    }

    // Farm clustering to enable filtering
    final assignment = RunSegmentationService.assignFarms(
      runs: segments,
      lats: provider.latitudes,
      lons: provider.longitudes,
    );
    final farms = assignment.farms;
    final runsWithFarms = assignment.runs;

    _selectedFarmId ??= (() {
      if (farms.isEmpty) return null;
      int latestFarmId = farms.first.id;
      DateTime latestEnd = DateTime.fromMillisecondsSinceEpoch(0);
      for (final f in farms) {
        for (final idx in f.runIndices) {
          final end = runsWithFarms[idx].endTime;
          if (end.isAfter(latestEnd)) { latestEnd = end; latestFarmId = f.id; }
        }
      }
      return latestFarmId;
    })();

    Widget farmSelector() {
      if (farms.isEmpty) return const SizedBox.shrink();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...farms.map((f) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text('Farm ${f.id}'),
                    selected: _selectedFarmId == f.id,
                    onSelected: (_) => setState(() { _selectedFarmId = f.id; }),
                  ),
                )),
          ],
        ),
      );
    }

    // Filter to selected farm only
    final int? farmId = _selectedFarmId;
    List<int> allowedRunIndices = farmId == null
        ? <int>[]
        : [
            for (int i = 0; i < runsWithFarms.length; i++)
              if (runsWithFarms[i].farmId == farmId) i
          ];

    if (allowedRunIndices.isNotEmpty) {
      List<DateTime> filteredTimestamps = [for (final i in allowedRunIndices) runTimestamps[i]];
      List<double> filterSeries(List<double> s) => [for (final i in allowedRunIndices) (i < s.length ? s[i] : double.nan)];

      final pHPerRun = filterSeries(RunSegmentationService.averagesForMetric(summaries, 'pH'));
      final temperaturePerRun = filterSeries(RunSegmentationService.averagesForMetric(summaries, 'Temperature'));
      final humidityPerRun = filterSeries(RunSegmentationService.averagesForMetric(summaries, 'Humidity'));
      final ecPerRun = filterSeries(RunSegmentationService.averagesForMetric(summaries, 'EC'));

      _dataLength = filteredTimestamps.length;

      final Widget content = Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: zoomIn, icon: Icon(Icons.zoom_in, color: iconColor)),
              IconButton(onPressed: zoomOut, icon: Icon(Icons.zoom_out, color: iconColor)),
              IconButton(onPressed: scrollLeft, icon: Icon(Icons.arrow_left, color: iconColor)),
              IconButton(onPressed: scrollRight, icon: Icon(Icons.arrow_right, color: iconColor)),
            ],
          ),
          farmSelector(),
          Expanded(
            child: DefaultTabController(
              length: 5,
              child: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: "pH"),
                      Tab(text: "Temperature"),
                      Tab(text: "Humidity"),
                      Tab(text: "EC"),
                      Tab(text: "All"),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        LineChartWidget(data: pHPerRun, color: Colors.green, label: "pH", timestamps: filteredTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                        LineChartWidget(data: temperaturePerRun, color: Colors.red, label: "Temperature", timestamps: filteredTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                        LineChartWidget(data: humidityPerRun, color: Colors.cyan, label: "Humidity", timestamps: filteredTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                        LineChartWidget(data: ecPerRun, color: Colors.indigo, label: "EC", timestamps: filteredTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                        MultiLineChartWidget(
                          pHData: pHPerRun,
                          temperatureData: temperaturePerRun,
                          humidityData: humidityPerRun,
                          ecData: ecPerRun,
                          timestamps: filteredTimestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                          combinedSeries: _buildCombinedIdealSeries(pHPerRun, temperaturePerRun, humidityPerRun, ecPerRun),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      return widget.embedded
          ? content
          : Scaffold(
              appBar: AppBar(title: const Text("📊 Graphs")),
              body: content,
            );
    }

    // Unfiltered path: all runs
    final pHPerRun = RunSegmentationService.averagesForMetric(summaries, 'pH');
    final temperaturePerRun = RunSegmentationService.averagesForMetric(summaries, 'Temperature');
    final humidityPerRun = RunSegmentationService.averagesForMetric(summaries, 'Humidity');
    final ecPerRun = RunSegmentationService.averagesForMetric(summaries, 'EC');

    final Widget content = Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(onPressed: zoomIn, icon: Icon(Icons.zoom_in, color: iconColor)),
            IconButton(onPressed: zoomOut, icon: Icon(Icons.zoom_out, color: iconColor)),
            IconButton(onPressed: scrollLeft, icon: Icon(Icons.arrow_left, color: iconColor)),
            IconButton(onPressed: scrollRight, icon: Icon(Icons.arrow_right, color: iconColor)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Text(
            'Showing per-run averages',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 5,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: "pH"),
                    Tab(text: "Temperature"),
                    Tab(text: "Humidity"),
                    Tab(text: "EC"),
                    Tab(text: "All"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      LineChartWidget(data: pHPerRun, color: Colors.green, label: "pH", timestamps: runTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                      LineChartWidget(data: temperaturePerRun, color: Colors.red, label: "Temperature", timestamps: runTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                      LineChartWidget(data: humidityPerRun, color: Colors.cyan, label: "Humidity", timestamps: runTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                      LineChartWidget(data: ecPerRun, color: Colors.indigo, label: "EC", timestamps: runTimestamps, zoomLevel: zoomLevel, scrollIndex: scrollIndex),
                      MultiLineChartWidget(
                        pHData: pHPerRun,
                        temperatureData: temperaturePerRun,
                        humidityData: humidityPerRun,
                        ecData: ecPerRun,
                        timestamps: runTimestamps,
                        zoomLevel: zoomLevel,
                        scrollIndex: scrollIndex,
                        combinedSeries: _buildCombinedIdealSeries(pHPerRun, temperaturePerRun, humidityPerRun, ecPerRun),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text("📊 Graphs")),
      body: content,
    );
  }
}
