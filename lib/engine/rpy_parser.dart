import 'script_ast.dart';

class _LogicalLine {
  const _LogicalLine({
    required this.lineNumber,
    required this.indent,
    required this.text,
  });

  final int lineNumber;
  final int indent;
  final String text;
}

/// Indentation-aware parser for plain-text Ren'Py `.rpy` scripts.
/// Produces the same [ScriptBlock] AST nodes as [RpycReader].
class RpyParser {
  static ScriptFile parseSource(
    String source, {
    required String virtualPath,
    String origin = 'rpy',
  }) {
    final rawLines = source.replaceAll('\r\n', '\n').split('\n');
    final logicalLines = _tokenizeLogicalLines(rawLines);
    final parser = _RpyBlockParser(virtualPath, rawLines, logicalLines);
    final nodes = parser.parseBlock(-1);
    return ScriptFile(
      path: virtualPath,
      block: ScriptBlock(nodes),
      origin: origin,
    );
  }

  static List<_LogicalLine> _tokenizeLogicalLines(List<String> rawLines) {
    final out = <_LogicalLine>[];
    int i = 0;

    while (i < rawLines.length) {
      final firstRaw = rawLines[i];
      final startLineNum = i + 1;
      final indent = _measureIndent(firstRaw);
      var stripped = _stripCommentOutsideStrings(firstRaw).trim();

      if (stripped.isEmpty) {
        i++;
        continue;
      }

      final buf = StringBuffer(stripped);
      int bracketDepth = _netBracketDelta(stripped);
      String? openTriple = _unclosedTripleQuote(stripped, null);

      while ((buf.toString().endsWith(r'\') ||
              bracketDepth > 0 ||
              openTriple != null) &&
          i + 1 < rawLines.length) {
        if (buf.toString().endsWith(r'\')) {
          final current = buf.toString();
          buf
            ..clear()
            ..write(current.substring(0, current.length - 1).trimRight());
        } else {
          buf.write('\n');
        }
        i++;
        final nextRaw = rawLines[i];
        if (openTriple != null) {
          buf.write(nextRaw);
          openTriple = _unclosedTripleQuote(nextRaw, openTriple);
        } else {
          final nextClean = _stripCommentOutsideStrings(nextRaw).trim();
          buf.write(' ');
          buf.write(nextClean);
          bracketDepth += _netBracketDelta(nextClean);
          openTriple = _unclosedTripleQuote(nextClean, null);
        }
      }

      final combined = buf.toString().trim();
      if (combined.isNotEmpty) {
        out.add(_LogicalLine(
          lineNumber: startLineNum,
          indent: indent,
          text: combined,
        ));
      }
      i++;
    }

    return out;
  }

  static int _measureIndent(String line) {
    int count = 0;
    for (int i = 0; i < line.length; i++) {
      final c = line.codeUnitAt(i);
      if (c == 0x20) {
        count += 1;
      } else if (c == 0x09) {
        count += 4;
      } else {
        break;
      }
    }
    return count;
  }

  static String _stripCommentOutsideStrings(String line) {
    String? quote;
    bool escaped = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (line.startsWith(quote, i)) {
          i += quote.length - 1;
          quote = null;
        }
      } else {
        if (line.startsWith('"""', i)) {
          quote = '"""';
          i += 2;
        } else if (line.startsWith("'''", i)) {
          quote = "'''";
          i += 2;
        } else if (ch == '"' || ch == "'") {
          quote = ch;
        } else if (ch == '#') {
          return line.substring(0, i);
        }
      }
    }
    return line;
  }

  static int _netBracketDelta(String s) {
    int delta = 0;
    String? quote;
    bool escaped = false;
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (s.startsWith(quote, i)) {
          i += quote.length - 1;
          quote = null;
        }
        continue;
      }
      if (s.startsWith('"""', i)) {
        quote = '"""';
        i += 2;
      } else if (s.startsWith("'''", i)) {
        quote = "'''";
        i += 2;
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '(' || ch == '[' || ch == '{') {
        delta++;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        delta--;
      }
    }
    return delta;
  }

  static String? _unclosedTripleQuote(String s, String? current) {
    String? quote = current;
    bool escaped = false;
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (s.startsWith(quote, i)) {
          i += quote.length - 1;
          quote = null;
        }
      } else {
        if (s.startsWith('"""', i)) {
          quote = '"""';
          i += 2;
        } else if (s.startsWith("'''", i)) {
          quote = "'''";
          i += 2;
        } else if (ch == '"' || ch == "'") {
          // Consume single-line string
          final single = ch;
          i++;
          while (i < s.length) {
            if (s[i] == r'\') {
              i += 2;
              continue;
            }
            if (s[i] == single) break;
            i++;
          }
        }
      }
    }
    return quote;
  }
}

class _RpyBlockParser {
  _RpyBlockParser(this.file, this.rawLines, this.lines);

  final String file;
  final List<String> rawLines;
  final List<_LogicalLine> lines;
  int _idx = 0;

  List<ScriptNode> parseBlock(int parentIndent) {
    final nodes = <ScriptNode>[];
    while (_idx < lines.length) {
      final cur = lines[_idx];
      if (cur.indent <= parentIndent) {
        break;
      }
      final parsed = _parseStatement(cur);
      nodes.addAll(parsed);
    }
    return nodes;
  }

  List<ScriptNode> _parseStatement(_LogicalLine cur) {
    final text = cur.text;
    final lineNum = cur.lineNumber;
    final indent = cur.indent;

    // 1. One-line Python: $ ...
    if (text.startsWith(r'$')) {
      _idx++;
      final code = text.substring(1).trim();
      if (code.isEmpty) return const <ScriptNode>[];
      return <ScriptNode>[PythonNode(file, lineNum, source: code)];
    }

    // 2. Python block: python [early] [hide] [in store]:
    final pyBlockMatch = RegExp(
      r'^(?:init\s+(?:[-+]?\d+\s+)?)?(?:early\s+)?python(?:\s+early|\s+hide|\s+in\s+[a-zA-Z0-9_.]+)*\s*:\s*$',
    ).firstMatch(text);
    if (pyBlockMatch != null) {
      _idx++;
      final pySource = _collectRawPythonBlock(indent);
      if (pySource.trim().isEmpty) return const <ScriptNode>[];
      if (text.startsWith('init')) {
        return <ScriptNode>[
          InitNode(
            file,
            lineNum,
            priority: 0,
            block: ScriptBlock(<ScriptNode>[
              PythonNode(file, lineNum, source: pySource),
            ]),
          ),
        ];
      }
      return <ScriptNode>[PythonNode(file, lineNum, source: pySource)];
    }

    // 3. Init block or single-line init statement
    final initMatch =
        RegExp(r'^init(?:\s+([-+]?\d+))?(?:\s+(.*))?$').firstMatch(text);
    if (initMatch != null) {
      final priority = int.tryParse(initMatch.group(1) ?? '0') ?? 0;
      final rest = (initMatch.group(2) ?? '').trim();
      if (rest.isEmpty || rest == ':') {
        _idx++;
        final children = parseBlock(indent);
        return <ScriptNode>[
          InitNode(file, lineNum,
              priority: priority, block: ScriptBlock(children)),
        ];
      } else {
        // Inline statement after `init [offset]` such as `init -1 define ...`
        final synthetic = _LogicalLine(
          lineNumber: lineNum,
          indent: indent,
          text: rest,
        );
        lines[_idx] = synthetic;
        final inner = _parseStatement(synthetic);
        return <ScriptNode>[
          InitNode(file, lineNum,
              priority: priority, block: ScriptBlock(inner)),
        ];
      }
    }

    // 4. Label
    final labelMatch = RegExp(
      r'^label\s+([a-zA-Z0-9_.]+)\s*(\([^\)]*\))?(?:\s+hide)?\s*:\s*$',
    ).firstMatch(text);
    if (labelMatch != null) {
      _idx++;
      final name = labelMatch.group(1)!;
      final params = labelMatch.group(2);
      final body = parseBlock(indent);
      return <ScriptNode>[
        LabelNode(
          file,
          lineNum,
          name: name,
          parameters: params,
          block: ScriptBlock(body),
        ),
      ];
    }

    // 5. Menu
    final menuMatch =
        RegExp(r'^menu(?:\s+([a-zA-Z0-9_]+))?\s*:\s*$').firstMatch(text);
    if (menuMatch != null) {
      _idx++;
      return <ScriptNode>[_parseMenu(lineNum, indent)];
    }

    // 6. If / elif / else
    final ifMatch = RegExp(r'^if\s+(.+):\s*$').firstMatch(text);
    if (ifMatch != null) {
      _idx++;
      final firstCond = ifMatch.group(1)!.trim();
      final firstBody = parseBlock(indent);
      final branches = <IfBranch>[
        IfBranch(condition: firstCond, block: ScriptBlock(firstBody)),
      ];

      while (_idx < lines.length && lines[_idx].indent == indent) {
        final nextText = lines[_idx].text;
        final elifMatch = RegExp(r'^elif\s+(.+):\s*$').firstMatch(nextText);
        if (elifMatch != null) {
          _idx++;
          final cond = elifMatch.group(1)!.trim();
          final body = parseBlock(indent);
          branches.add(IfBranch(condition: cond, block: ScriptBlock(body)));
          continue;
        }
        if (RegExp(r'^else\s*:\s*$').hasMatch(nextText)) {
          _idx++;
          final body = parseBlock(indent);
          branches.add(IfBranch(condition: null, block: ScriptBlock(body)));
          break;
        }
        break;
      }

      return <ScriptNode>[IfNode(file, lineNum, branches: branches)];
    }

    // 7. While
    final whileMatch = RegExp(r'^while\s+(.+):\s*$').firstMatch(text);
    if (whileMatch != null) {
      _idx++;
      final cond = whileMatch.group(1)!.trim();
      final body = parseBlock(indent);
      return <ScriptNode>[
        WhileNode(file, lineNum, condition: cond, block: ScriptBlock(body)),
      ];
    }

    // 8. Define
    final defineMatch = RegExp(
      r'^define(?:\s+[-+]?\d+)?\s+([a-zA-Z0-9_.]+)\s*(\+=|\|=|=)\s*(.+)$',
      dotAll: true,
    ).firstMatch(text);
    if (defineMatch != null) {
      _idx++;
      var name = defineMatch.group(1)!.trim();
      if (name.startsWith('store.')) name = name.substring(6);
      final op = defineMatch.group(2)!;
      final expr = defineMatch.group(3)!.trim();
      return <ScriptNode>[
        DefineNode(file, lineNum, name: name, expression: expr, operator: op),
      ];
    }

    // 9. Default
    final defaultMatch = RegExp(
      r'^default\s+([a-zA-Z0-9_.]+)\s*=\s*(.+)$',
      dotAll: true,
    ).firstMatch(text);
    if (defaultMatch != null) {
      _idx++;
      var name = defaultMatch.group(1)!.trim();
      if (name.startsWith('store.')) name = name.substring(6);
      final expr = defaultMatch.group(2)!.trim();
      return <ScriptNode>[
        DefaultNode(file, lineNum, name: name, expression: expr),
      ];
    }

    // 10. Image definition (`image bg uni = "bg_uni.jpg"` or ATL `image ...:`)
    final imageEqMatch = RegExp(
      r'^image\s+([a-zA-Z0-9_\-\s]+?)\s*=\s*(.+)$',
      dotAll: true,
    ).firstMatch(text);
    if (imageEqMatch != null) {
      _idx++;
      final parts = imageEqMatch
          .group(1)!
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList();
      final expr = imageEqMatch.group(2)!.trim();
      return <ScriptNode>[
        ImageNode(file, lineNum, name: parts, expression: expr),
      ];
    }

    final imageAtlMatch = RegExp(
      r'^image\s+([a-zA-Z0-9_\-\s]+?)\s*:\s*$',
    ).firstMatch(text);
    if (imageAtlMatch != null) {
      _idx++;
      final parts = imageAtlMatch
          .group(1)!
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList();
      final atlExpr = _skipBlockAndFindFirstString(indent);
      return <ScriptNode>[
        ImageNode(file, lineNum, name: parts, expression: atlExpr),
      ];
    }

    // 11. Jump
    final jumpMatch = RegExp(
      r'^jump\s+(expression\s+)?(.+)$',
    ).firstMatch(text);
    if (jumpMatch != null) {
      _idx++;
      final isExpr = jumpMatch.group(1) != null;
      final target = jumpMatch.group(2)!.trim();
      return <ScriptNode>[
        JumpNode(file, lineNum, target: target, isExpression: isExpr),
      ];
    }

    // 12. Call
    final callMatch = RegExp(
      r'^call\s+(expression\s+)?([a-zA-Z0-9_.]+)(?:\([^\)]*\))?(?:\s+from\s+[a-zA-Z0-9_.]+)?$',
    ).firstMatch(text);
    if (callMatch != null) {
      _idx++;
      final isExpr = callMatch.group(1) != null;
      final target = callMatch.group(2)!.trim();
      return <ScriptNode>[
        CallNode(file, lineNum, target: target, isExpression: isExpr),
      ];
    }

    // 13. Return
    if (text == 'return' || text.startsWith('return ')) {
      _idx++;
      return <ScriptNode>[ReturnNode(file, lineNum)];
    }

    // 14. Pass
    if (text == 'pass') {
      _idx++;
      return const <ScriptNode>[];
    }

    // 15. Scene / Show / Hide / With
    if (text == 'scene' ||
        text.startsWith('scene ') ||
        text.startsWith('scene:')) {
      _idx++;
      var body = text.substring(5).trim();
      if (body.endsWith(':')) {
        body = body.substring(0, body.length - 1).trim();
        _skipBlock(indent);
      }
      final parsed = _parseSceneShowClause(body);
      return <ScriptNode>[
        SceneNode(file, lineNum,
            image: parsed.spec, transition: parsed.transition),
      ];
    }

    if (text.startsWith('show ') && !text.startsWith('show screen ')) {
      _idx++;
      var body = text.substring(5).trim();
      if (body.endsWith(':')) {
        body = body.substring(0, body.length - 1).trim();
        _skipBlock(indent);
      }
      final parsed = _parseSceneShowClause(body);
      if (parsed.spec == null) return const <ScriptNode>[];
      return <ScriptNode>[
        ShowNode(file, lineNum,
            image: parsed.spec!, transition: parsed.transition),
      ];
    }

    if (text.startsWith('hide ') && !text.startsWith('hide screen ')) {
      _idx++;
      var body = text.substring(5).trim();
      if (body.endsWith(':')) {
        body = body.substring(0, body.length - 1).trim();
        _skipBlock(indent);
      }
      final parsed = _parseSceneShowClause(body);
      if (parsed.spec == null) return const <ScriptNode>[];
      return <ScriptNode>[
        HideNode(file, lineNum,
            image: parsed.spec!, transition: parsed.transition),
      ];
    }

    if (text.startsWith('with ')) {
      _idx++;
      final trans = text.substring(5).trim();
      if (trans.isEmpty || trans == 'None') return const <ScriptNode>[];
      return <ScriptNode>[WithNode(file, lineNum, transition: trans)];
    }

    // 16. Audio & Pause statements
    final playMatch = RegExp(
      r'^(play|queue)\s+(music|sound|voice|audio)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (playMatch != null) {
      _idx++;
      final verb = playMatch.group(1)!.toLowerCase();
      final channel = playMatch.group(2)!.toLowerCase();
      var rest = playMatch.group(3)!.trim();
      bool? loop;
      if (RegExp(r'\bnoloop\b', caseSensitive: false).hasMatch(rest)) {
        loop = false;
      } else if (RegExp(r'\bloop\b', caseSensitive: false).hasMatch(rest)) {
        loop = true;
      }
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
          lineNum,
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
    ).firstMatch(text);
    if (stopMatch != null) {
      _idx++;
      return <ScriptNode>[
        StopNode(file, lineNum, channel: stopMatch.group(1)!.toLowerCase()),
      ];
    }

    final voiceMatch = RegExp(r'^voice\s+(.+)$').firstMatch(text);
    if (voiceMatch != null) {
      _idx++;
      return <ScriptNode>[
        PlayNode(
          file,
          lineNum,
          channel: 'voice',
          fileExpression: voiceMatch.group(1)!.trim(),
          loop: false,
        ),
      ];
    }

    final pauseMatch = RegExp(r'^pause(?:\s+(.+))?$').firstMatch(text);
    if (pauseMatch != null) {
      _idx++;
      return <ScriptNode>[
        PauseNode(file, lineNum, duration: pauseMatch.group(1)?.trim()),
      ];
    }

    // 17. Blocks we intentionally skip (screen, style, transform, translate, layeredimage)
    if (RegExp(
            r'^(screen|style|transform|layeredimage|camera|testcase|python)\b')
        .hasMatch(text)) {
      _idx++;
      if (text.endsWith(':')) {
        _skipBlock(indent);
      }
      return const <ScriptNode>[];
    }

    if (text.startsWith('translate ')) {
      final transMatch =
          RegExp(r'^translate\s+([a-zA-Z0-9_]+)\s+').firstMatch(text);
      final lang = transMatch?.group(1);
      _idx++;
      if (lang != null && lang != 'None') {
        if (text.endsWith(':')) {
          _skipBlock(indent);
        }
        return const <ScriptNode>[];
      }
      if (text.endsWith(':')) {
        return parseBlock(indent);
      }
      return const <ScriptNode>[];
    }

    // 18. Window / NVL / Show screen / Call screen statements -> skip cleanly
    if (text.startsWith('window ') ||
        text.startsWith('show screen ') ||
        text.startsWith('hide screen ') ||
        text.startsWith('call screen ') ||
        text.startsWith('nvl ')) {
      _idx++;
      if (text.endsWith(':')) _skipBlock(indent);
      return const <ScriptNode>[];
    }

    // 19. Say statement (dialogue line)
    final sayNode = _tryParseSay(lineNum, text);
    if (sayNode != null) {
      _idx++;
      if (text.endsWith(':')) {
        _skipBlock(indent);
      }
      return <ScriptNode>[sayNode];
    }

    // 20. Any other unknown block or statement
    _idx++;
    if (text.endsWith(':')) {
      _skipBlock(indent);
    }
    return const <ScriptNode>[];
  }

  MenuNode _parseMenu(int menuLine, int menuIndent) {
    final choices = <MenuChoice>[];
    String? caption;
    String? setVar;

    while (_idx < lines.length && lines[_idx].indent > menuIndent) {
      final item = lines[_idx];
      final itemText = item.text;
      final itemIndent = item.indent;

      if (itemText.startsWith('set ')) {
        setVar = itemText.substring(4).trim();
        _idx++;
        continue;
      }

      if (itemText.endsWith(':')) {
        // Choice entry: `"Choice label" [if condition]:`
        final header = itemText.substring(0, itemText.length - 1).trim();
        final extracted = _extractFirstQuotedString(header);
        if (extracted != null) {
          final label = extracted.value;
          final afterQuote = header.substring(extracted.endIndex).trim();
          String? condition;
          final ifMatch = RegExp(r'^if\s+(.+)$').firstMatch(afterQuote);
          if (ifMatch != null) {
            condition = ifMatch.group(1)!.trim();
          }
          _idx++;
          final choiceBody = parseBlock(itemIndent);
          choices.add(MenuChoice(
            text: label,
            condition: condition,
            block: ScriptBlock(choiceBody),
          ));
          continue;
        }
      }

      // Menu caption line (Say statement inside menu without `:`)
      final say = _tryParseSay(item.lineNumber, itemText);
      if (say != null) {
        caption = say.what;
      }
      _idx++;
    }

    return MenuNode(
      file,
      menuLine,
      choices: choices,
      caption: caption,
      setVariable: setVar,
    );
  }

  SayNode? _tryParseSay(int lineNum, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Case 1: Starts with a quoted string -> either narrator `"text"` or `"Speaker" "text"`
    if (trimmed.startsWith('"') || trimmed.startsWith("'")) {
      final first = _extractFirstQuotedString(trimmed);
      if (first == null) return null;
      final rest = trimmed.substring(first.endIndex).trim();
      if (rest.startsWith('"') || rest.startsWith("'")) {
        final second = _extractFirstQuotedString(rest);
        if (second != null) {
          return SayNode(
            file,
            lineNum,
            who: '"${first.value}"',
            what: second.value,
          );
        }
      }
      return SayNode(file, lineNum, who: null, what: first.value);
    }

    // Case 2: Starts with identifier (speaker variable + optional attributes + quoted text)
    final prefixMatch = RegExp(
      r'^([a-zA-Z_][a-zA-Z0-9_.]*)((?:\s+[a-zA-Z0-9_\-]+)*)\s+([\"' "'" r'''].*)$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (prefixMatch != null) {
      final who = prefixMatch.group(1)!;
      final attrStr = (prefixMatch.group(2) ?? '').trim();
      final quotePart = prefixMatch.group(3)!;
      final quoted = _extractFirstQuotedString(quotePart);
      if (quoted != null) {
        final attrs = attrStr.isEmpty
            ? const <String>[]
            : attrStr.split(RegExp(r'\s+'));
        return SayNode(
          file,
          lineNum,
          who: who,
          what: quoted.value,
          attributes: attrs,
        );
      }
    }

    return null;
  }

  _ParsedSceneClause _parseSceneShowClause(String body) {
    if (body.isEmpty) {
      return const _ParsedSceneClause(spec: null, transition: null);
    }

    String? transition;
    var working = body;

    final withMatch = RegExp(r'\bwith\s+([a-zA-Z0-9_.\(\)]+)\s*$')
        .firstMatch(working);
    if (withMatch != null) {
      transition = withMatch.group(1)!.trim();
      working = working.substring(0, withMatch.start).trim();
    }

    // Strip `behind ...`, `zorder ...`, `onlayer ...`
    String? layer;
    final layerMatch =
        RegExp(r'\bonlayer\s+([a-zA-Z0-9_]+)').firstMatch(working);
    if (layerMatch != null) {
      layer = layerMatch.group(1);
      working = working.replaceRange(layerMatch.start, layerMatch.end, '').trim();
    }
    working = working
        .replaceAll(RegExp(r'\bzorder\s+[-+]?\d+'), '')
        .replaceAll(RegExp(r'\bbehind\s+[a-zA-Z0-9_,\s]+'), '')
        .trim();

    String? asTag;
    final asMatch = RegExp(r'\bas\s+([a-zA-Z0-9_]+)').firstMatch(working);
    if (asMatch != null) {
      asTag = asMatch.group(1);
      working = working.replaceRange(asMatch.start, asMatch.end, '').trim();
    }

    List<String> atList = const <String>[];
    final atMatch = RegExp(r'\bat\s+([a-zA-Z0-9_,\s]+)$').firstMatch(working);
    if (atMatch != null) {
      atList = atMatch
          .group(1)!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      working = working.substring(0, atMatch.start).trim();
    }

    if (working.startsWith('expression ')) {
      final expr = working.substring(11).trim();
      return _ParsedSceneClause(
        spec: ImageSpec(
          name: const <String>[],
          expression: expr,
          tag: asTag,
          atList: atList,
          layer: layer,
        ),
        transition: transition,
      );
    }

    final nameParts = working
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (nameParts.isEmpty) {
      return _ParsedSceneClause(spec: null, transition: transition);
    }

    return _ParsedSceneClause(
      spec: ImageSpec(
        name: nameParts,
        tag: asTag,
        atList: atList,
        layer: layer,
      ),
      transition: transition,
    );
  }

  String _collectRawPythonBlock(int parentIndent) {
    if (_idx >= lines.length || lines[_idx].indent <= parentIndent) {
      return '';
    }
    final startLine = lines[_idx].lineNumber;
    while (_idx < lines.length && lines[_idx].indent > parentIndent) {
      _idx++;
    }
    final endLine =
        _idx < lines.length ? lines[_idx].lineNumber - 1 : rawLines.length;

    final collected = <String>[];
    int? minIndent;
    for (int ln = startLine; ln <= endLine && ln <= rawLines.length; ln++) {
      final raw = rawLines[ln - 1];
      if (raw.trim().isEmpty) {
        collected.add('');
        continue;
      }
      final ind = RpyParser._measureIndent(raw);
      if (minIndent == null || ind < minIndent) {
        minIndent = ind;
      }
      collected.add(raw);
    }

    final base = minIndent ?? 0;
    return collected.map((l) {
      if (l.trim().isEmpty) return '';
      int remove = 0;
      int i = 0;
      while (i < l.length && remove < base) {
        if (l.codeUnitAt(i) == 0x20) {
          remove += 1;
        } else if (l.codeUnitAt(i) == 0x09) {
          remove += 4;
        } else {
          break;
        }
        i++;
      }
      return l.substring(i);
    }).join('\n');
  }

  void _skipBlock(int parentIndent) {
    while (_idx < lines.length && lines[_idx].indent > parentIndent) {
      _idx++;
    }
  }

  String? _skipBlockAndFindFirstString(int parentIndent) {
    String? found;
    while (_idx < lines.length && lines[_idx].indent > parentIndent) {
      if (found == null) {
        final q = _extractFirstQuotedString(lines[_idx].text);
        if (q != null &&
            (q.value.endsWith('.png') ||
                q.value.endsWith('.jpg') ||
                q.value.endsWith('.jpeg') ||
                q.value.endsWith('.webp'))) {
          found = '"${q.value}"';
        }
      }
      _idx++;
    }
    return found;
  }

  _ExtractedString? _extractFirstQuotedString(String s) {
    int i = 0;
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
    if (i >= s.length) return null;

    String quote;
    if (s.startsWith('"""', i)) {
      quote = '"""';
    } else if (s.startsWith("'''", i)) {
      quote = "'''";
    } else if (s[i] == '"' || s[i] == "'") {
      quote = s[i];
    } else {
      return null;
    }

    i += quote.length;
    final sb = StringBuffer();
    while (i < s.length) {
      if (s[i] == r'\' && i + 1 < s.length) {
        final next = s[i + 1];
        switch (next) {
          case 'n':
            sb.write('\n');
            break;
          case 't':
            sb.write('\t');
            break;
          case '"':
            sb.write('"');
            break;
          case "'":
            sb.write("'");
            break;
          case r'\':
            sb.write(r'\');
            break;
          default:
            sb.write(next);
        }
        i += 2;
        continue;
      }
      if (s.startsWith(quote, i)) {
        return _ExtractedString(sb.toString(), i + quote.length);
      }
      sb.write(s[i]);
      i++;
    }
    return _ExtractedString(sb.toString(), s.length);
  }
}

class _ParsedSceneClause {
  const _ParsedSceneClause({required this.spec, required this.transition});

  final ImageSpec? spec;
  final String? transition;
}

class _ExtractedString {
  const _ExtractedString(this.value, this.endIndex);

  final String value;
  final int endIndex;
}
