// Assuming this is the adjusted code
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dashboard')), 
      body: Column(
        children: <Widget>[
          // Only displaying necessary metrics below
          MetricCard(title: 'pH', value: '6.0'),
          MetricCard(title: 'Temperature', value: '22°C'),
          MetricCard(title: 'Humidity', value: '50%'),
          MetricCard(title: 'EC', value: '1.5 mS/cm'),
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;

  MetricCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Text(title, style: TextStyle(fontSize: 20)),
            SizedBox(height: 10),
            Text(value, style: TextStyle(fontSize: 24)),
          ],
        ),
      ),
    );
  }
}
