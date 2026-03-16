import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: const Column(
        children: <Widget>[
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

  const MetricCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Text(title, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 24)),
          ],
        ),
      ),
    );
  }
}
