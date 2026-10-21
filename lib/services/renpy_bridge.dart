import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/renpy_game.dart';

class RenpyBridge {
  static const MethodChannel _channel =
      MethodChannel('com.example.ax_app/renpy_bridge');

  /// Check if an execution engine (like JoiPlay Ren'Py plugin) is installed
  static Future<bool> isPluginInstalled() async {
    try {
      final bool? result = await _channel.invokeMethod('isPluginInstalled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if the app has full file access on Android 11+
  static Future<bool> hasAllFilesAccess() async {
    try {
      final bool? result = await _channel.invokeMethod('hasAllFilesAccess');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Request full file access on Android 11+
  static Future<bool> requestAllFilesAccess() async {
    try {
      final bool? result =
          await _channel.invokeMethod('requestAllFilesAccess');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launch the game via the native Ren'Py Android engine
  static Future<bool> launchRenpyGame({
    required String gamePath,
    required String executable,
  }) async {
    try {
      final bool? success = await _channel.invokeMethod('launchRenpyGame', {
        'gamePath': gamePath,
        'executable': executable,
      });
      return success ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Open link to download the Ren'Py plugin if not installed
  static Future<void> openPluginDownloadPage() async {
    try {
      await _channel.invokeMethod('openUrl', {
        'url': 'https://joiplay.cyou/',
      });
    } catch (_) {}
  }

  /// Get app internal files directory path
  static Future<String> getAppDataPath() async {
    try {
      final String? path = await _channel.invokeMethod('getAppDataPath');
      return path ?? Directory.systemTemp.path;
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  /// Get Android external storage root path (e.g. /storage/emulated/0)
  static Future<String> getExternalStoragePath() async {
    try {
      final String? path =
          await _channel.invokeMethod('getExternalStoragePath');
      return path ?? '/storage/emulated/0';
    } catch (_) {
      return '/storage/emulated/0';
    }
  }

  /// Load saved games from local JSON file
  static Future<List<RenpyGame>?> loadSavedGames() async {
    try {
      final dirPath = await getAppDataPath();
      final file = File(p.join(dirPath, 'saved_renpy_games.json'));
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final List<dynamic> decoded = json.decode(content);
      return decoded
          .map((item) => RenpyGame.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Save games list to local JSON file
  static Future<void> saveGames(List<RenpyGame> games) async {
    try {
      final dirPath = await getAppDataPath();
      final file = File(p.join(dirPath, 'saved_renpy_games.json'));
      final encoded = json.encode(games.map((g) => g.toMap()).toList());
      await file.writeAsString(encoded);
    } catch (_) {}
  }
}
