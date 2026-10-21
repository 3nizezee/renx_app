import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pickle_decoder.dart';
import 'script_ast.dart';

/// Decodes compiled Ren'Py `.rpyc` files (both `RENPY RPC2` container format
/// and legacy raw zlib format) into the unified [ScriptBlock] AST.
class RpycReader {
  static ScriptFile? decodeBytes(
    Uint8List bytes, {
    required String virtualPath,
    String origin = 'rpyc',
  }) {
    final pickleBytes = extractAstPickle(bytes);
    if (pickleBytes == null) return null;

    final root = PickleDecoder(pickleBytes).decode();
    if (root is! List || root.length < 2) return null;

    final rawStmts = root[1];
    if (rawStmts is! List) return null;

    final nodes = _convertNodeList(rawStmts, virtualPath);
    return ScriptFile(
      path: virtualPath,
      block: ScriptBlock(nodes),
      origin: origin,
    );
  }

  /// Decompresses the AST pickle payload from a `.rpyc` binary buffer.
  static Uint8List? extractAstPickle(Uint8List bytes) {
    if (bytes.length < 16) return null;

    // Check for "RENPY RPC2" header
    final magic = latin1.decode(bytes.sublist(0, 10), allowInvalid: true);
    if (magic == 'RENPY RPC2') {
      final view = ByteData.sublistView(bytes);
      int pos = 10;
      Uint8List? slot1Data;
      Uint8List? slot2Data;

      while (pos + 12 <= bytes.length) {
        final slot = view.getUint32(pos, Endian.little);
        final start = view.getUint32(pos + 4, Endian.little);
        final length = view.getUint32(pos + 8, Endian.little);
        pos += 12;

        if (slot == 0) break;
        if (start + length > bytes.length || length == 0) continue;

        final slice = Uint8List.sublistView(bytes, start, start + length);
        if (slot == 1) {
          slot1Data = slice;
        } else if (slot == 2) {
          slot2Data = slice;
        }
      }

      final targetSlice = slot1Data ?? slot2Data;
      if (targetSlice == null) return null;
      try {
        return Uint8List.fromList(zlib.decode(targetSlice));
      } catch (_) {
        return null;
      }
    }

    // Legacy .rpyc: entire file is zlib-compressed pickle
    try {
      return Uint8List.fromList(zlib.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  static List<ScriptNode> _convertNodeList(
      List<dynamic> rawList, String defaultFile) {
    final result = <ScriptNode>[];
    for (final item in rawList) {
      if (item is PyObject) {
        final converted = _convertNode(item, defaultFile);
        if (converted != null) {
          result.addAll(converted);
        }
      }
    }
    return result;
  }

  static List<ScriptNode>? _convertNode(PyObject obj, String defaultFile) {
    final fields = obj.fields;
    final file = _exprString(fields['filename']) ?? defaultFile;
    final line = _intVal(fields['linenumber'], 1);
    final shortClass = obj.klass.split('.').last;

    switch (shortClass) {
      case 'Label':
        final name = _exprString(fields['name']) ?? '';
        final rawBlock = fields['block'];
        final children = rawBlock is List
            ? _convertNodeList(rawBlock, file)
            : <ScriptNode>[];
        return <ScriptNode>[
          LabelNode(
            file,
            line,
            name: name,
            block: ScriptBlock(children),
          ),
        ];

      case 'Say':
      case 'TranslateSay':
        final lang = _exprString(fields['language']);
        if (lang != null && lang.isNotEmpty && lang != 'None') {
          return const <ScriptNode>[];
        }
        final who = _exprString(fields['who']);
        final what = _exprString(fields['what']) ?? '';
        final withExpr = _exprString(fields['with_']);
        final rawInteract = fields['interact'];
        final interact = rawInteract is bool
            ? rawInteract
            : (rawInteract == 0 ? false : true);
        final attrs = _stringList(fields['attributes']);
        final tempAttrs = _stringList(fields['temporary_attributes']);
        return <ScriptNode>[
          SayNode(
            file,
            line,
            who: (who != null && who.trim().isNotEmpty) ? who.trim() : null,
            what: what,
            attributes: attrs,
            temporaryAttributes: tempAttrs,
            interact: interact,
            transition: withExpr,
          ),
        ];

      case 'Menu':
        final rawItems = fields['items'];
        final choices = <MenuChoice>[];
        String? caption;

        // Check statement_start if it holds a pre-menu Say caption
        final stmtStart = fields['statement_start'];
        if (stmtStart is PyObject &&
            stmtStart.klass.endsWith('.Say') &&
            !identical(stmtStart, obj)) {
          final startFields = stmtStart.fields;
          if (startFields['interact'] == false) {
            caption = _exprString(startFields['what']);
          }
        }

        if (rawItems is List) {
          for (final entry in rawItems) {
            if (entry is List && entry.length >= 3) {
              final label = _exprString(entry[0]) ?? '';
              final condRaw = _exprString(entry[1]);
              final itemBlock = entry[2];
              if (itemBlock is List) {
                final cond = (condRaw == null ||
                        condRaw == 'True' ||
                        condRaw.trim().isEmpty)
                    ? null
                    : condRaw.trim();
                choices.add(
                  MenuChoice(
                    text: label,
                    condition: cond,
                    block: ScriptBlock(_convertNodeList(itemBlock, file)),
                  ),
                );
              } else {
                caption ??= label;
              }
            }
          }
        }
        final setVar = _exprString(fields['set']);
        return <ScriptNode>[
          MenuNode(
            file,
            line,
            choices: choices,
            caption: caption,
            setVariable: setVar,
          ),
        ];

      case 'Jump':
        final target = _exprString(fields['target']) ?? '';
        final isExpr = fields['expression'] == true;
        return <ScriptNode>[
          JumpNode(file, line, target: target, isExpression: isExpr),
        ];

      case 'Call':
        final target = _exprString(fields['label']) ?? '';
        final isExpr = fields['expression'] == true;
        return <ScriptNode>[
          CallNode(file, line, target: target, isExpression: isExpr),
        ];

      case 'Return':
        return <ScriptNode>[ReturnNode(file, line)];

      case 'If':
        final rawEntries = fields['entries'];
        final branches = <IfBranch>[];
        if (rawEntries is List) {
          for (final entry in rawEntries) {
            if (entry is List && entry.length >= 2) {
              final condStr = _exprString(entry[0])?.trim();
              final branchBlock = entry[1] is List
                  ? _convertNodeList(entry[1] as List, file)
                  : <ScriptNode>[];
              branches.add(
                IfBranch(
                  condition: (condStr == null ||
                          condStr.isEmpty ||
                          condStr == 'True')
                      ? null
                      : condStr,
                  block: ScriptBlock(branchBlock),
                ),
              );
            }
          }
        }
        return <ScriptNode>[IfNode(file, line, branches: branches)];

      case 'While':
        final cond = _exprString(fields['condition']) ?? 'False';
        final rawBlock = fields['block'];
        final children = rawBlock is List
            ? _convertNodeList(rawBlock, file)
            : <ScriptNode>[];
        return <ScriptNode>[
          WhileNode(file, line, condition: cond, block: ScriptBlock(children)),
        ];

      case 'Scene':
        final spec = _parseImspec(fields['imspec']);
        return <ScriptNode>[
          SceneNode(file, line, image: spec),
        ];

      case 'Show':
        final spec = _parseImspec(fields['imspec']);
        if (spec == null) return const <ScriptNode>[];
        return <ScriptNode>[
          ShowNode(file, line, image: spec),
        ];

      case 'Hide':
        final spec = _parseImspec(fields['imspec']);
        if (spec == null) return const <ScriptNode>[];
        return <ScriptNode>[
          HideNode(file, line, image: spec),
        ];

      case 'With':
        final expr = _exprString(fields['expr']) ?? '';
        if (expr.isEmpty || expr == 'None') return const <ScriptNode>[];
        return <ScriptNode>[
          WithNode(file, line, transition: expr),
        ];

      case 'Python':
      case 'EarlyPython':
        final src = _pyCodeSource(fields['code']);
        if (src == null || src.trim().isEmpty) return const <ScriptNode>[];
        return <ScriptNode>[
          PythonNode(file, line, source: src),
        ];

      case 'Define':
        final varname = _exprString(fields['varname']) ?? '';
        final store = _exprString(fields['store']) ?? 'store';
        final op = _exprString(fields['operator']) ?? '=';
        final expr = _pyCodeSource(fields['code']) ?? 'None';
        if (varname.isEmpty) return const <ScriptNode>[];
        final fullName = _qualifyStoreName(store, varname);
        return <ScriptNode>[
          DefineNode(file, line, name: fullName, expression: expr, operator: op),
        ];

      case 'Default':
        final varname = _exprString(fields['varname']) ?? '';
        final store = _exprString(fields['store']) ?? 'store';
        final expr = _pyCodeSource(fields['code']) ?? 'None';
        if (varname.isEmpty) return const <ScriptNode>[];
        final fullName = _qualifyStoreName(store, varname);
        return <ScriptNode>[
          DefaultNode(file, line, name: fullName, expression: expr),
        ];

      case 'Image':
        final imgName = _stringList(fields['imgname']);
        var expr = _pyCodeSource(fields['code']);
        expr ??= _extractAtlDisplayable(fields['atl']);
        if (imgName.isEmpty) return const <ScriptNode>[];
        return <ScriptNode>[
          ImageNode(file, line, name: imgName, expression: expr),
        ];

      case 'Init':
        final priority = _intVal(fields['priority'], 0);
        final rawBlock = fields['block'];
        final children = rawBlock is List
            ? _convertNodeList(rawBlock, file)
            : <ScriptNode>[];
        return <ScriptNode>[
          InitNode(file, line,
              priority: priority, block: ScriptBlock(children)),
        ];

      case 'UserStatement':
        final rawLine = _exprString(fields['line'])?.trim() ?? '';
        if (rawLine.isEmpty) return const <ScriptNode>[];
        return _parseUserStatement(file, line, rawLine);

      case 'Translate':
      case 'TranslateBlock':
        // Skip non-default language translations so they don't overwrite the
        // main script labels; default (None) translations can still execute.
        final lang = _exprString(fields['language']);
        if (lang != null && lang.isNotEmpty && lang != 'None') {
          return const <ScriptNode>[];
        }
        final rawBlock = fields['block'];
        if (rawBlock is List) {
          return _convertNodeList(rawBlock, file);
        }
        return const <ScriptNode>[];

      case 'Pass':
      case 'EndTranslate':
      case 'TranslateString':
      case 'TranslatePython':
      case 'TranslateEarlyBlock':
      case 'Style':
      case 'Transform':
      case 'Screen':
      case 'Testcase':
      case 'Camera':
      case 'ShowLayer':
        return const <ScriptNode>[];

      default:
        return <ScriptNode>[
          UnsupportedNode(file, line, description: shortClass),
        ];
    }
  }

  static List<ScriptNode> _parseUserStatement(
      String file, int line, String rawLine) {
    final playMatch = RegExp(
      r'^(play|queue)\s+(music|sound|voice|audio)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawLine);
    if (playMatch != null) {
      final verb = playMatch.group(1)!.toLowerCase();
      final channel = playMatch.group(2)!.toLowerCase();
      var rest = playMatch.group(3)!.trim();
      bool? loop;
      if (RegExp(r'\bnoloop\b', caseSensitive: false).hasMatch(rest)) {
        loop = false;
      } else if (RegExp(r'\bloop\b', caseSensitive: false).hasMatch(rest)) {
        loop = true;
      }
      // Strip trailing clauses like fadein, fadeout, volume, loop, noloop
      rest = rest
          .replaceAll(
              RegExp(
                  r'\s+(fadein|fadeout|volume|tight|if_changed)\s+[0-9\.]+.*$',
                  caseSensitive: false),
              '')
          .replaceAll(
              RegExp(r'\s+(loop|noloop|tight)\b.*$', caseSensitive: false), '')
          .trim();
      return <ScriptNode>[
        PlayNode(
          file,
          line,
          channel: channel,
          fileExpression: rest,
          loop: loop,
          queue: verb == 'queue',
        ),
      ];
    }

    final stopMatch = RegExp(
      r'^stop\s+(music|sound|voice|audio)\b',
      caseSensitive: false,
    ).firstMatch(rawLine);
    if (stopMatch != null) {
      return <ScriptNode>[
        StopNode(file, line, channel: stopMatch.group(1)!.toLowerCase()),
      ];
    }

    final voiceMatch = RegExp(
      r'^voice\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawLine);
    if (voiceMatch != null) {
      return <ScriptNode>[
        PlayNode(
          file,
          line,
          channel: 'voice',
          fileExpression: voiceMatch.group(1)!.trim(),
          loop: false,
        ),
      ];
    }

    final pauseMatch = RegExp(
      r'^pause(?:\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(rawLine);
    if (pauseMatch != null) {
      return <ScriptNode>[
        PauseNode(file, line, duration: pauseMatch.group(1)?.trim()),
      ];
    }

    return const <ScriptNode>[];
  }

  static ImageSpec? _parseImspec(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final nameParts = _stringList(raw[0]);
    final expr = raw.length > 1 ? _exprString(raw[1]) : null;
    final tag = raw.length > 2 ? _exprString(raw[2]) : null;
    final atList = raw.length > 3 ? _stringList(raw[3]) : const <String>[];
    final layer = raw.length > 4 ? _exprString(raw[4]) : null;

    if (nameParts.isEmpty && (expr == null || expr.isEmpty)) {
      return null;
    }

    return ImageSpec(
      name: nameParts,
      expression: expr,
      tag: tag,
      atList: atList,
      layer: layer,
    );
  }

  static String _qualifyStoreName(String store, String varname) {
    var cleanStore = store.trim();
    if (cleanStore.startsWith('store.')) {
      cleanStore = cleanStore.substring(6);
    } else if (cleanStore == 'store') {
      cleanStore = '';
    }
    return cleanStore.isEmpty ? varname : '$cleanStore.$varname';
  }

  static String? _pyCodeSource(dynamic codeObj) {
    if (codeObj == null) return null;
    if (codeObj is String) return codeObj;
    if (codeObj is PyObject) {
      final f = codeObj.fields;
      if (f.containsKey('source')) {
        final s = _exprString(f['source']);
        if (s != null) return s;
      }
      if (codeObj.state is List) {
        final stateList = codeObj.state as List;
        if (stateList.length >= 2) {
          final s = _exprString(stateList[1]);
          if (s != null) return s;
        }
        for (final item in stateList) {
          if (item is List && item.length >= 2) {
            final s = _exprString(item[1]);
            if (s != null) return s;
          }
        }
      }
      if (codeObj.args.isNotEmpty) {
        final s = _exprString(codeObj.args.first);
        if (s != null) return s;
      }
    }
    return null;
  }

  /// Extracts a displayable expression from a simple ATL block if present.
  static String? _extractAtlDisplayable(dynamic atlObj) {
    if (atlObj is! PyObject) return null;
    final stmts = atlObj.fields['statements'];
    if (stmts is List) {
      for (final item in stmts) {
        if (item is PyObject) {
          final exprs = item.fields['expressions'];
          if (exprs is List && exprs.isNotEmpty) {
            final firstPair = exprs.first;
            if (firstPair is List && firstPair.isNotEmpty) {
              final e = _exprString(firstPair.first);
              if (e != null && e.isNotEmpty) return e;
            }
          }
        }
      }
    }
    return null;
  }

  static String? _exprString(dynamic v) {
    if (v == null || v is PyClassRef) return null;
    if (v is String) return v;
    if (v is Uint8List) {
      return utf8.decode(v, allowMalformed: true);
    }
    if (v is PyObject) {
      for (final arg in v.args) {
        if (arg is String) return arg;
        if (arg is Uint8List) {
          return utf8.decode(arg, allowMalformed: true);
        }
      }
      final f = v.fields;
      if (f['source'] != null) return _exprString(f['source']);
      if (f['s'] != null) return _exprString(f['s']);
      return null;
    }
    if (v is num || v is bool) return v.toString();
    return null;
  }

  static List<String> _stringList(dynamic v) {
    if (v is! Iterable) return const <String>[];
    final out = <String>[];
    for (final item in v) {
      final s = _exprString(item);
      if (s != null && s.isNotEmpty) {
        out.add(s);
      }
    }
    return out;
  }

  static int _intVal(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}
