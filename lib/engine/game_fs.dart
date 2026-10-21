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

  /// In-memory LRU cache of recently loaded asset bytes (such as current
  /// background and character sprites).
  final Map<String, Uint8List> _byteCache = <String, Uint8List>{};

  static const Set<String> _imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
  };

  /// Mounts a Ren'Py project directory (or a path to its `.exe` or `game/`
  /// subdirectory) and indexes all loose files and `.rpa` archives.
  static Future<GameFileSystem?> mount(String inputPath) async {
    Directory baseDir;
    final f = File(inputPath);
    if (await f.exists()) {
      baseDir = f.parent;
    } else {
      baseDir = Directory(inputPath);
    }
    if (!await baseDir.exists()) return null;

    // Locate the `game/` directory even if the user selected `game/` directly
    // or a parent wrapper directory.
    Directory rootDir = baseDir;
    Directory gameDir = Directory(p.join(baseDir.path, 'game'));

    if (!await gameDir.exists()) {
      if (p.basename(baseDir.path).toLowerCase() == 'game') {
        gameDir = baseDir;
        rootDir = baseDir.parent;
      } else {
        // Check one level down in case the zip extracted into a wrapper folder
        try {
          for (final child in baseDir.listSync()) {
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

    if (!await gameDir.exists()) {
      // Allow folders that placed .rpy / .rpyc / .rpa directly in the selected folder
      gameDir = baseDir;
    }

    final assets = <String, AssetSource>{};
    final archives = <RpaArchive>[];
    final rpaFiles = <File>[];

    // 1. Scan loose files in gameDir
    try {
      final entities = gameDir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
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

    // 2. Open all .rpa archives and merge their entries (loose disk files take precedence)
    rpaFiles.sort((a, b) => a.path.compareTo(b.path));
    for (final rpaFile in rpaFiles) {
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

    // 3. Build automatic image lookup index matching Ren'Py's image directory rules
    final imageIndex = <String, String>{};
    for (final entry in assets.entries) {
      final vPath = entry.key;
      final ext = p.extension(vPath);
      if (!_imageExtensions.contains(ext)) continue;

      // Exact relative path without extension (e.g. `images/bg uni` and `bg uni`)
      final noExt = vPath.substring(0, vPath.length - ext.length);
      imageIndex[noExt] = vPath;
      imageIndex[vPath] = vPath;

      final baseName = p.posix.basenameWithoutExtension(vPath).toLowerCase();
      imageIndex.putIfAbsent(baseName, () => vPath);

      // Also index with underscores converted to spaces and vice versa
      final spaceNormalized =
          baseName.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      imageIndex.putIfAbsent(spaceNormalized, () => vPath);

      final underscoreNormalized =
          baseName.replaceAll(RegExp(r'\s+'), '_').trim();
      imageIndex.putIfAbsent(underscoreNormalized, () => vPath);

      // If under `images/<tag>/...`, also index `<tag> <basename>`
      final parts = noExt.split('/');
      if (parts.length >= 3 && parts.first == 'images') {
        final folderTag = parts[1];
        if (!spaceNormalized.startsWith('$folderTag ')) {
          imageIndex.putIfAbsent('$folderTag $spaceNormalized', () => vPath);
        }
      }
    }

    return GameFileSystem._(
      rootPath: rootDir.path,
      gameDirPath: gameDir.path,
      archives: archives,
      assets: assets,
      imageIndex: imageIndex,
    );
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
      // Fallback: match by basename if path prefix differs
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
      if (_byteCache.length >= 24) {
        _byteCache.remove(_byteCache.keys.first);
      }
      _byteCache[norm] = bytes;
    }
    return bytes;
  }

  /// Resolves an image name or filename (such as `['bg', 'uni']`,
  /// `['sylvie', 'green', 'smile']`, or `'gui/main_menu.png'`) to its virtual
  /// path in [assets].
  String? resolveImageVirtualPath(
    List<String> nameParts, {
    Map<String, String>? definedImages,
  }) {
    if (nameParts.isEmpty) return null;
    final joined = nameParts.join(' ').toLowerCase().trim();

    // 1. Check explicit `image ... = "..."` definitions first
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

    // 2. Direct lookup in imageIndex
    if (imageIndex.containsKey(joined)) {
      return imageIndex[joined];
    }

    final underscored = nameParts.join('_').toLowerCase();
    if (imageIndex.containsKey(underscored)) {
      return imageIndex[underscored];
    }

    // 3. Progressive attribute matching (if `sylvie green surprised` isn't
    // found as an exact string, check all tokens in any order after tag)
    final tag = nameParts.first.toLowerCase();
    final attrs =
        nameParts.sublist(1).map((s) => s.toLowerCase()).toSet();

    String? bestMatch;
    int bestScore = 0;

    for (final entry in imageIndex.entries) {
      final tokens = entry.key
          .replaceAll('_', ' ')
          .split(RegExp(r'[\s/]+'))
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.isEmpty) continue;
      if (!tokens.contains(tag)) continue;

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

  /// Discovers and loads all Ren'Py script files (`.rpy` and `.rpyc`) from
  /// both disk and `.rpa` archives.
  Future<ScriptLoadResult> loadAllScripts() async {
    // Group script candidates by their path without extension so we don't load
    // both `script.rpy` and `script.rpyc` twice.
    final candidates = <String, _ScriptPair>{};

    for (final entry in assets.entries) {
      final key = entry.key;
      if (key.startsWith('tl/') && !key.startsWith('tl/none/')) {
        // Ignore non-default translation directories
        continue;
      }
      if (key.startsWith('renpy/') || key.startsWith('cache/')) {
        continue;
      }

      if (key.endsWith('.rpy')) {
        final stem = key.substring(0, key.length - 4);
        candidates.putIfAbsent(stem, () => _ScriptPair()).rpy = entry.value;
      } else if (key.endsWith('.rpyc')) {
        final stem = key.substring(0, key.length - 5);
        candidates.putIfAbsent(stem, () => _ScriptPair()).rpyc = entry.value;
      }
    }

    final stems = candidates.keys.toList()..sort();
    final loadedFiles = <ScriptFile>[];
    final errors = <String>[];

    for (final stem in stems) {
      final pair = candidates[stem]!;
      final baseName = p.posix.basename(stem);

      // Skip pure UI screen/style boilerplate files that never contain story
      // labels or character definitions
      if (baseName == 'screens' || baseName == 'gui') {
        continue;
      }

      ScriptFile? scriptFile;

      // Prefer .rpyc first because it contains Ren'Py's exact compiled AST;
      // fall back to .rpy if .rpyc is absent or fails to decode.
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
            errors.add('${src.virtualPath}: $e');
          }
        }
      }

      if (scriptFile == null && pair.rpy != null) {
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
            errors.add('${src.virtualPath}: $e');
          }
        }
      }

      if (scriptFile != null && scriptFile.block.nodes.isNotEmpty) {
        loadedFiles.add(scriptFile);
      }
    }

    // Assign stable integer IDs to every ScriptBlock across all loaded files
    int nextBlockId = 1;
    void assignIds(ScriptBlock block) {
      block.id = nextBlockId++;
      for (final node in block.nodes) {
        if (node is LabelNode) {
          assignIds(node.block);
        } else if (node is InitNode) {
          assignIds(node.block);
        } else if (node is MenuNode) {
          for (final c in node.choices) {
            assignIds(c.block);
          }
        } else if (node is IfNode) {
          for (final b in node.branches) {
            assignIds(b.block);
          }
        } else if (node is WhileNode) {
          assignIds(node.block);
        }
      }
    }

    for (final f in loadedFiles) {
      assignIds(f.block);
    }

    return ScriptLoadResult(
      files: loadedFiles,
      errors: errors,
      totalAssetsCount: assets.length,
      archiveCount: archives.length,
      imageCount: imageIndex.length,
    );
  }
}

class _ScriptPair {
  AssetSource? rpy;
  AssetSource? rpyc;
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
