import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class HeatmapCacheService {
  // Produce a stable key for a CSV content and metric label
  static String buildKey({required String csvContent, required String metric}) {
    final hash = sha1.convert(utf8.encode(csvContent)).toString();
    final safeMetric = metric.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${hash}_$safeMetric';
  }

  static Future<Directory> _ensureDir(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> getPngFile(String key) async {
    final dir = await _ensureDir('heatmaps');
    return File('${dir.path}/$key.png');
  }

  static Future<bool> existsPng(String key) async {
    final file = await getPngFile(key);
    return file.exists();
  }

  static Future<File> writePng(String key, ui.Image image) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('Failed to encode PNG');
    final file = await getPngFile(key);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file;
  }

  static Future<File> getTexturedModelFile(String key) async {
    final dir = await _ensureDir('models');
    return File('${dir.path}/$key.glb');
  }

  static Future<bool> existsModel(String key) async {
    final file = await getTexturedModelFile(key);
    return file.exists();
  }
}
