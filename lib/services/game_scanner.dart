import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/renpy_game.dart';

class ScanResult {
  final bool isValidRenpy;
  final String title;
  final String rootPath;
  final String executableName;
  final String? iconPath;
  final String? coverPath;
  final String renpyVersion;
  final String? errorMessage;

  ScanResult({
    required this.isValidRenpy,
    required this.title,
    required this.rootPath,
    required this.executableName,
    this.iconPath,
    this.coverPath,
    this.renpyVersion = 'Ren\'Py 7/8',
    this.errorMessage,
  });
}

class GameScanner {
  /// Scans a directory or specific executable file to verify and extract Ren'Py metadata
  static Future<ScanResult> scanDirectory(String targetPath) async {
    try {
      Directory dir;
      String execName = '';

      if (await File(targetPath).exists()) {
        final file = File(targetPath);
        dir = file.parent;
        execName = p.basename(file.path);
      } else if (await Directory(targetPath).exists()) {
        dir = Directory(targetPath);
      } else {
        return ScanResult(
          isValidRenpy: false,
          title: '',
          rootPath: targetPath,
          executableName: '',
          errorMessage: 'ไม่พบโฟลเดอร์หรือไฟล์ที่เลือก',
        );
      }

      // Check if folder contains "game" directory
      final gameDir = Directory(p.join(dir.path, 'game'));
      final renpyDir = Directory(p.join(dir.path, 'renpy'));

      bool hasGameDir = await gameDir.exists();
      bool hasRenpyDir = await renpyDir.exists();

      // Look for .rpy or .rpyc files
      bool hasRpyFiles = false;
      String? discoveredIcon;
      String? discoveredCover;
      String detectedVersion = 'Ren\'Py 7/8 (PC)';

      if (hasGameDir) {
        try {
          final gameFiles = gameDir.listSync(recursive: false);
          for (final entity in gameFiles) {
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (ext == '.rpyc' || ext == '.rpy' || ext == '.rpa') {
                hasRpyFiles = true;
              }
            }
          }

          // Search for GUI images in game/gui or game
          final possibleIcons = [
            p.join(gameDir.path, 'gui', 'window_icon.png'),
            p.join(gameDir.path, 'icon.png'),
            p.join(dir.path, 'icon.png'),
          ];
          for (final iconP in possibleIcons) {
            if (await File(iconP).exists()) {
              discoveredIcon = iconP;
              break;
            }
          }

          final possibleCovers = [
            p.join(gameDir.path, 'gui', 'main_menu.png'),
            p.join(gameDir.path, 'gui', 'game_menu.png'),
            p.join(gameDir.path, 'cover.png'),
            p.join(dir.path, 'cover.jpg'),
          ];
          for (final coverP in possibleCovers) {
            if (await File(coverP).exists()) {
              discoveredCover = coverP;
              break;
            }
          }
        } catch (_) {}
      }

      // If executable name wasn't set, find the first .exe in the root
      if (execName.isEmpty) {
        try {
          final rootFiles = dir.listSync();
          for (final entity in rootFiles) {
            if (entity is File &&
                p.extension(entity.path).toLowerCase() == '.exe') {
              execName = p.basename(entity.path);
              break;
            }
          }
        } catch (_) {}
      }

      // If still empty, use the directory name
      String defaultTitle = p.basename(dir.path);
      if (execName.isNotEmpty &&
          execName.toLowerCase() != 'python.exe' &&
          execName.toLowerCase() != 'renpy.exe') {
        defaultTitle = p.basenameWithoutExtension(execName);
      }

      // Check if it's Ren'Py 8 (look for python3 in renpy directory or scripts)
      if (hasRenpyDir) {
        final py3File = File(p.join(renpyDir.path, 'py3-linux-x86_64'));
        if (await py3File.exists()) {
          detectedVersion = 'Ren\'Py 8 (Python 3)';
        }
      }

      bool isValid = hasGameDir || hasRpyFiles || hasRenpyDir;

      return ScanResult(
        isValidRenpy: isValid,
        title: defaultTitle,
        rootPath: dir.path,
        executableName: execName,
        iconPath: discoveredIcon,
        coverPath: discoveredCover,
        renpyVersion: detectedVersion,
        errorMessage: isValid
            ? null
            : 'ไม่พบโฟลเดอร์ game/ หรือไฟล์สคริปต์ .rpyc ของ Ren\'Py',
      );
    } catch (e) {
      return ScanResult(
        isValidRenpy: false,
        title: '',
        rootPath: targetPath,
        executableName: '',
        errorMessage: 'เกิดข้อผิดพลาดในการตรวจสอบไฟล์: $e',
      );
    }
  }

  /// Create sample demo game structure for testing
  static RenpyGame createDemoGame() {
    return RenpyGame(
      id: 'demo_game_001',
      title: 'The Question (Ren\'Py Demo)',
      path: '/sdcard/Download/TheQuestion',
      executableName: 'TheQuestion.exe',
      renpyVersion: 'Ren\'Py 8 (Python 3)',
      dateAdded: DateTime.now(),
      playTimeMinutes: 15,
      isFavorite: true,
    );
  }
}
