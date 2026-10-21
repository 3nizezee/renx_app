import 'dart:typed_data';

import 'game_fs.dart';
import 'mini_python.dart';
import 'script_ast.dart';

enum SpritePosition {
  left,
  center,
  right,
}

class ActiveSprite {
  const ActiveSprite({
    required this.tag,
    required this.attributes,
    required this.virtualPath,
    required this.position,
  });

  final String tag;
  final List<String> attributes;
  final String virtualPath;
  final SpritePosition position;

  ActiveSprite copyWith({
    List<String>? attributes,
    String? virtualPath,
    SpritePosition? position,
  }) {
    return ActiveSprite(
      tag: tag,
      attributes: attributes ?? this.attributes,
      virtualPath: virtualPath ?? this.virtualPath,
      position: position ?? this.position,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tag': tag,
        'attributes': attributes,
        'virtualPath': virtualPath,
        'position': position.name,
      };

  factory ActiveSprite.fromJson(Map<String, dynamic> map) {
    final posName = map['position'] as String? ?? 'center';
    final pos = SpritePosition.values.firstWhere(
      (e) => e.name == posName,
      orElse: () => SpritePosition.center,
    );
    return ActiveSprite(
      tag: map['tag'] as String? ?? '',
      attributes: (map['attributes'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      virtualPath: map['virtualPath'] as String? ?? '',
      position: pos,
    );
  }
}

class ActiveChoice {
  const ActiveChoice({
    required this.index,
    required this.text,
    required this.blockId,
  });

  /// Index inside the original `MenuNode.choices` list.
  final int index;

  /// Interpolated text shown to the player.
  final String text;

  /// Target block ID executed when this choice is selected.
  final int blockId;
}

class DialogueLogEntry {
  const DialogueLogEntry({
    required this.speaker,
    required this.text,
    this.speakerColorHex,
  });

  final String? speaker;
  final String text;
  final String? speakerColorHex;
}

class _ExecFrame {
  _ExecFrame({
    required this.blockId,
    required this.index,
    this.isCallBoundary = false,
  });

  final int blockId;
  int index;
  bool isCallBoundary;

  _ExecFrame clone() => _ExecFrame(
        blockId: blockId,
        index: index,
        isCallBoundary: isCallBoundary,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'blockId': blockId,
        'index': index,
        'isCallBoundary': isCallBoundary,
      };

  factory _ExecFrame.fromJson(Map<String, dynamic> map) => _ExecFrame(
        blockId: (map['blockId'] as num).toInt(),
        index: (map['index'] as num).toInt(),
        isCallBoundary: (map['isCallBoundary'] as bool?) ?? false,
      );
}

class _LabelLocation {
  const _LabelLocation({
    required this.node,
    required this.parentBlockId,
    required this.indexInParent,
  });

  final LabelNode node;
  final int parentBlockId;
  final int indexInParent;
}

class RuntimeSnapshot {
  RuntimeSnapshot({
    required this.stack,
    required this.store,
    required this.seenLabels,
    required this.bgVirtualPath,
    required this.bgSolidHex,
    required this.sprites,
    required this.speakerName,
    required this.speakerColorHex,
    required this.dialogueText,
    required this.activeChoices,
    required this.currentMusic,
    required this.currentSound,
    required this.currentTransition,
    required this.sourceFile,
    required this.sourceLine,
    required this.stepCount,
  });

  final List<_ExecFrame> stack;
  final Map<String, dynamic> store;
  final Set<String> seenLabels;
  final String? bgVirtualPath;
  final String? bgSolidHex;
  final Map<String, ActiveSprite> sprites;
  final String? speakerName;
  final String? speakerColorHex;
  final String dialogueText;
  final List<ActiveChoice> activeChoices;
  final String? currentMusic;
  final String? currentSound;
  final String? currentTransition;
  final String sourceFile;
  final int sourceLine;
  final int stepCount;
}

/// Core state machine that executes compiled `.rpyc` and `.rpy` AST scripts
/// loaded through [GameFileSystem].
class RenpyRuntime {
  RenpyRuntime({
    required this.fs,
    required this.loadResult,
  });

  final GameFileSystem fs;
  final ScriptLoadResult loadResult;
  final MiniPython py = MiniPython();

  final Map<int, ScriptBlock> _blocksById = <int, ScriptBlock>{};
  final Map<String, _LabelLocation> _labels = <String, _LabelLocation>{};
  final Map<String, String> _definedImages = <String, String>{};
  final Map<String, String> _definedSolids = <String, String>{};

  final List<_ExecFrame> _stack = <_ExecFrame>[];
  final List<RuntimeSnapshot> _rollbackStack = <RuntimeSnapshot>[];
  final List<DialogueLogEntry> historyLog = <DialogueLogEntry>[];

  static const int _maxRollbackDepth = 64;
  static const int _maxNonInteractiveSteps = 4000;

  // Observable presentation state
  String? bgVirtualPath;
  Uint8List? bgBytes;
  String? bgSolidHex = '#0A0D14';

  final Map<String, ActiveSprite> sprites = <String, ActiveSprite>{};
  final Map<String, Uint8List> spriteBytes = <String, Uint8List>{};

  String? speakerName;
  String? speakerColorHex;
  String dialogueText = '';
  List<ActiveChoice> activeChoices = const <ActiveChoice>[];

  String? currentMusic;
  String? currentSound;
  String? currentTransition;

  String currentFile = '';
  int currentLine = 0;
  int stepCount = 0;
  bool isFinished = false;

  int get labelCount => _labels.length;
  int get scriptFileCount => loadResult.files.length;
  bool get canRollback => _rollbackStack.isNotEmpty;
  bool get isWaitingForChoice => activeChoices.isNotEmpty;

  /// Extracts `config.name` or `gui.title` if defined by `options.rpyc` / `options.rpy`.
  String? get configuredGameTitle {
    final candidates = <String>[
      'config.name',
      'config.window_title',
      'gui.game_title',
    ];
    for (final key in candidates) {
      final val = py.store[key];
      if (val is String && val.trim().isNotEmpty) {
        return py.formatText(val);
      }
    }
    return null;
  }

  String? get configuredGameVersion {
    final val = py.store['config.version'];
    if (val is String && val.trim().isNotEmpty) {
      return val.trim();
    }
    return null;
  }

  /// Indexes all blocks & labels, executes all `init` / `define` / `default` /
  /// `image` statements, and advances to the first interactive dialogue or menu.
  Future<bool> initialize() async {
    _blocksById.clear();
    _labels.clear();
    _definedImages.clear();
    _definedSolids.clear();
    _stack.clear();
    _rollbackStack.clear();
    historyLog.clear();

    // 1. Register blocks and collect init statements + labels
    final initEntries = <_InitEntry>[];
    int orderCounter = 0;

    for (final file in loadResult.files) {
      _indexBlock(
        file.block,
        initEntries: initEntries,
        priority: 0,
        insideInit: false,
        nextOrder: () => orderCounter++,
      );
    }

    py.knownLabels
      ..clear()
      ..addAll(_labels.keys);

    // 2. Sort init statements by priority, then file order, and execute them
    initEntries.sort((a, b) {
      final cmp = a.priority.compareTo(b.priority);
      return cmp != 0 ? cmp : a.order.compareTo(b.order);
    });

    for (final entry in initEntries) {
      _executeInitStatement(entry.node);
    }

    // 3. Locate entry point (`label start` is standard in Ren'Py)
    _LabelLocation? entryLabel = _labels['start'];
    if (entryLabel == null) {
      for (final e in _labels.entries) {
        if (e.key.toLowerCase() == 'start') {
          entryLabel = e.value;
          break;
        }
      }
    }
    if (entryLabel == null && _labels.isNotEmpty) {
      // Prefer a label from `script.rpyc` / `script.rpy` if present
      for (final loc in _labels.values) {
        final f = loc.node.file.toLowerCase();
        if (f.endsWith('script.rpyc') || f.endsWith('script.rpy')) {
          entryLabel = loc;
          break;
        }
      }
      entryLabel ??= _labels.values.first;
    }

    if (entryLabel != null) {
      _jumpToLabelLocation(entryLabel);
    } else if (loadResult.files.isNotEmpty) {
      // Fallback for label-less scripts: run the first file's top-level block
      final firstFile = loadResult.files.first;
      _stack.add(_ExecFrame(blockId: firstFile.block.id, index: 0));
    } else {
      isFinished = true;
      return false;
    }

    isFinished = false;
    await _advanceUntilInteractive(recordSnapshotBeforeAdvance: false);
    return true;
  }

  void _indexBlock(
    ScriptBlock block, {
    required List<_InitEntry> initEntries,
    required int priority,
    required bool insideInit,
    required int Function() nextOrder,
  }) {
    _blocksById[block.id] = block;

    for (int i = 0; i < block.nodes.length; i++) {
      final node = block.nodes[i];

      if (node is InitNode) {
        _indexBlock(
          node.block,
          initEntries: initEntries,
          priority: node.priority,
          insideInit: true,
          nextOrder: nextOrder,
        );
      } else if (node is LabelNode) {
        _labels.putIfAbsent(
          node.name,
          () => _LabelLocation(
            node: node,
            parentBlockId: block.id,
            indexInParent: i,
          ),
        );
        _indexBlock(
          node.block,
          initEntries: initEntries,
          priority: priority,
          insideInit: false,
          nextOrder: nextOrder,
        );
      } else if (node is MenuNode) {
        for (final choice in node.choices) {
          _indexBlock(
            choice.block,
            initEntries: initEntries,
            priority: priority,
            insideInit: false,
            nextOrder: nextOrder,
          );
        }
      } else if (node is IfNode) {
        for (final branch in node.branches) {
          _indexBlock(
            branch.block,
            initEntries: initEntries,
            priority: priority,
            insideInit: false,
            nextOrder: nextOrder,
          );
        }
      } else if (node is WhileNode) {
        _indexBlock(
          node.block,
          initEntries: initEntries,
          priority: priority,
          insideInit: false,
          nextOrder: nextOrder,
        );
      } else if (node is DefineNode ||
          node is DefaultNode ||
          node is ImageNode ||
          (insideInit && node is PythonNode)) {
        initEntries.add(
          _InitEntry(
            priority: priority,
            order: nextOrder(),
            node: node,
          ),
        );
      }
    }
  }

  void _executeInitStatement(ScriptNode node) {
    if (node is DefineNode) {
      final val = py.evaluate(node.expression);
      py.applyAssignment(node.name, node.operator, val);
    } else if (node is DefaultNode) {
      final clean = node.name.startsWith('store.')
          ? node.name.substring(6)
          : node.name;
      if (!py.store.containsKey(clean)) {
        py.store[clean] = py.evaluate(node.expression);
      }
    } else if (node is ImageNode) {
      final key = node.name.join(' ').toLowerCase().trim();
      if (node.expression != null && node.expression!.trim().isNotEmpty) {
        final evaluated = py.evaluate(node.expression!);
        if (evaluated is SolidDisplayable) {
          _definedSolids[key] = evaluated.colorHex;
        } else if (evaluated is String && evaluated.trim().isNotEmpty) {
          _definedImages[key] = evaluated.trim();
        }
      }
    } else if (node is PythonNode) {
      py.execute(node.source);
    }
  }

  /// Advances the script past the current dialogue line. If a choice menu is
  /// currently active, does nothing until [choose] is called.
  Future<void> stepForward() async {
    if (isFinished || isWaitingForChoice) return;
    await _advanceUntilInteractive(recordSnapshotBeforeAdvance: true);
  }

  /// Selects a choice from [activeChoices] by its index in [activeChoices].
  Future<void> choose(int visibleChoiceIndex) async {
    if (visibleChoiceIndex < 0 || visibleChoiceIndex >= activeChoices.length) {
      return;
    }
    _pushRollbackSnapshot();

    final chosen = activeChoices[visibleChoiceIndex];
    activeChoices = const <ActiveChoice>[];

    final targetBlock = _blocksById[chosen.blockId];
    if (targetBlock != null) {
      _stack.add(_ExecFrame(blockId: targetBlock.id, index: 0));
    }
    await _advanceUntilInteractive(recordSnapshotBeforeAdvance: false);
  }

  /// Jumps directly to a named label (used by the developer/chapter jump menu).
  Future<bool> jumpToLabel(String labelName) async {
    final loc = _findLabel(labelName);
    if (loc == null) return false;
    _pushRollbackSnapshot();
    activeChoices = const <ActiveChoice>[];
    _stack.clear();
    _jumpToLabelLocation(loc);
    isFinished = false;
    await _advanceUntilInteractive(recordSnapshotBeforeAdvance: false);
    return true;
  }

  /// Restores the most recent rollback snapshot.
  Future<bool> rollback() async {
    if (_rollbackStack.isEmpty) return false;
    final snap = _rollbackStack.removeLast();
    await _restoreSnapshot(snap);
    if (historyLog.isNotEmpty) {
      historyLog.removeLast();
    }
    return true;
  }

  void _pushRollbackSnapshot() {
    if (_rollbackStack.length >= _maxRollbackDepth) {
      _rollbackStack.removeAt(0);
    }
    _rollbackStack.add(
      RuntimeSnapshot(
        stack: _stack.map((f) => f.clone()).toList(),
        store: py.snapshotStore(),
        seenLabels: Set<String>.from(py.seenLabels),
        bgVirtualPath: bgVirtualPath,
        bgSolidHex: bgSolidHex,
        sprites: Map<String, ActiveSprite>.from(sprites),
        speakerName: speakerName,
        speakerColorHex: speakerColorHex,
        dialogueText: dialogueText,
        activeChoices: List<ActiveChoice>.from(activeChoices),
        currentMusic: currentMusic,
        currentSound: currentSound,
        currentTransition: currentTransition,
        sourceFile: currentFile,
        sourceLine: currentLine,
        stepCount: stepCount,
      ),
    );
  }

  Future<void> _restoreSnapshot(RuntimeSnapshot snap) async {
    _stack
      ..clear()
      ..addAll(snap.stack.map((f) => f.clone()));
    py.restoreStore(snap.store);
    py.seenLabels
      ..clear()
      ..addAll(snap.seenLabels);

    bgVirtualPath = snap.bgVirtualPath;
    bgSolidHex = snap.bgSolidHex;
    bgBytes = bgVirtualPath != null ? await fs.readBytes(bgVirtualPath!) : null;

    sprites
      ..clear()
      ..addAll(snap.sprites);
    await _reloadSpriteBytes();

    speakerName = snap.speakerName;
    speakerColorHex = snap.speakerColorHex;
    dialogueText = snap.dialogueText;
    activeChoices = List<ActiveChoice>.from(snap.activeChoices);
    currentMusic = snap.currentMusic;
    currentSound = snap.currentSound;
    currentTransition = snap.currentTransition;
    currentFile = snap.sourceFile;
    currentLine = snap.sourceLine;
    stepCount = snap.stepCount;
    isFinished = false;
  }

  Future<void> _advanceUntilInteractive({
    required bool recordSnapshotBeforeAdvance,
  }) async {
    if (recordSnapshotBeforeAdvance &&
        (dialogueText.isNotEmpty || activeChoices.isNotEmpty)) {
      _pushRollbackSnapshot();
    }

    currentTransition = null;
    int safetyCounter = 0;

    while (_stack.isNotEmpty && safetyCounter < _maxNonInteractiveSteps) {
      safetyCounter++;
      final frame = _stack.last;
      final block = _blocksById[frame.blockId];

      if (block == null || frame.index >= block.nodes.length) {
        _stack.removeLast();
        continue;
      }

      final node = block.nodes[frame.index];
      frame.index++;

      currentFile = node.file;
      currentLine = node.line;

      if (node is SayNode) {
        await _applySayNode(node);
        if (node.interact) {
          stepCount++;
          return;
        }
        continue;
      }

      if (node is MenuNode) {
        final paused = _applyMenuNode(node);
        if (paused) {
          stepCount++;
          return;
        }
        continue;
      }

      if (node is SceneNode) {
        await _applySceneNode(node);
        continue;
      }

      if (node is ShowNode) {
        await _applyShowNode(node);
        continue;
      }

      if (node is HideNode) {
        _applyHideNode(node);
        continue;
      }

      if (node is WithNode) {
        currentTransition = node.transition;
        continue;
      }

      if (node is JumpNode) {
        final targetName = node.isExpression
            ? (py.evaluate(node.target)?.toString() ?? node.target)
            : node.target;
        final loc = _findLabel(targetName);
        if (loc != null) {
          _popToCallBoundary();
          _jumpToLabelLocation(loc);
        }
        continue;
      }

      if (node is CallNode) {
        final targetName = node.isExpression
            ? (py.evaluate(node.target)?.toString() ?? node.target)
            : node.target;
        final loc = _findLabel(targetName);
        if (loc != null) {
          if (_stack.isNotEmpty) {
            _stack.last.isCallBoundary = true;
          }
          _jumpToLabelLocation(loc);
        }
        continue;
      }

      if (node is ReturnNode) {
        _popToCallBoundary();
        if (_stack.isNotEmpty && _stack.last.isCallBoundary) {
          _stack.last.isCallBoundary = false;
        } else {
          _stack.clear();
          isFinished = true;
          return;
        }
        continue;
      }

      if (node is LabelNode) {
        py.seenLabels.add(node.name);
        _stack.add(_ExecFrame(blockId: node.block.id, index: 0));
        continue;
      }

      if (node is IfNode) {
        for (final branch in node.branches) {
          final cond = branch.condition;
          final shouldTake =
              cond == null || cond.trim().isEmpty || py.evalBool(cond);
          if (shouldTake) {
            _stack.add(_ExecFrame(blockId: branch.block.id, index: 0));
            break;
          }
        }
        continue;
      }

      if (node is WhileNode) {
        if (py.evalBool(node.condition)) {
          // Re-run this WhileNode after its body completes
          frame.index--;
          _stack.add(_ExecFrame(blockId: node.block.id, index: 0));
        }
        continue;
      }

      if (node is PythonNode) {
        py.pendingJump = null;
        py.execute(node.source);
        if (py.pendingJump != null) {
          final loc = _findLabel(py.pendingJump!);
          py.pendingJump = null;
          if (loc != null) {
            _popToCallBoundary();
            _jumpToLabelLocation(loc);
          }
        }
        continue;
      }

      if (node is DefineNode || node is DefaultNode || node is ImageNode) {
        _executeInitStatement(node);
        continue;
      }

      if (node is PlayNode) {
        final resolved = py.evaluate(node.fileExpression)?.toString() ??
            node.fileExpression.replaceAll('"', '').replaceAll("'", '');
        if (node.channel == 'music') {
          currentMusic = resolved;
        } else {
          currentSound = resolved;
        }
        continue;
      }

      if (node is StopNode) {
        if (node.channel == 'music') {
          currentMusic = null;
        } else {
          currentSound = null;
        }
        continue;
      }
    }

    if (_stack.isEmpty) {
      isFinished = true;
    }
  }

  Future<void> _applySayNode(SayNode node) async {
    String? resolvedName;
    String? resolvedColor;
    String prefix = '';
    String suffix = '';
    String? charImageTag;

    if (node.who != null && node.who!.trim().isNotEmpty) {
      final rawWho = node.who!.trim();
      final val = py.evaluate(rawWho);
      if (val is RenpyCharacter) {
        if (val.isDynamic && val.name != null) {
          resolvedName = py.evaluate(val.name!)?.toString() ?? val.name;
        } else {
          resolvedName = val.name;
        }
        resolvedColor = val.colorHex;
        prefix = val.whatPrefix;
        suffix = val.whatSuffix;
        charImageTag = val.imageTag;
      } else if (val != null) {
        resolvedName = val.toString();
      } else {
        resolvedName = rawWho.replaceAll('"', '').replaceAll("'", '');
      }
    }

    // Update character sprite attributes if the say statement specifies inline
    // attributes (e.g. `s green smile "Hello!"`)
    final inlineAttrs = <String>[
      ...node.attributes,
      ...node.temporaryAttributes,
    ];
    if (inlineAttrs.isNotEmpty) {
      final tagCandidate =
          (charImageTag ?? node.who ?? '').trim().toLowerCase();
      if (tagCandidate.isNotEmpty && sprites.containsKey(tagCandidate)) {
        final existing = sprites[tagCandidate]!;
        final spec = ImageSpec(
          name: <String>[tagCandidate, ...inlineAttrs],
          tag: tagCandidate,
        );
        final vPath = _resolveSpecVirtualPath(
          spec,
          previousAttributes: existing.attributes,
        );
        if (vPath != null) {
          sprites[tagCandidate] = existing.copyWith(
            attributes: inlineAttrs,
            virtualPath: vPath,
          );
          final bytes = await fs.readBytes(vPath);
          if (bytes != null) {
            spriteBytes[tagCandidate] = bytes;
          }
        }
      }
    }

    speakerName =
        resolvedName != null ? py.formatText(resolvedName) : null;
    speakerColorHex = resolvedColor;
    dialogueText = py.formatText('$prefix${node.what}$suffix');
    if (node.transition != null) {
      currentTransition = node.transition;
    }

    if (node.interact && dialogueText.isNotEmpty) {
      historyLog.add(
        DialogueLogEntry(
          speaker: speakerName,
          text: dialogueText,
          speakerColorHex: speakerColorHex,
        ),
      );
      if (historyLog.length > 200) {
        historyLog.removeAt(0);
      }
    }
  }

  bool _applyMenuNode(MenuNode node) {
    if (node.caption != null && node.caption!.trim().isNotEmpty) {
      speakerName = null;
      speakerColorHex = null;
      dialogueText = py.formatText(node.caption!);
    }

    final visible = <ActiveChoice>[];
    for (int i = 0; i < node.choices.length; i++) {
      final c = node.choices[i];
      if (c.condition != null &&
          c.condition!.trim().isNotEmpty &&
          c.condition!.trim() != 'True') {
        if (!py.evalBool(c.condition!)) continue;
      }
      visible.add(
        ActiveChoice(
          index: i,
          text: py.formatText(c.text),
          blockId: c.block.id,
        ),
      );
    }

    if (visible.isEmpty) {
      return false;
    }

    activeChoices = visible;
    return true;
  }

  Future<void> _applySceneNode(SceneNode node) async {
    sprites.clear();
    spriteBytes.clear();

    if (node.transition != null) {
      currentTransition = node.transition;
    }

    final spec = node.image;
    if (spec == null) {
      bgVirtualPath = null;
      bgBytes = null;
      bgSolidHex = '#000000';
      return;
    }

    final joinedKey = spec.name.join(' ').toLowerCase().trim();
    if (_definedSolids.containsKey(joinedKey)) {
      bgVirtualPath = null;
      bgBytes = null;
      bgSolidHex = _definedSolids[joinedKey];
      return;
    }

    final vPath = _resolveSpecVirtualPath(spec);
    if (vPath != null) {
      bgVirtualPath = vPath;
      bgBytes = await fs.readBytes(vPath);
      bgSolidHex = '#0A0D14';
      return;
    }

    // Standard named solid colors (`scene black`, `scene white`)
    bgVirtualPath = null;
    bgBytes = null;
    if (joinedKey.contains('white')) {
      bgSolidHex = '#F5F7FA';
    } else if (joinedKey.contains('red')) {
      bgSolidHex = '#3B0A0A';
    } else if (joinedKey.contains('blue')) {
      bgSolidHex = '#0A192F';
    } else {
      bgSolidHex = '#000000';
    }
  }

  Future<void> _applyShowNode(ShowNode node) async {
    final spec = node.image;
    final tag = spec.effectiveTag.toLowerCase();
    if (tag.isEmpty) return;

    if (node.transition != null) {
      currentTransition = node.transition;
    }

    // If the script uses `show bg ...`, treat it as a background layer update
    if (tag == 'bg' || tag == 'background') {
      final vPath = _resolveSpecVirtualPath(spec);
      if (vPath != null) {
        bgVirtualPath = vPath;
        bgBytes = await fs.readBytes(vPath);
      }
      return;
    }

    final existing = sprites[tag];
    final position = _resolvePosition(spec.atList, existing?.position);
    final vPath = _resolveSpecVirtualPath(
      spec,
      previousAttributes: existing?.attributes,
    );

    if (vPath != null) {
      final newAttrs = spec.name.length > 1
          ? spec.name.sublist(1)
          : (existing?.attributes ?? const <String>[]);
      sprites[tag] = ActiveSprite(
        tag: tag,
        attributes: newAttrs,
        virtualPath: vPath,
        position: position,
      );
      final bytes = await fs.readBytes(vPath);
      if (bytes != null) {
        spriteBytes[tag] = bytes;
      }
    }
  }

  void _applyHideNode(HideNode node) {
    final tag = node.image.effectiveTag.toLowerCase();
    sprites.remove(tag);
    spriteBytes.remove(tag);
    if (node.transition != null) {
      currentTransition = node.transition;
    }
  }

  SpritePosition _resolvePosition(
    List<String> atList,
    SpritePosition? previous,
  ) {
    for (final raw in atList) {
      final t = raw.toLowerCase();
      if (t.contains('left')) return SpritePosition.left;
      if (t.contains('right')) return SpritePosition.right;
      if (t.contains('center') || t.contains('truecenter')) {
        return SpritePosition.center;
      }
    }
    return previous ?? SpritePosition.center;
  }

  String? _resolveSpecVirtualPath(
    ImageSpec spec, {
    List<String>? previousAttributes,
  }) {
    if (spec.expression != null && spec.expression!.trim().isNotEmpty) {
      final eval = py.evaluate(spec.expression!);
      if (eval is String && eval.trim().isNotEmpty) {
        final direct = fs.resolveImageVirtualPath(
          <String>[eval.trim()],
          definedImages: _definedImages,
        );
        if (direct != null) return direct;
      }
    }

    if (spec.name.isEmpty) return null;

    final joined = spec.name.join(' ').toLowerCase().trim();
    if (_definedImages.containsKey(joined) || fs.imageIndex.containsKey(joined)) {
      return fs.resolveImageVirtualPath(
        spec.name,
        definedImages: _definedImages,
      );
    }

    // If previous attributes exist (e.g. `sylvie green normal` was showing
    // and the script says `show sylvie smile`), try combining sticky attributes
    if (previousAttributes != null &&
        previousAttributes.isNotEmpty &&
        spec.name.length == 2) {
      final combined = <String>[
        spec.name.first,
        ...previousAttributes.where((a) => a != spec.name.last),
        spec.name.last,
      ];
      final combinedKey = combined.join(' ').toLowerCase().trim();
      if (_definedImages.containsKey(combinedKey) ||
          fs.imageIndex.containsKey(combinedKey)) {
        return fs.resolveImageVirtualPath(
          combined,
          definedImages: _definedImages,
        );
      }
    }

    return fs.resolveImageVirtualPath(
      spec.name,
      definedImages: _definedImages,
    );
  }

  _LabelLocation? _findLabel(String name) {
    final clean = name.trim();
    if (_labels.containsKey(clean)) return _labels[clean];
    final lower = clean.toLowerCase();
    for (final entry in _labels.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  void _popToCallBoundary() {
    while (_stack.isNotEmpty && !_stack.last.isCallBoundary) {
      _stack.removeLast();
    }
  }

  void _jumpToLabelLocation(_LabelLocation loc) {
    py.seenLabels.add(loc.node.name);
    // Push the parent block at the statement following the label so execution
    // falls through naturally if the label block does not end with `return`.
    _stack.add(
      _ExecFrame(
        blockId: loc.parentBlockId,
        index: loc.indexInParent + 1,
      ),
    );
    _stack.add(
      _ExecFrame(
        blockId: loc.node.block.id,
        index: 0,
      ),
    );
  }

  Future<void> _reloadSpriteBytes() async {
    spriteBytes.clear();
    for (final entry in sprites.entries) {
      final bytes = await fs.readBytes(entry.value.virtualPath);
      if (bytes != null) {
        spriteBytes[entry.key] = bytes;
      }
    }
  }

  List<String> get sortedLabelNames {
    final names = _labels.keys.toList()..sort();
    return names;
  }

  /// Serializes the complete runtime state to a JSON-compatible map for save slots.
  Map<String, dynamic> exportSaveState() {
    final serializableStore = <String, dynamic>{};
    for (final entry in py.store.entries) {
      final v = entry.value;
      if (v == null ||
          v is num ||
          v is bool ||
          v is String ||
          v is List ||
          v is Map) {
        serializableStore[entry.key] = v;
      } else if (v is RenpyCharacter) {
        serializableStore[entry.key] = v.toJson();
      }
    }

    return <String, dynamic>{
      'version': 2,
      'timestamp': DateTime.now().toIso8601String(),
      'stack': _stack.map((f) => f.toJson()).toList(),
      'store': serializableStore,
      'seenLabels': py.seenLabels.toList(),
      'bgVirtualPath': bgVirtualPath,
      'bgSolidHex': bgSolidHex,
      'sprites': sprites.map((k, v) => MapEntry(k, v.toJson())),
      'speakerName': speakerName,
      'speakerColorHex': speakerColorHex,
      'dialogueText': dialogueText,
      'activeChoices': activeChoices
          .map((c) => <String, dynamic>{
                'index': c.index,
                'text': c.text,
                'blockId': c.blockId,
              })
          .toList(),
      'currentMusic': currentMusic,
      'currentSound': currentSound,
      'currentFile': currentFile,
      'currentLine': currentLine,
      'stepCount': stepCount,
    };
  }

  /// Restores runtime state from a map produced by [exportSaveState].
  Future<bool> importSaveState(Map<String, dynamic> data) async {
    try {
      final rawStack = data['stack'] as List<dynamic>? ?? const <dynamic>[];
      _stack
        ..clear()
        ..addAll(
          rawStack.map(
            (e) => _ExecFrame.fromJson(Map<String, dynamic>.from(e as Map)),
          ),
        );

      final rawStore =
          Map<String, dynamic>.from(data['store'] as Map? ?? const <String, dynamic>{});
      for (final entry in rawStore.entries) {
        final val = entry.value;
        if (val is Map && val['__type__'] == 'RenpyCharacter') {
          py.store[entry.key] =
              RenpyCharacter.fromJson(Map<String, dynamic>.from(val));
        } else {
          py.store[entry.key] = val;
        }
      }

      final seen = data['seenLabels'] as List<dynamic>? ?? const <dynamic>[];
      py.seenLabels
        ..clear()
        ..addAll(seen.map((e) => e.toString()));

      bgVirtualPath = data['bgVirtualPath'] as String?;
      bgSolidHex = data['bgSolidHex'] as String? ?? '#0A0D14';
      bgBytes =
          bgVirtualPath != null ? await fs.readBytes(bgVirtualPath!) : null;

      sprites.clear();
      final rawSprites = data['sprites'] as Map? ?? const <String, dynamic>{};
      for (final entry in rawSprites.entries) {
        sprites[entry.key.toString()] = ActiveSprite.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      await _reloadSpriteBytes();

      speakerName = data['speakerName'] as String?;
      speakerColorHex = data['speakerColorHex'] as String?;
      dialogueText = data['dialogueText'] as String? ?? '';

      final rawChoices =
          data['activeChoices'] as List<dynamic>? ?? const <dynamic>[];
      activeChoices = rawChoices.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return ActiveChoice(
          index: (m['index'] as num).toInt(),
          text: m['text'] as String? ?? '',
          blockId: (m['blockId'] as num).toInt(),
        );
      }).toList();

      currentMusic = data['currentMusic'] as String?;
      currentSound = data['currentSound'] as String?;
      currentFile = data['currentFile'] as String? ?? '';
      currentLine = (data['currentLine'] as num?)?.toInt() ?? 0;
      stepCount = (data['stepCount'] as num?)?.toInt() ?? 0;
      isFinished = false;
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _InitEntry {
  const _InitEntry({
    required this.priority,
    required this.order,
    required this.node,
  });

  final int priority;
  final int order;
  final ScriptNode node;
}
