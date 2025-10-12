// lib/providers/csv_data_provider.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

class CSVDataProvider extends ChangeNotifier {
  List<double> pH = [];
  List<double> temperature = [];
  List<double> humidity = [];
  List<double> ec = [];
  List<double> n = [];
  List<double> p = [];
  List<double> k = [];
  List<DateTime> timestamps = [];
  List<double> latitudes = [];
  List<double> longitudes = [];
  List<String> plantStatus = [];
  String _sourceKey = '';

  String get sourceKey => _sourceKey;

  void updateData({
    required List<double> pH,
    required List<double> temperature,
    required List<double> humidity,
    required List<double> ec,
    required List<double> n,
    required List<double> p,
    required List<double> k,
    required List<DateTime> timestamps,
    required List<double> latitudes,
    required List<double> longitudes,
    List<String>? plantStatus,
  }) {
    this.pH = pH;
    this.temperature = temperature;
    this.humidity = humidity;
    this.ec = ec;
    this.n = n;
    this.p = p;
    this.k = k;
    this.timestamps = timestamps;
    this.latitudes = latitudes;
    this.longitudes = longitudes;
    this.plantStatus = plantStatus ?? [];
    _sourceKey = _computeDatasetHash();
    notifyListeners();
  }

  bool get hasData => timestamps.isNotEmpty;

  String _computeDatasetHash() {
    final parts = <String>[
      timestamps.map((d) => d.toIso8601String()).join(','),
      latitudes.map((v) => v.toString()).join(','),
      longitudes.map((v) => v.toString()).join(','),
      pH.map((v) => v.toString()).join(','),
      temperature.map((v) => v.toString()).join(','),
      humidity.map((v) => v.toString()).join(','),
      ec.map((v) => v.toString()).join(','),
      n.map((v) => v.toString()).join(','),
      p.map((v) => v.toString()).join(','),
      k.map((v) => v.toString()).join(','),
      plantStatus.join(','),
    ];
    final digest = sha1.convert(utf8.encode(parts.join('|'))).toString();
    return digest;
  }
}
