import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/renpy_game.dart';

class RenpyBridge {
  static const MethodChannel _channel =
      MethodChannel('com.example.ax_app/renpy_bridge');

  // Official verified URLs for JoiPlay & Ren'Py Plugin
  static const String officialPatreonUrl = 'https://www.patreon.com/joiplay';
  static const String officialGithubUrl = 'https://github.com/joiplay';
  static const String mirrorSearchUrl =
      'https://www.google.com/search?q=JoiPlay+RenPy+Plugin+APK+download';

  /// Check if an external execution engine (like JoiPlay Ren'Py plugin) is installed
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

  /// Launch the game via the native external Ren'Py Android engine
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

  /// Open any URL in the external browser
  static Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {
        'url': url,
      });
    } catch (_) {}
  }

  /// Shows a dialog with working official download sources and Built-in Engine status
  static Future<void> showPluginDownloadDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.extension_rounded, color: Colors.purpleAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'จัดการเอนจินและปลั๊กอิน Ren\'Py',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Built-in Engine Status (Always Ready)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.greenAccent, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Built-in RenPlay Engine (พร้อมใช้งาน)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'ทำงานในตัวแอปทันที รองรับการอ่านไฟล์สคริปต์ .rpy / .rpyc, ฉากหลัง, ตัวละคร และระบบ Save/Load โดยไม่ต้องลงแอปเพิ่ม',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ดาวน์โหลด External JoiPlay Ren\'Py Plugin (ทางเลือกเสริมสำหรับเกม 3D/Python ขั้นสูง):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.deepOrange,
                    child: Icon(Icons.public_rounded,
                        color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    '1. Official Patreon (โพสต์แจกฟรีทางการ)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'patreon.com/joiplay (เลื่อนดูโพสต์ Public เพื่อโหลด MEGA)',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () {
                    Navigator.pop(ctx);
                    openUrl(officialPatreonUrl);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blueGrey,
                    child:
                        Icon(Icons.code_rounded, color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    '2. Official GitHub (JoiPlay Project)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'github.com/joiplay (ซอร์สโค้ดและรีลีสทางการ)',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () {
                    Navigator.pop(ctx);
                    openUrl(officialGithubUrl);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.search_rounded,
                        color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    '3. ค้นหาลิงก์ดาวน์โหลดตรง (Mirror APK)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'ค้นหาไฟล์ APK ของ JoiPlay Ren\'Py Plugin เวอร์ชันล่าสุด',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () {
                    Navigator.pop(ctx);
                    openUrl(mirrorSearchUrl);
                  },
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ปิด'),
            ),
          ],
        );
      },
    );
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
