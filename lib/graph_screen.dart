import 'package:flutter/material.dart';

class GraphScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Graph Screen'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'pH'),
              Tab(text: 'Temperature'),
              Tab(text: 'Humidity'),
              Tab(text: 'EC'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // pH graph widget
            Container(
              color: Colors.green,
              child: Center(child: Text('pH Graph')), // Placeholder for pH graph
            ),
            // Temperature graph widget
            Container(
              color: Colors.blue,
              child: Center(child: Text('Temperature Graph')), // Placeholder for Temperature graph
            ),
            // Humidity graph widget
            Container(
              color: Colors.yellow,
              child: Center(child: Text('Humidity Graph')), // Placeholder for Humidity graph
            ),
            // EC graph widget
            Container(
              color: Colors.orange,
              child: Center(child: Text('EC Graph')), // Placeholder for EC graph
            ),
          ],
        ),
      ),
    );
  }
}