import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/renpy_game.dart';

class RenpyBridge {
  static const MethodChannel _channel =
      MethodChannel('com.example.ax_app/renpy_bridge');

  static const String officialPatreonUrl = 'https://www.patreon.com/joiplay';
  static const String officialGithubUrl = 'https://github.com/joiplay';
  static const String mirrorSearchUrl =
      'https://www.google.com/search?q=JoiPlay+RenPy+Plugin+APK+download';

  static Future<bool> isPluginInstalled() async {
    try {
      final bool? result = await _channel.invokeMethod('isPluginInstalled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasAllFilesAccess() async {
    try {
      final bool? result = await _channel.invokeMethod('hasAllFilesAccess');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> requestAllFilesAccess() async {
    try {
      final bool? result =
          await _channel.invokeMethod('requestAllFilesAccess');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

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
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {
        'url': url,
      });
    } catch (_) {}
  }

  static Future<void> showPluginDownloadDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF11151F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232A3B), width: 1),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF3B82F6).withOpacity(0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.memory_rounded,
                          color: Color(0xFF60A5FA),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ระบบจัดการเอนจินและปลั๊กอิน',
                              style: TextStyle(
                                color: Color(0xFFF3F6FC),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Built-in AST VM และตัวเชื่อมต่อปลั๊กอินภายนอก',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.35),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF34D399),
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RenPlay Core Engine (ทำงานในตัวแอป)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF34D399),
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'ถอดรหัสไฟล์ไบนารี .rpyc (RENPY RPC2), แตกคลังข้อมูล .rpa (RPA-3.0 / RPA-2.0) และรันสคริปต์ .rpy ของเกมจริงโดยตรง ไม่ต้องติดตั้งแอปเสริม',
                                style: TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'แหล่งดาวน์โหลด External Runtime (ทางเลือกเสริม)',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildLinkTile(
                    icon: Icons.public_rounded,
                    accentColor: const Color(0xFF3B82F6),
                    title: 'Official Patreon Repository',
                    subtitle: 'patreon.com/joiplay (โพสต์สาธารณะทางการ)',
                    onTap: () {
                      Navigator.pop(ctx);
                      openUrl(officialPatreonUrl);
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildLinkTile(
                    icon: Icons.code_rounded,
                    accentColor: const Color(0xFF06B6D4),
                    title: 'Official GitHub Organization',
                    subtitle: 'github.com/joiplay (ซอร์สโค้ดและแพ็กเกจเสริม)',
                    onTap: () {
                      Navigator.pop(ctx);
                      openUrl(officialGithubUrl);
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildLinkTile(
                    icon: Icons.travel_explore_rounded,
                    accentColor: const Color(0xFF6366F1),
                    title: 'ค้นหาไฟล์ติดตั้ง APK ล่าสุด',
                    subtitle: 'ค้นหาลิงก์ดาวน์โหลดตรงผ่านเว็บเบราว์เซอร์',
                    onTap: () {
                      Navigator.pop(ctx);
                      openUrl(mirrorSearchUrl);
                    },
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF232A3B),
                        foregroundColor: const Color(0xFFF3F6FC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('ปิดหน้าต่าง'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildLinkTile({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF171C29),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF232A3B)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF3F6FC),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                color: Color(0xFF64748B),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<String> getAppDataPath() async {
    try {
      final String? path = await _channel.invokeMethod('getAppDataPath');
      return path ?? Directory.systemTemp.path;
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  static Future<String> getExternalStoragePath() async {
    try {
      final String? path =
          await _channel.invokeMethod('getExternalStoragePath');
      return path ?? '/storage/emulated/0';
    } catch (_) {
      return '/storage/emulated/0';
    }
  }

  /// Loads saved user games from disk, automatically purging any legacy built-in
  /// demo entries (`demo_game_001`) so only real user games appear.
  static Future<List<RenpyGame>> loadSavedGames() async {
    try {
      final dirPath = await getAppDataPath();
      final file = File(p.join(dirPath, 'saved_renpy_games.json'));
      if (!await file.exists()) return <RenpyGame>[];
      final content = await file.readAsString();
      final List<dynamic> decoded = json.decode(content) as List<dynamic>;
      final games = decoded
          .map((item) => RenpyGame.fromMap(Map<String, dynamic>.from(item as Map)))
          .where((g) => g.id != 'demo_game_001' && !g.title.contains('(Ren\'Py Demo)'))
          .toList();
      return games;
    } catch (_) {
      return <RenpyGame>[];
    }
  }

  static Future<void> saveGames(List<RenpyGame> games) async {
    try {
      final dirPath = await getAppDataPath();
      final file = File(p.join(dirPath, 'saved_renpy_games.json'));
      final encoded = json.encode(games.map((g) => g.toMap()).toList());
      await file.writeAsString(encoded);
    } catch (_) {}
  }

  static Future<Map<int, Map<String, dynamic>>> loadGameSaveSlots(
    String gameId,
  ) async {
    try {
      final dirPath = await getAppDataPath();
      final file = File(p.join(dirPath, 'renplay_saves_$gameId.json'));
      if (!await file.exists()) return <int, Map<String, dynamic>>{};
      final raw = json.decode(await file.readAsString()) as Map;
      final out = <int, Map<String, dynamic>>{};
      for (final entry in raw.entries) {
        final slotNum = int.tryParse(entry.key.toString());
        if (slotNum != null && entry.value is Map) {
          out[slotNum] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
      return out;
    } catch (_) {
      return <int, Map<String, dynamic>>{};
    }
  }

  static Future<void> saveGameSaveSlots(
    String gameId,
    Map<int, Map<String, dynamic>> slots,
  ) async {
    try {
      final dirPath = await getAppDataPath();
      final file = File(p.join(dirPath, 'renplay_saves_$gameId.json'));
      final serializable = <String, dynamic>{};
      for (final entry in slots.entries) {
        serializable[entry.key.toString()] = entry.value;
      }
      await file.writeAsString(json.encode(serializable));
    } catch (_) {}
  }
}
