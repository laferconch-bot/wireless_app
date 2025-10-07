import 'package:flutter/foundation.dart';

class AppSettings extends ChangeNotifier {
  String _saveDirectory = '';

  String get saveDirectory => _saveDirectory;

  void setSaveDirectory(String dir) {
    _saveDirectory = dir;
    notifyListeners();
  }
}
