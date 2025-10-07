// lib/screens/graph_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/line_chart.dart';
import '../widgets/multi_line_chart.dart';
import '../providers/csv_data_provider.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  // Start more zoomed-in by default to avoid clutter.
  double zoomLevel = 3;
  int scrollIndex = 0;

  void zoomIn() => setState(() { if (zoomLevel < 5) zoomLevel += 1; });
  void zoomOut() => setState(() { if (zoomLevel > 1) zoomLevel -= 1; });
  void scrollLeft() => setState(() { if (scrollIndex > 0) scrollIndex--; });
  void scrollRight() {
    final provider = context.read<CSVDataProvider>();
    if (scrollIndex < provider.timestamps.length - 10) scrollIndex++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CSVDataProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabLabelColor = isDark ? Colors.tealAccent : Colors.green;
    final unselectedTabColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final iconColor = isDark ? Colors.tealAccent : Colors.black87;

    if (!provider.hasData) {
      return const Scaffold(
        body: Center(child: Text("No data available.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("📊 Graphs"),
        backgroundColor: isDark ? Colors.black : Colors.green[100],
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: Column(
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
          Expanded(
            child: DefaultTabController(
              length: 8,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    labelColor: tabLabelColor,
                    unselectedLabelColor: unselectedTabColor,
                    indicatorColor: tabLabelColor,
                    tabs: const [
                      Tab(text: "pH"),
                      Tab(text: "N"),
                      Tab(text: "P"),
                      Tab(text: "K"),
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
                        LineChartWidget(
                          data: provider.pH,
                          color: Colors.green,
                          label: "pH",
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                        LineChartWidget(
                          data: provider.n,
                          color: Colors.blue,
                          label: "N",
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                        LineChartWidget(
                          data: provider.p,
                          color: Colors.orange,
                          label: "P",
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                        LineChartWidget(
                          data: provider.k,
                          color: Colors.purple,
                          label: "K",
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                        LineChartWidget(
                          data: provider.temperature,
                          color: Colors.red,
                          label: "Temperature",
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                        LineChartWidget(
                          data: provider.humidity,
                          color: Colors.cyan,
                          label: "Humidity",
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                        LineChartWidget(
                          data: provider.ec,
                          color: Colors.indigo,
                          label: "EC",
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                        MultiLineChartWidget(
                          pHData: provider.pH,
                          nData: provider.n,
                          pData: provider.p,
                          kData: provider.k,
                          temperatureData: provider.temperature,
                          humidityData: provider.humidity,
                          ecData: provider.ec,
                          timestamps: provider.timestamps,
                          zoomLevel: zoomLevel,
                          scrollIndex: scrollIndex,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
