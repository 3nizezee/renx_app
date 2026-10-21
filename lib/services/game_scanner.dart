import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../engine/game_fs.dart';
import '../engine/mini_python.dart';
import '../engine/rpy_parser.dart';
import '../engine/rpyc_reader.dart';
import '../engine/script_ast.dart';

class ScanResult {
  final bool isValidRenpy;
  final String title;
  final String rootPath;
  final String executableName;
  final String? iconPath;
  final String? coverPath;
  final String renpyVersion;
  final int archiveCount;
  final int scriptCount;
  final int assetCount;
  final String? errorMessage;

  const ScanResult({
    required this.isValidRenpy,
    required this.title,
    required this.rootPath,
    required this.executableName,
    this.iconPath,
    this.coverPath,
    this.renpyVersion = 'Ren\'Py 7/8',
    this.archiveCount = 0,
    this.scriptCount = 0,
    this.assetCount = 0,
    this.errorMessage,
  });
}

class GameScanner {
  /// Scans a directory or executable path, mounts its `.rpa` archives and
  /// `game/` directory, and extracts real metadata and artwork.
  static Future<ScanResult> scanDirectory(String targetPath) async {
    try {
      String execName = '';
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        final ext = p.extension(targetFile.path).toLowerCase();
        if (ext == '.exe' || ext == '.py' || ext == '.sh') {
          execName = p.basename(targetFile.path);
        }
      }

      final fs = await GameFileSystem.mount(targetPath);
      if (fs == null) {
        return ScanResult(
          isValidRenpy: false,
          title: '',
          rootPath: targetPath,
          executableName: '',
          errorMessage: 'ไม่พบโฟลเดอร์หรือไฟล์ที่ระบุ กรุณาตรวจสอบพาธอีกครั้ง',
        );
      }

      final rootDir = Directory(fs.rootPath);

      // Count script files (.rpyc and .rpy) across disk + .rpa archives
      final scriptStems = <String>{};
      for (final key in fs.assets.keys) {
        if (key.startsWith('renpy/') || key.startsWith('cache/')) continue;
        if (key.endsWith('.rpyc')) {
          scriptStems.add(key.substring(0, key.length - 5));
        } else if (key.endsWith('.rpy')) {
          scriptStems.add(key.substring(0, key.length - 4));
        }
      }

      // Discover .exe in rootDir if not explicitly selected
      if (execName.isEmpty) {
        try {
          for (final entity in rootDir.listSync()) {
            if (entity is File &&
                p.extension(entity.path).toLowerCase() == '.exe') {
              final base = p.basename(entity.path);
              if (base.toLowerCase() != 'python.exe' &&
                  base.toLowerCase() != 'pythonw.exe' &&
                  base.toLowerCase() != 'renpy.exe' &&
                  !base.toLowerCase().startsWith('dxwebsetup')) {
                execName = base;
                break;
              }
            }
          }
        } catch (_) {}
      }

      // Inspect options.rpyc / options.rpy for `config.name` and `config.version`
      final py = MiniPython();
      await _evaluateOptionsFile(fs, py, 'options.rpyc', isRpyc: true);
      if (!py.store.containsKey('config.name')) {
        await _evaluateOptionsFile(fs, py, 'options.rpy', isRpyc: false);
      }

      String? configuredTitle;
      final rawConfigName =
          py.store['config.name'] ?? py.store['config.window_title'];
      if (rawConfigName is String && rawConfigName.trim().isNotEmpty) {
        configuredTitle = py.formatText(rawConfigName);
      }

      String? configuredVersion;
      final rawConfigVer = py.store['config.version'];
      if (rawConfigVer is String && rawConfigVer.trim().isNotEmpty) {
        configuredVersion = rawConfigVer.trim();
      }

      // Determine fallback title from executable or folder name
      String resolvedTitle = configuredTitle ?? p.basename(rootDir.path);
      if (configuredTitle == null &&
          execName.isNotEmpty &&
          execName.toLowerCase() != 'python.exe' &&
          execName.toLowerCase() != 'renpy.exe') {
        resolvedTitle = p.basenameWithoutExtension(execName);
      }

      // Detect Ren'Py / Python generation
      String detectedVersion = 'Ren\'Py 7/8';
      final renpyDir = Directory(p.join(rootDir.path, 'renpy'));
      final libDir = Directory(p.join(rootDir.path, 'lib'));
      try {
        if (await libDir.exists()) {
          final libEntries =
              libDir.listSync().map((e) => p.basename(e.path).toLowerCase());
          if (libEntries.any((n) => n.contains('py3'))) {
            detectedVersion = 'Ren\'Py 8 (Py3)';
          } else if (libEntries.any((n) => n.contains('py2'))) {
            detectedVersion = 'Ren\'Py 7 (Py2)';
          }
        }
      } catch (_) {}
      if (configuredVersion != null && configuredVersion.isNotEmpty) {
        detectedVersion = '$detectedVersion • v$configuredVersion';
      }

      // Extract or locate icon and cover artwork (even from inside .rpa archives)
      final iconPath = await _extractArtworkPath(
        fs,
        rootDir.path,
        tag: 'icon',
        candidates: const <String>[
          'gui/window_icon.png',
          'icon.png',
          'android-icon_foreground.png',
        ],
      );

      final coverPath = await _extractArtworkPath(
        fs,
        rootDir.path,
        tag: 'cover',
        candidates: const <String>[
          'gui/main_menu.png',
          'gui/overlay/main_menu.png',
          'gui/game_menu.png',
          'presplash.png',
          'presplash.jpg',
          'cover.png',
          'cover.jpg',
        ],
      );

      final bool hasRenpyDir = await renpyDir.exists();
      final bool isValid =
          scriptStems.isNotEmpty || fs.archives.isNotEmpty || hasRenpyDir;

      return ScanResult(
        isValidRenpy: isValid,
        title: resolvedTitle,
        rootPath: rootDir.path,
        executableName: execName,
        iconPath: iconPath,
        coverPath: coverPath,
        renpyVersion: detectedVersion,
        archiveCount: fs.archives.length,
        scriptCount: scriptStems.length,
        assetCount: fs.assets.length,
        errorMessage: isValid
            ? null
            : 'ไม่พบไฟล์สคริปต์ (.rpyc / .rpy) หรือคลังข้อมูล (.rpa) ในโฟลเดอร์ที่เลือก',
      );
    } catch (e) {
      return ScanResult(
        isValidRenpy: false,
        title: '',
        rootPath: targetPath,
        executableName: '',
        errorMessage: 'เกิดข้อผิดพลาดขณะตรวจสอบโครงสร้างไฟล์เกม: $e',
      );
    }
  }

  static Future<void> _evaluateOptionsFile(
    GameFileSystem fs,
    MiniPython py,
    String virtualPath, {
    required bool isRpyc,
  }) async {
    final bytes = await fs.readBytes(virtualPath);
    if (bytes == null || bytes.length > 512 * 1024) return;

    ScriptFile? file;
    try {
      if (isRpyc) {
        file = RpycReader.decodeBytes(bytes, virtualPath: virtualPath);
      } else {
        final text = utf8.decode(bytes, allowMalformed: true);
        file = RpyParser.parseSource(text, virtualPath: virtualPath);
      }
    } catch (_) {
      return;
    }
    if (file == null) return;

    void walk(ScriptBlock block) {
      for (final node in block.nodes) {
        if (node is InitNode) {
          walk(node.block);
        } else if (node is DefineNode) {
          py.applyAssignment(
            node.name,
            node.operator,
            py.evaluate(node.expression),
          );
        } else if (node is DefaultNode) {
          py.store.putIfAbsent(node.name, () => py.evaluate(node.expression));
        } else if (node is PythonNode) {
          py.execute(node.source);
        }
      }
    }

    walk(file.block);
  }

  static Future<String?> _extractArtworkPath(
    GameFileSystem fs,
    String rootDirPath, {
    required String tag,
    required List<String> candidates,
  }) async {
    // 1. Check virtual file system (disk or .rpa archive)
    for (final candidate in candidates) {
      final key = candidate.toLowerCase();
      final source = fs.assets[key];
      if (source != null) {
        if (source.diskPath != null && await File(source.diskPath!).exists()) {
          return source.diskPath;
        }
        final bytes = await fs.readBytes(key);
        if (bytes != null && bytes.isNotEmpty) {
          try {
            final cacheDir = Directory(
              p.join(Directory.systemTemp.path, 'renplay_art_cache'),
            );
            if (!await cacheDir.exists()) {
              await cacheDir.create(recursive: true);
            }
            final hash = rootDirPath.hashCode.unsignedAbs();
            final ext = p.posix.extension(key);
            final outFile = File(
              p.join(cacheDir.path, 'game_${hash}_$tag$ext'),
            );
            await outFile.writeAsBytes(bytes, flush: true);
            return outFile.path;
          } catch (_) {}
        }
      }
    }

    // 2. Check root directory directly
    for (final name in <String>['icon.png', 'cover.png', 'cover.jpg']) {
      final f = File(p.join(rootDirPath, name));
      if (await f.exists()) return f.path;
    }
    return null;
  }
}

extension on int {
  int unsignedAbs() => abs();
}
