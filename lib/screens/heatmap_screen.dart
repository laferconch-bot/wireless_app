// Updated heatmap_screen.dart, removing Plant Status and simplifying metrics.

import 'package:flutter/material.dart';

class HeatmapScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Heatmap'),
      ),
      body: Center(
        child: Column(
          children: <Widget>[ 
            // Simplified metrics
            Text('pH Level: 7.0'),
            Text('Temperature: 25°C'),
            Text('Humidity: 60%'),
            Text('EC Level: 1.5 mS/cm'),
          ],
        ),
      ),
    );
  }
}