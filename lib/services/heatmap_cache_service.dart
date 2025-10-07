import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings.dart';

class HeatmapCacheService {
  // Produce a stable key for a CSV content and metric label
  static String buildKey({required String csvContent, required String metric}) {
    final hash = sha1.convert(utf8.encode(csvContent)).toString();
    final safeMetric = metric.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${hash}_$safeMetric';
  }

  static Future<Directory> _ensureDir(String name, {String? basePath}) async {
    Directory base;
    if (basePath != null && basePath.isNotEmpty) {
      base = Directory(basePath);
      if (!await base.exists()) {
        await base.create(recursive: true);
      }
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> getPngFile(String key, {String? basePath}) async {
    final dir = await _ensureDir('heatmaps', basePath: basePath);
    return File('${dir.path}/$key.png');
  }

  static Future<bool> existsPng(String key, {String? basePath}) async {
    final file = await getPngFile(key, basePath: basePath);
    return file.exists();
  }

  static Future<File> writePng(String key, ui.Image image, {String? basePath}) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('Failed to encode PNG');
    final file = await getPngFile(key, basePath: basePath);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file;
  }

  static Future<File> getTexturedModelFile(String key, {String? basePath}) async {
    final dir = await _ensureDir('models', basePath: basePath);
    return File('${dir.path}/$key.glb');
  }

  static Future<bool> existsModel(String key, {String? basePath}) async {
    final file = await getTexturedModelFile(key, basePath: basePath);
    return file.exists();
  }
}
