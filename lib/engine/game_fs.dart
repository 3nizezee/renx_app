import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import 'rpa_archive.dart';
import 'rpy_parser.dart';
import 'rpyc_reader.dart';
import 'script_ast.dart';

class AssetSource {
  const AssetSource.disk(this.diskPath, this.virtualPath)
      : archive = null,
        rpaEntry = null;

  const AssetSource.rpa(this.archive, this.rpaEntry, this.virtualPath)
      : diskPath = null;

  final String? diskPath;
  final RpaArchive? archive;
  final RpaEntry? rpaEntry;
  final String virtualPath;

  bool get isFromArchive => archive != null && rpaEntry != null;
}

class ScriptCandidatePair {
  ScriptCandidatePair(this.stem);

  final String stem;
  AssetSource? rpy;
  AssetSource? rpyc;
}

/// Unified virtual file system across a Ren'Py game's `game/` folder on disk
/// and all `.rpa` archives inside it.
class GameFileSystem {
  GameFileSystem._({
    required this.rootPath,
    required this.gameDirPath,
    required this.archives,
    required this.assets,
    required this.imageIndex,
  });

  final String rootPath;
  final String gameDirPath;
  final List<RpaArchive> archives;

  /// Virtual path (lowercase, forward slashes, relative to `game/`) -> source.
  final Map<String, AssetSource> assets;

  /// Canonical lowercase image key (e.g. `'bg uni'` or `'sylvie green smile'`)
  /// -> virtual path in [assets].
  final Map<String, String> imageIndex;

  /// In-memory LRU cache of recently loaded asset bytes.
  final Map<String, Uint8List> _byteCache = <String, Uint8List>{};

  /// Script files deferred during initial fast boot so huge games start within
  /// 1–3 seconds and load remaining chapter files on demand.
  final List<ScriptCandidatePair> deferredScripts = <ScriptCandidatePair>[];

  int _nextBlockId = 1;

  static GameFileSystem? _cachedFs;
  static String? _cachedInputPath;

  static const Set<String> _imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
  };

  static const Set<String> _skippedDirectories = <String>{
    'saves',
    'cache',
    'renpy',
    'lib',
    'log',
    '.git',
    '__pycache__',
  };

  /// Mounts a Ren'Py project directory (or a path to its `.exe` or `game/`
  /// subdirectory) and indexes loose files and `.rpa` archives asynchronously.
  static Future<GameFileSystem?> mount(
    String inputPath, {
    void Function(String status)? onProgress,
    bool useCache = true,
  }) async {
    final normInput = p.normalize(inputPath);
    if (useCache && _cachedFs != null && _cachedInputPath == normInput) {
      return _cachedFs;
    }

    Directory baseDir;
    final f = File(inputPath);
    if (await f.exists()) {
      baseDir = f.parent;
    } else {
      baseDir = Directory(inputPath);
    }
    if (!await baseDir.exists()) return null;

    Directory rootDir = baseDir;
    Directory gameDir = Directory(p.join(baseDir.path, 'game'));

    if (!await gameDir.exists()) {
      if (p.basename(baseDir.path).toLowerCase() == 'game') {
        gameDir = baseDir;
        rootDir = baseDir.parent;
      } else {
        // Check one level down in case the archive extracted into a wrapper folder
        try {
          await for (final child in baseDir.list(followLinks: false)) {
            if (child is Directory) {
              final candidate = Directory(p.join(child.path, 'game'));
              if (await candidate.exists()) {
                rootDir = child;
                gameDir = candidate;
                break;
              }
            }
          }
        } catch (_) {}
      }
    }

    final bool hasDedicatedGameDir = await gameDir.exists();
    if (!hasDedicatedGameDir) {
      gameDir = baseDir;
    }

    final assets = <String, AssetSource>{};
    final archives = <RpaArchive>[];
    final rpaFiles = <File>[];

    onProgress?.call('กำลังสแกนไฟล์ในโฟลเดอร์เกม...');
    await Future<void>.delayed(Duration.zero);

    // 1. Scan loose files asynchronously with depth and count protection
    final int maxScanDepth = hasDedicatedGameDir ? 5 : 2;
    int scannedCount = 0;

    Future<void> walkDir(Directory dir, int depth) async {
      if (depth > maxScanDepth || scannedCount > 25000) return;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          scannedCount++;
          if (scannedCount % 250 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          if (entity is Directory) {
            final dirName = p.basename(entity.path).toLowerCase();
            if (_skippedDirectories.contains(dirName)) continue;
            if (dirName == 'tl') continue;
            await walkDir(entity, depth + 1);
          } else if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.rpa') {
              rpaFiles.add(entity);
              continue;
            }
            final rel = p
                .relative(entity.path, from: gameDir.path)
                .replaceAll(r'\', '/');
            assets[rel.toLowerCase()] = AssetSource.disk(entity.path, rel);
          }
        }
      } catch (_) {}
    }

    await walkDir(gameDir, 0);

    // 2. Open .rpa archives and merge their entries
    rpaFiles.sort((a, b) => a.path.compareTo(b.path));
    for (int i = 0; i < rpaFiles.length; i++) {
      final rpaFile = rpaFiles[i];
      final rpaName = p.basename(rpaFile.path);
      onProgress?.call(
        'กำลังเมานต์คลังข้อมูล $rpaName (${i + 1}/${rpaFiles.length})...',
      );
      await Future<void>.delayed(Duration.zero);

      final archive = await RpaArchive.open(rpaFile.path);
      if (archive != null) {
        archives.add(archive);
        for (final entry in archive.entries.values) {
          final key = entry.virtualPath.toLowerCase();
          assets.putIfAbsent(
            key,
            () => AssetSource.rpa(archive, entry, entry.virtualPath),
          );
        }
      }
    }

    // 3. Build automatic image lookup index matching Ren'Py's image rules
    onProgress?.call('กำลังจัดทำดัชนีรูปภาพและทรัพยากร...');
    await Future<void>.delayed(Duration.zero);

    final imageIndex = <String, String>{};
    int imgCounter = 0;
    for (final entry in assets.entries) {
      final vPath = entry.key;
      final ext = p.posix.extension(vPath);
      if (!_imageExtensions.contains(ext)) continue;

      imgCounter++;
      if (imgCounter % 800 == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final noExt = vPath.substring(0, vPath.length - ext.length);
      imageIndex[noExt] = vPath;
      imageIndex[vPath] = vPath;

      final baseName = p.posix.basenameWithoutExtension(vPath).toLowerCase();
      imageIndex.putIfAbsent(baseName, () => vPath);

      final spaceNormalized =
          baseName.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      imageIndex.putIfAbsent(spaceNormalized, () => vPath);

      final underscoreNormalized =
          baseName.replaceAll(RegExp(r'\s+'), '_').trim();
      imageIndex.putIfAbsent(underscoreNormalized, () => vPath);

      final parts = noExt.split('/');
      if (parts.length >= 3 && parts.first == 'images') {
        final folderTag = parts[1];
        if (!spaceNormalized.startsWith('$folderTag ')) {
          imageIndex.putIfAbsent('$folderTag $spaceNormalized', () => vPath);
        }
      }
    }

    final fs = GameFileSystem._(
      rootPath: rootDir.path,
      gameDirPath: gameDir.path,
      archives: archives,
      assets: assets,
      imageIndex: imageIndex,
    );
    _cachedFs = fs;
    _cachedInputPath = normInput;
    return fs;
  }

  /// Reads the bytes of a virtual path (case-insensitive) from disk or `.rpa`.
  Future<Uint8List?> readBytes(String virtualPath) async {
    final norm = virtualPath
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'^/+'), '')
        .toLowerCase();

    if (_byteCache.containsKey(norm)) {
      return _byteCache[norm];
    }

    var source = assets[norm];
    if (source == null && !norm.startsWith('images/')) {
      source = assets['images/$norm'];
    }
    if (source == null) {
      final targetBase = p.posix.basename(norm);
      for (final entry in assets.entries) {
        if (p.posix.basename(entry.key) == targetBase) {
          source = entry.value;
          break;
        }
      }
    }
    if (source == null) return null;

    Uint8List? bytes;
    if (source.diskPath != null) {
      try {
        bytes = await File(source.diskPath!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    } else if (source.archive != null && source.rpaEntry != null) {
      bytes = await source.archive!.readEntry(source.rpaEntry!);
    }

    if (bytes != null) {
      if (_byteCache.length >= 32) {
        _byteCache.remove(_byteCache.keys.first);
      }
      _byteCache[norm] = bytes;
    }
    return bytes;
  }

  /// Resolves an image name or filename to its virtual path in [assets].
  String? resolveImageVirtualPath(
    List<String> nameParts, {
    Map<String, String>? definedImages,
  }) {
    if (nameParts.isEmpty) return null;
    final joined = nameParts.join(' ').toLowerCase().trim();

    if (definedImages != null) {
      final mapped = definedImages[joined];
      if (mapped != null) {
        final norm = mapped.replaceAll(r'\', '/').toLowerCase();
        if (assets.containsKey(norm)) return norm;
        if (imageIndex.containsKey(norm)) return imageIndex[norm];
        final base = p.posix.basenameWithoutExtension(norm);
        if (imageIndex.containsKey(base)) return imageIndex[base];
      }
    }

    if (imageIndex.containsKey(joined)) {
      return imageIndex[joined];
    }

    final underscored = nameParts.join('_').toLowerCase();
    if (imageIndex.containsKey(underscored)) {
      return imageIndex[underscored];
    }

    final tag = nameParts.first.toLowerCase();
    final attrs = nameParts.sublist(1).map((s) => s.toLowerCase()).toSet();

    String? bestMatch;
    int bestScore = 0;

    for (final entry in imageIndex.entries) {
      final key = entry.key;
      if (!key.contains(tag)) continue;
      final tokens = key
          .replaceAll('_', ' ')
          .split(RegExp(r'[\s/]+'))
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.isEmpty || !tokens.contains(tag)) continue;

      int score = 1;
      for (final attr in attrs) {
        if (tokens.contains(attr)) score += 2;
      }
      if (score > bestScore) {
        bestScore = score;
        bestMatch = entry.value;
      }
    }

    return bestMatch;
  }

  static bool _shouldSkipScriptStem(String stem) {
    final baseName = p.posix.basename(stem).toLowerCase();
    if (baseName.startsWith('00')) return true;
    const skippedStems = <String>{
      'screens',
      'gui',
      'gallery',
      'music_room',
      'musicroom',
      'achievements',
      'keymap',
      'navigation',
      'credits',
    };
    return skippedStems.contains(baseName);
  }

  static int _scriptPriorityScore(String stem) {
    final base = p.posix.basename(stem).toLowerCase();
    if (base == 'options') return 0;
    if (base == 'definitions' ||
        base == 'defs' ||
        base == 'characters' ||
        base == 'init' ||
        base == 'vars' ||
        base == 'variables' ||
        base == 'setup') {
      return 1;
    }
    if (base == 'script' || base == 'start' || base == 'main') return 2;
    if (base.startsWith('prologue') ||
        base.startsWith('intro') ||
        base.startsWith('ch0') ||
        base.startsWith('ch1') ||
        base.startsWith('chapter1') ||
        base.startsWith('chapter_1') ||
        base.startsWith('day1') ||
        base.startsWith('act1')) {
      return 3;
    }
    return 10;
  }

  /// Discovers and loads Ren'Py script files (`.rpyc` and `.rpy`) with priority
  /// ordering and time-budgeted deferred loading so large games start quickly.
  Future<ScriptLoadResult> loadAllScripts({
    void Function(String status)? onProgress,
  }) async {
    deferredScripts.clear();
    _nextBlockId = 1;

    final candidates = <String, ScriptCandidatePair>{};

    for (final entry in assets.entries) {
      final key = entry.key;
      if (key.startsWith('tl/') ||
          key.startsWith('renpy/') ||
          key.startsWith('cache/') ||
          key.startsWith('saves/')) {
        continue;
      }

      if (key.endsWith('.rpy')) {
        final stem = key.substring(0, key.length - 4);
        if (_shouldSkipScriptStem(stem)) continue;
        candidates
            .putIfAbsent(stem, () => ScriptCandidatePair(stem))
            .rpy = entry.value;
      } else if (key.endsWith('.rpyc')) {
        final stem = key.substring(0, key.length - 5);
        if (_shouldSkipScriptStem(stem)) continue;
        candidates
            .putIfAbsent(stem, () => ScriptCandidatePair(stem))
            .rpyc = entry.value;
      }
    }

    final pairs = candidates.values.toList()
      ..sort((a, b) {
        final pa = _scriptPriorityScore(a.stem);
        final pb = _scriptPriorityScore(b.stem);
        if (pa != pb) return pa.compareTo(pb);
        return a.stem.compareTo(b.stem);
      });

    final loadedFiles = <ScriptFile>[];
    final errors = <String>[];
    final stopwatch = Stopwatch()..start();
    bool foundStartLabel = false;

    for (int i = 0; i < pairs.length; i++) {
      final pair = pairs[i];
      final priority = _scriptPriorityScore(pair.stem);

      // Once priority files and `label start` are loaded, if initial boot has
      // already spent > 2.5 seconds and we have at least 6 loaded files, defer
      // remaining secondary chapter files for on-demand loading.
      if (foundStartLabel &&
          priority >= 10 &&
          loadedFiles.length >= 6 &&
          stopwatch.elapsedMilliseconds > 2500) {
        deferredScripts.addAll(pairs.sublist(i));
        break;
      }

      final shortName = p.posix.basename(pair.stem);
      onProgress?.call(
        'กำลังถอดรหัสสคริปต์ $shortName (${i + 1}/${pairs.length})...',
      );
      await Future<void>.delayed(Duration.zero);

      final scriptFile = await decodeCandidatePair(pair, errors: errors);
      if (scriptFile != null && scriptFile.block.nodes.isNotEmpty) {
        assignBlockIds(scriptFile.block);
        loadedFiles.add(scriptFile);
        if (!foundStartLabel && _containsStartLabel(scriptFile.block)) {
          foundStartLabel = true;
        }
      }
    }

    return ScriptLoadResult(
      files: loadedFiles,
      errors: errors,
      totalAssetsCount: assets.length,
      archiveCount: archives.length,
      imageCount: imageIndex.length,
    );
  }

  /// Decodes a single [ScriptCandidatePair] (preferring `.rpyc` and falling
  /// back to `.rpy` if `.rpyc` is absent or yields no executable statements).
  Future<ScriptFile?> decodeCandidatePair(
    ScriptCandidatePair pair, {
    List<String>? errors,
  }) async {
    ScriptFile? scriptFile;

    if (pair.rpyc != null) {
      final src = pair.rpyc!;
      final bytes = await readBytes(src.virtualPath);
      if (bytes != null) {
        try {
          scriptFile = RpycReader.decodeBytes(
            bytes,
            virtualPath: src.virtualPath,
            origin: src.isFromArchive ? 'rpyc (archive)' : 'rpyc',
          );
        } catch (e) {
          errors?.add('${src.virtualPath}: $e');
        }
      }
    }

    if ((scriptFile == null || scriptFile.block.nodes.isEmpty) &&
        pair.rpy != null) {
      final src = pair.rpy!;
      final bytes = await readBytes(src.virtualPath);
      if (bytes != null) {
        try {
          final text = utf8.decode(bytes, allowMalformed: true);
          scriptFile = RpyParser.parseSource(
            text,
            virtualPath: src.virtualPath,
            origin: src.isFromArchive ? 'rpy (archive)' : 'rpy',
          );
        } catch (e) {
          errors?.add('${src.virtualPath}: $e');
        }
      }
    }

    return scriptFile;
  }

  void assignBlockIds(ScriptBlock block) {
    block.id = _nextBlockId++;
    for (final node in block.nodes) {
      if (node is LabelNode) {
        assignBlockIds(node.block);
      } else if (node is InitNode) {
        assignBlockIds(node.block);
      } else if (node is MenuNode) {
        for (final c in node.choices) {
          assignBlockIds(c.block);
        }
      } else if (node is IfNode) {
        for (final b in node.branches) {
          assignBlockIds(b.block);
        }
      } else if (node is WhileNode) {
        assignBlockIds(node.block);
      }
    }
  }

  static bool _containsStartLabel(ScriptBlock block) {
    for (final node in block.nodes) {
      if (node is LabelNode && node.name.toLowerCase() == 'start') {
        return true;
      }
      if (node is InitNode && _containsStartLabel(node.block)) {
        return true;
      }
    }
    return false;
  }
}

class ScriptLoadResult {
  const ScriptLoadResult({
    required this.files,
    required this.errors,
    required this.totalAssetsCount,
    required this.archiveCount,
    required this.imageCount,
  });

  final List<ScriptFile> files;
  final List<String> errors;
  final int totalAssetsCount;
  final int archiveCount;
  final int imageCount;
}
