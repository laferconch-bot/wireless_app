import 'package:flutter/material.dart';
import 'package:your_app/widgets/metric_tile.dart';
import 'package:your_app/screens/settings_screen.dart';

class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            MetricTile(title: 'pH', value: '6.5'),
            MetricTile(title: 'Temperature', value: '22° C'),
            MetricTile(title: 'Humidity', value: '50%'),
            MetricTile(title: 'EC', value: '1.2 mS/cm'),
          ],
        ),
      ),
    );
  }
}