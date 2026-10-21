import 'dart:math' as math;

/// Represents a `Character(...)` object defined in a Ren'Py script.
class RenpyCharacter {
  const RenpyCharacter({
    required this.name,
    this.colorHex,
    this.imageTag,
    this.whatPrefix = '',
    this.whatSuffix = '',
    this.isDynamic = false,
  });

  final String? name;
  final String? colorHex;
  final String? imageTag;
  final String whatPrefix;
  final String whatSuffix;
  final bool isDynamic;

  Map<String, dynamic> toJson() => <String, dynamic>{
        '__type__': 'RenpyCharacter',
        'name': name,
        'colorHex': colorHex,
        'imageTag': imageTag,
        'whatPrefix': whatPrefix,
        'whatSuffix': whatSuffix,
        'isDynamic': isDynamic,
      };

  factory RenpyCharacter.fromJson(Map<String, dynamic> map) {
    return RenpyCharacter(
      name: map['name'] as String?,
      colorHex: map['colorHex'] as String?,
      imageTag: map['imageTag'] as String?,
      whatPrefix: (map['whatPrefix'] as String?) ?? '',
      whatSuffix: (map['whatSuffix'] as String?) ?? '',
      isDynamic: (map['isDynamic'] as bool?) ?? false,
    );
  }
}

/// Represents a `Solid("#rrggbb")` displayable.
class SolidDisplayable {
  const SolidDisplayable(this.colorHex);
  final String colorHex;
}

/// Lightweight evaluator for Ren'Py Python expressions and simple statement
/// blocks (`$ x = 1`, `if flag:`, `Character(...)`, string interpolation).
class MiniPython {
  MiniPython({Map<String, dynamic>? initialStore})
      : store = initialStore ?? <String, dynamic>{};

  final Map<String, dynamic> store;
  final math.Random _rng = math.Random();
  final Set<String> seenLabels = <String>{};
  final Set<String> knownLabels = <String>{};

  /// Set by `renpy.jump("target")` inside a Python block if invoked.
  String? pendingJump;

  /// Deep-clones serializable store values for rollback snapshots and saves.
  Map<String, dynamic> snapshotStore() {
    final copy = <String, dynamic>{};
    for (final entry in store.entries) {
      copy[entry.key] = _cloneValue(entry.value);
    }
    return copy;
  }

  void restoreStore(Map<String, dynamic> snapshot) {
    store
      ..clear()
      ..addAll(_cloneValue(snapshot) as Map<String, dynamic>);
  }

  static dynamic _cloneValue(dynamic v) {
    if (v is List) return v.map(_cloneValue).toList();
    if (v is Map) {
      final out = <String, dynamic>{};
      for (final e in v.entries) {
        out[e.key.toString()] = _cloneValue(e.value);
      }
      return out;
    }
    if (v is Set) return v.map(_cloneValue).toSet();
    return v;
  }

  /// Executes a single-line or multi-line Python block against [store].
  void execute(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    _execBlock(lines, 0, lines.length);
  }

  void _execBlock(List<String> lines, int start, int end) {
    int i = start;
    while (i < end) {
      final raw = lines[i];
      final trimmed = _stripInlineComment(raw).trim();
      if (trimmed.isEmpty ||
          trimmed == 'pass' ||
          trimmed.startsWith('import ') ||
          trimmed.startsWith('from ')) {
        i++;
        continue;
      }

      // Handle simple if / elif / else inside python blocks
      if (trimmed.startsWith('if ') && trimmed.endsWith(':')) {
        final baseIndent = _indentOf(raw);
        i = _execPythonIfChain(lines, i, end, baseIndent);
        continue;
      }

      _execSingleStatement(trimmed);
      i++;
    }
  }

  int _execPythonIfChain(
      List<String> lines, int startIdx, int limit, int baseIndent) {
    int i = startIdx;
    bool branchTaken = false;

    while (i < limit) {
      final raw = lines[i];
      final trimmed = _stripInlineComment(raw).trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }
      final ind = _indentOf(raw);
      if (ind < baseIndent) break;
      if (ind > baseIndent) {
        i++;
        continue;
      }

      bool isConditionBranch = false;
      String? condExpr;

      if (trimmed.startsWith('if ') && trimmed.endsWith(':')) {
        if (i != startIdx) break; // Start of a separate if statement
        isConditionBranch = true;
        condExpr = trimmed.substring(3, trimmed.length - 1).trim();
      } else if (trimmed.startsWith('elif ') && trimmed.endsWith(':')) {
        isConditionBranch = true;
        condExpr = trimmed.substring(5, trimmed.length - 1).trim();
      } else if (trimmed == 'else:' ||
          RegExp(r'^else\s*:$').hasMatch(trimmed)) {
        isConditionBranch = true;
        condExpr = null;
      } else {
        break;
      }

      final bodyStart = i + 1;
      int bodyEnd = bodyStart;
      while (bodyEnd < limit) {
        final nextTrim = _stripInlineComment(lines[bodyEnd]).trim();
        if (nextTrim.isNotEmpty && _indentOf(lines[bodyEnd]) <= baseIndent) {
          break;
        }
        bodyEnd++;
      }

      if (!branchTaken && isConditionBranch) {
        final shouldRun = condExpr == null ? true : evalBool(condExpr);
        if (shouldRun) {
          branchTaken = true;
          _execBlock(lines, bodyStart, bodyEnd);
        }
      }

      i = bodyEnd;
    }

    return i;
  }

  void _execSingleStatement(String stmt) {
    // Handle `renpy.jump("label")`
    final jumpCall = RegExp(
            r'''^renpy\.jump\(\s*['"]([^'"]+)['"]\s*\)$''')
        .firstMatch(stmt);
    if (jumpCall != null) {
      pendingJump = jumpCall.group(1);
      return;
    }

    // Handle ` variable += expr`, `-=`, `*=`, `/=`, `|=`, `=`
    final assignMatch = RegExp(
      r'^([a-zA-Z_][a-zA-Z0-9_.]*(?:\s*,\s*[a-zA-Z_][a-zA-Z0-9_.]*)*)\s*(\+=|-=|\*=|/=|\|=|=)(?!=)\s*(.+)$',
      dotAll: true,
    ).firstMatch(stmt);

    if (assignMatch != null) {
      final lhsRaw = assignMatch.group(1)!.trim();
      final op = assignMatch.group(2)!;
      final rhsRaw = assignMatch.group(3)!.trim();

      if (lhsRaw.contains(',') && op == '=') {
        final targets = lhsRaw.split(',').map((s) => _cleanVarName(s.trim())).toList();
        final rhsVal = evaluate(rhsRaw);
        if (rhsVal is List) {
          for (int k = 0; k < targets.length && k < rhsVal.length; k++) {
            store[targets[k]] = rhsVal[k];
          }
        }
        return;
      }

      final varName = _cleanVarName(lhsRaw);
      final rhsVal = evaluate(rhsRaw);
      applyAssignment(varName, op, rhsVal);
      return;
    }

    // Handle dictionary subscript assignment: `dict_var[key] = val`
    final subAssign = RegExp(
      r'^([a-zA-Z_][a-zA-Z0-9_.]*)\[(.+?)\]\s*=\s*(.+)$',
    ).firstMatch(stmt);
    if (subAssign != null) {
      final targetName = _cleanVarName(subAssign.group(1)!);
      final keyVal = evaluate(subAssign.group(2)!);
      final rhsVal = evaluate(subAssign.group(3)!);
      final container = store[targetName];
      if (container is Map && keyVal != null) {
        container[keyVal] = rhsVal;
      } else if (container is List && keyVal is int) {
        if (keyVal >= 0 && keyVal < container.length) {
          container[keyVal] = rhsVal;
        }
      }
      return;
    }

    // Handle `.append(...)` / `.add(...)` / `.remove(...)`
    final methodCall = RegExp(
      r'^([a-zA-Z_][a-zA-Z0-9_.]*)\.(append|add|remove|discard|clear)\((.*)\)$',
    ).firstMatch(stmt);
    if (methodCall != null) {
      final targetName = _cleanVarName(methodCall.group(1)!);
      final method = methodCall.group(2)!;
      final argRaw = methodCall.group(3)!.trim();
      final container = store[targetName];
      final argVal = argRaw.isEmpty ? null : evaluate(argRaw);
      if (container is List) {
        if (method == 'append') container.add(argVal);
        if (method == 'remove') container.remove(argVal);
        if (method == 'clear') container.clear();
      } else if (container is Set) {
        if (method == 'add') container.add(argVal);
        if (method == 'remove' || method == 'discard') container.remove(argVal);
        if (method == 'clear') container.clear();
      }
      return;
    }

    // Otherwise evaluate expression for side effects
    evaluate(stmt);
  }

  void applyAssignment(String rawName, String op, dynamic rhsVal) {
    final name = _cleanVarName(rawName);
    if (op == '=') {
      store[name] = rhsVal;
      return;
    }
    final cur = store[name];
    switch (op) {
      case '+=':
        if (cur is num && rhsVal is num) {
          store[name] = cur + rhsVal;
        } else if (cur is String) {
          store[name] = cur + (rhsVal?.toString() ?? '');
        } else if (cur is List && rhsVal is Iterable) {
          cur.addAll(rhsVal);
        } else {
          store[name] = (cur is num ? cur : 0) + (rhsVal is num ? rhsVal : 0);
        }
        break;
      case '-=':
        if (cur is num && rhsVal is num) {
          store[name] = cur - rhsVal;
        } else {
          store[name] = (cur is num ? cur : 0) - (rhsVal is num ? rhsVal : 0);
        }
        break;
      case '*=':
        if (cur is num && rhsVal is num) {
          store[name] = cur * rhsVal;
        }
        break;
      case '/=':
        if (cur is num && rhsVal is num && rhsVal != 0) {
          store[name] = cur / rhsVal;
        }
        break;
      case '|=':
        if (cur is Set && rhsVal is Iterable) {
          cur.addAll(rhsVal);
        } else if (cur is int && rhsVal is int) {
          store[name] = cur | rhsVal;
        }
        break;
    }
  }

  bool evalBool(String expr) {
    return isTruthy(evaluate(expr));
  }

  static bool isTruthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty;
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  /// Evaluates a Python expression against [store].
  dynamic evaluate(String rawExpr) {
    var expr = rawExpr.trim();
    if (expr.isEmpty) return null;

    // Strip wrapping parentheses if balanced
    while (expr.startsWith('(') &&
        expr.endsWith(')') &&
        _isWrappedByOuterParens(expr)) {
      expr = expr.substring(1, expr.length - 1).trim();
    }

    // 1. Literals
    if (expr == 'True') return true;
    if (expr == 'False') return false;
    if (expr == 'None') return null;

    final intVal = int.tryParse(expr);
    if (intVal != null) return intVal;

    final doubleVal = double.tryParse(expr);
    if (doubleVal != null) return doubleVal;

    // 2. Ternary expression: `A if COND else B`
    final ternary = _splitTernary(expr);
    if (ternary != null) {
      return evalBool(ternary[1])
          ? evaluate(ternary[0])
          : evaluate(ternary[2]);
    }

    // 3. Boolean `or`
    final orParts = _splitTopLevelKeyword(expr, 'or');
    if (orParts.length > 1) {
      dynamic last;
      for (final part in orParts) {
        last = evaluate(part);
        if (isTruthy(last)) return last;
      }
      return last;
    }

    // 4. Boolean `and`
    final andParts = _splitTopLevelKeyword(expr, 'and');
    if (andParts.length > 1) {
      dynamic last;
      for (final part in andParts) {
        last = evaluate(part);
        if (!isTruthy(last)) return last;
      }
      return last;
    }

    // 5. Unary `not `
    if (expr.startsWith('not ') || expr.startsWith('not(')) {
      final inner = expr.substring(3).trim();
      return !evalBool(inner);
    }

    // 6. Comparisons: `==`, `!=`, `<=`, `>=`, `<`, `>`, `in`, `not in`, `is`, `is not`
    final cmp = _splitComparison(expr);
    if (cmp != null) {
      final left = evaluate(cmp.left);
      final right = evaluate(cmp.right);
      return _compare(left, cmp.op, right);
    }

    // 7. Addition / Subtraction (`+`, `-`) at top level
    final addSub = _splitTopLevelAddSub(expr);
    if (addSub != null) {
      final left = evaluate(addSub.left);
      final right = evaluate(addSub.right);
      if (addSub.op == '+') {
        if (left is num && right is num) return left + right;
        if (left is String || right is String) {
          return '${left ?? ''}${right ?? ''}';
        }
        if (left is List && right is List) return <dynamic>[...left, ...right];
      } else {
        if (left is num && right is num) return left - right;
      }
    }

    // 8. Multiplication / Division / Modulo (`*`, `//`, `/`, `%`)
    final mulDiv = _splitTopLevelMulDiv(expr);
    if (mulDiv != null) {
      final left = evaluate(mulDiv.left);
      final right = evaluate(mulDiv.right);
      if (left is num && right is num) {
        switch (mulDiv.op) {
          case '*':
            return left * right;
          case '//':
            return right != 0 ? left ~/ right : 0;
          case '/':
            return right != 0 ? left / right : 0.0;
          case '%':
            return right != 0 ? left % right : 0;
        }
      }
    }

    // 9. String literal (including r"...", u"...", """...""")
    final strLit = _tryParseStringLiteral(expr);
    if (strLit != null) return strLit;

    // 10. List literal `[...]`
    if (expr.startsWith('[') && expr.endsWith(']')) {
      final inner = expr.substring(1, expr.length - 1).trim();
      if (inner.isEmpty) return <dynamic>[];
      return _splitTopLevelArgs(inner).map(evaluate).toList();
    }

    // 11. Dict literal `{...}`
    if (expr.startsWith('{') && expr.endsWith('}')) {
      final inner = expr.substring(1, expr.length - 1).trim();
      if (inner.isEmpty) return <dynamic, dynamic>{};
      final items = _splitTopLevelArgs(inner);
      final map = <dynamic, dynamic>{};
      for (final item in items) {
        final colonIdx = _findTopLevelChar(item, ':');
        if (colonIdx != -1) {
          final k = evaluate(item.substring(0, colonIdx));
          final v = evaluate(item.substring(colonIdx + 1));
          map[k] = v;
        }
      }
      return map;
    }

    // 12. Function / constructor call: `FuncName(args...)`
    final callMatch =
        RegExp(r'^([a-zA-Z_][a-zA-Z0-9_.]*)\s*\((.*)\)$', dotAll: true)
            .firstMatch(expr);
    if (callMatch != null && _isBalancedCall(expr, callMatch.group(1)!.length)) {
      final fnName = callMatch.group(1)!.trim();
      final argsBody = callMatch.group(2)!.trim();
      return _evalCall(fnName, argsBody);
    }

    // 13. Subscript access: `container[key]`
    final subMatch =
        RegExp(r'^([a-zA-Z_][a-zA-Z0-9_.]*)\[(.+)\]$').firstMatch(expr);
    if (subMatch != null) {
      final target = _lookupVar(subMatch.group(1)!);
      final key = evaluate(subMatch.group(2)!);
      if (target is Map) return target[key];
      if (target is List && key is int && key >= 0 && key < target.length) {
        return target[key];
      }
      return null;
    }

    // 14. Variable lookup in store
    return _lookupVar(expr);
  }

  dynamic _lookupVar(String rawName) {
    final name = _cleanVarName(rawName);
    if (store.containsKey(name)) return store[name];
    // Handle attribute access on RenpyCharacter such as `e.name`
    final dotIdx = name.lastIndexOf('.');
    if (dotIdx != -1) {
      final prefix = name.substring(0, dotIdx);
      final attr = name.substring(dotIdx + 1);
      final obj = store[prefix];
      if (obj is RenpyCharacter) {
        if (attr == 'name') return obj.name;
        if (attr == 'image_tag') return obj.imageTag;
      } else if (obj is Map) {
        return obj[attr];
      }
    }
    return null;
  }

  dynamic _evalCall(String fnName, String argsBody) {
    final posArgs = <dynamic>[];
    final kwArgs = <String, dynamic>{};

    if (argsBody.isNotEmpty) {
      for (final rawArg in _splitTopLevelArgs(argsBody)) {
        final eqIdx = _findKeywordEquals(rawArg);
        if (eqIdx != -1) {
          final k = rawArg.substring(0, eqIdx).trim();
          final v = evaluate(rawArg.substring(eqIdx + 1));
          kwArgs[k] = v;
        } else {
          posArgs.add(evaluate(rawArg));
        }
      }
    }

    // Translation wrappers `_("...")` and `__(...)` and `_p("""...""")`
    if (fnName == '_' || fnName == '__' || fnName == '_p') {
      if (posArgs.isEmpty) return '';
      final s = posArgs.first?.toString() ?? '';
      if (fnName == '_p') {
        return s
            .split(RegExp(r'\n\s*\n'))
            .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
            .join('\n\n');
      }
      return s;
    }

    // Character / DynamicCharacter
    if (fnName == 'Character' ||
        fnName == 'DynamicCharacter' ||
        fnName.endsWith('.Character')) {
      final name = posArgs.isNotEmpty ? posArgs.first?.toString() : null;
      final color = (kwArgs['color'] ?? kwArgs['who_color'])?.toString();
      final image = kwArgs['image']?.toString();
      final prefix = kwArgs['what_prefix']?.toString() ?? '';
      final suffix = kwArgs['what_suffix']?.toString() ?? '';
      final isDyn =
          fnName == 'DynamicCharacter' || kwArgs['dynamic'] == true;

      // Inherit from kind if specified (`kind=base_char`)
      final kind = kwArgs['kind'];
      if (kind is RenpyCharacter) {
        return RenpyCharacter(
          name: name ?? kind.name,
          colorHex: color ?? kind.colorHex,
          imageTag: image ?? kind.imageTag,
          whatPrefix: prefix.isNotEmpty ? prefix : kind.whatPrefix,
          whatSuffix: suffix.isNotEmpty ? suffix : kind.whatSuffix,
          isDynamic: isDyn || kind.isDynamic,
        );
      }

      return RenpyCharacter(
        name: name,
        colorHex: color,
        imageTag: image,
        whatPrefix: prefix,
        whatSuffix: suffix,
        isDynamic: isDyn,
      );
    }

    // Displayable wrappers used in `image ... = ...`
    if (fnName == 'Solid') {
      final hex = posArgs.isNotEmpty ? posArgs.first?.toString() ?? '#000000' : '#000000';
      return SolidDisplayable(hex);
    }

    if (fnName == 'Image' ||
        fnName == 'Frame' ||
        fnName == ' im.Scale' ||
        fnName.startsWith('im.') ||
        fnName == ' At' ||
        fnName == 'At' ||
        fnName == 'AlphaMask' ||
        fnName == 'Transform') {
      for (final arg in posArgs) {
        if (arg is String &&
            (arg.endsWith('.png') ||
                arg.endsWith('.jpg') ||
                arg.endsWith('.jpeg') ||
                arg.endsWith('.webp'))) {
          return arg;
        }
      }
      if (kwArgs['child'] is String) return kwArgs['child'];
      return posArgs.isNotEmpty ? posArgs.first : null;
    }

    if (fnName == 'ConditionSwitch' || fnName == 'ShowingSwitch') {
      // ConditionSwitch("cond1", "img1.png", "True", "img2.png")
      for (int i = 0; i + 1 < posArgs.length; i += 2) {
        final cond = posArgs[i]?.toString() ?? 'False';
        if (cond == 'True' || cond == 'default' || evalBool(cond)) {
          return posArgs[i + 1];
        }
      }
      return posArgs.length >= 2 ? posArgs[1] : null;
    }

    // Standard Python built-ins
    switch (fnName) {
      case 'str':
        return posArgs.isNotEmpty ? (posArgs.first?.toString() ?? '') : '';
      case 'int':
        if (posArgs.isEmpty) return 0;
        final v = posArgs.first;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      case 'float':
        if (posArgs.isEmpty) return 0.0;
        final v = posArgs.first;
        if (v is num) return v.toDouble();
        return double.tryParse(v?.toString() ?? '') ?? 0.0;
      case 'bool':
        return posArgs.isNotEmpty && isTruthy(posArgs.first);
      case 'len':
        if (posArgs.isEmpty) return 0;
        final v = posArgs.first;
        if (v is String) return v.length;
        if (v is Iterable) return v.length;
        if (v is Map) return v.length;
        return 0;
      case 'abs':
        if (posArgs.isNotEmpty && posArgs.first is num) {
          return (posArgs.first as num).abs();
        }
        return 0;
      case 'min':
        final nums = posArgs.whereType<num>().toList();
        return nums.isEmpty ? 0 : nums.reduce(math.min);
      case 'max':
        final nums = posArgs.whereType<num>().toList();
        return nums.isEmpty ? 0 : nums.reduce(math.max);
      case 'range':
        if (posArgs.isEmpty) return <int>[];
        final start = posArgs.length >= 2 ? (posArgs[0] as num).toInt() : 0;
        final end = posArgs.length >= 2
            ? (posArgs[1] as num).toInt()
            : (posArgs[0] as num).toInt();
        final step = posArgs.length >= 3 ? (posArgs[2] as num).toInt() : 1;
        final out = <int>[];
        if (step > 0) {
          for (int k = start; k < end; k += step) {
            out.add(k);
          }
        }
        return out;
      case 'renpy.random.randint':
      case 'random.randint':
        if (posArgs.length >= 2) {
          final a = (posArgs[0] as num).toInt();
          final b = (posArgs[1] as num).toInt();
          if (b >= a) return a + _rng.nextInt(b - a + 1);
        }
        return 0;
      case 'renpy.random.choice':
      case 'random.choice':
        if (posArgs.isNotEmpty &&
            posArgs.first is List &&
            (posArgs.first as List).isNotEmpty) {
          final list = posArgs.first as List;
          return list[_rng.nextInt(list.length)];
        }
        return null;
      case 'renpy.seen_label':
        if (posArgs.isNotEmpty) {
          return seenLabels.contains(posArgs.first?.toString());
        }
        return false;
      case 'renpy.has_label':
        if (posArgs.isNotEmpty) {
          return knownLabels.contains(posArgs.first?.toString());
        }
        return false;
    }

    return null;
  }

  /// Formats a Ren'Py dialogue or choice string by interpolating `[var]`
  /// expressions against [store] and stripping text tags (`{b}`, `{w}`, etc.).
  String formatText(String raw) {
    var out = raw
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\n', '\n')
        .replaceAll('%%', '%');

    // Interpolate `[variable]` (ignoring escaped `[[`)
    out = out.replaceAllMapped(
      RegExp(r'(?<!\[)\[([^\[\]\n]+)\]'),
      (match) {
        final expr = match.group(1)!.split('!').first.split(':').first.trim();
        final val = evaluate(expr);
        if (val is RenpyCharacter) return val.name ?? '';
        if (val != null) return val.toString();
        return match.group(0)!;
      },
    );
    out = out.replaceAll('[[', '[').replaceAll(']]', ']');

    // Strip Ren'Py text tags like {b}, {/b}, {w=0.5}, {color=#ff0000}, {nw}
    out = out.replaceAll(RegExp(r'\{/?[a-zA-Z0-9_=#\.\+\-\s,\*\/:%]*\}'), '');
    return out.trim();
  }

  static String _cleanVarName(String raw) {
    var s = raw.trim();
    if (s.startsWith('store.')) {
      s = s.substring(6);
    }
    return s;
  }

  static int _indentOf(String line) {
    int count = 0;
    for (int i = 0; i < line.length; i++) {
      if (line.codeUnitAt(i) == 0x20) {
        count += 1;
      } else if (line.codeUnitAt(i) == 0x09) {
        count += 4;
      } else {
        break;
      }
    }
    return count;
  }

  static String _stripInlineComment(String line) {
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
        if (ch == '"' || ch == "'") {
          quote = ch;
        } else if (ch == '#') {
          return line.substring(0, i);
        }
      }
    }
    return line;
  }

  static bool _isWrappedByOuterParens(String s) {
    int depth = 0;
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
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0 && i < s.length - 1) return false;
      }
    }
    return depth == 0;
  }

  static bool _isBalancedCall(String s, int fnNameLen) {
    int i = fnNameLen;
    while (i < s.length && s[i] != '(') {
      i++;
    }
    if (i >= s.length) return false;
    return _isWrappedByOuterParens(s.substring(i));
  }

  static List<String>? _splitTernary(String expr) {
    final ifParts = _splitTopLevelKeyword(expr, 'if');
    if (ifParts.length == 2) {
      final elseParts = _splitTopLevelKeyword(ifParts[1], 'else');
      if (elseParts.length == 2) {
        return <String>[ifParts[0], elseParts[0], elseParts[1]];
      }
    }
    return null;
  }

  static List<String> _splitTopLevelKeyword(String expr, String kw) {
    final result = <String>[];
    int depth = 0;
    String? quote;
    bool escaped = false;
    int lastStart = 0;

    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (expr.startsWith(quote, i)) {
          i += quote.length - 1;
          quote = null;
        }
        continue;
      }
      if (expr.startsWith('"""', i) || expr.startsWith("'''", i)) {
        quote = expr.substring(i, i + 3);
        i += 2;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
        continue;
      }
      if (ch == ')' || ch == ']' || ch == '}') {
        depth--;
        continue;
      }
      if (depth == 0 && expr.startsWith(kw, i)) {
        final beforeOk = i == 0 || !_isIdentChar(expr.codeUnitAt(i - 1));
        final afterIdx = i + kw.length;
        final afterOk =
            afterIdx >= expr.length || !_isIdentChar(expr.codeUnitAt(afterIdx));
        if (beforeOk && afterOk) {
          result.add(expr.substring(lastStart, i).trim());
          i = afterIdx - 1;
          lastStart = afterIdx;
        }
      }
    }

    if (result.isEmpty) return <String>[expr];
    result.add(expr.substring(lastStart).trim());
    return result;
  }

  static _BinaryOp? _splitComparison(String expr) {
    const ops = <String>[
      'not in',
      'is not',
      '==',
      '!=',
      '<=',
      '>=',
      '<',
      '>',
      'in',
      'is',
    ];
    int depth = 0;
    String? quote;
    bool escaped = false;

    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (expr.startsWith(quote, i)) {
          i += quote.length - 1;
          quote = null;
        }
        continue;
      }
      if (expr.startsWith('"""', i) || expr.startsWith("'''", i)) {
        quote = expr.substring(i, i + 3);
        i += 2;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
        continue;
      }
      if (ch == ')' || ch == ']' || ch == '}') {
        depth--;
        continue;
      }
      if (depth == 0) {
        for (final op in ops) {
          if (expr.startsWith(op, i)) {
            if (op == 'in' ||
                op == 'is' ||
                op == 'not in' ||
                op == 'is not') {
              final beforeOk = i > 0 && !_isIdentChar(expr.codeUnitAt(i - 1));
              final afterIdx = i + op.length;
              final afterOk = afterIdx < expr.length &&
                  !_isIdentChar(expr.codeUnitAt(afterIdx));
              if (!beforeOk || !afterOk) continue;
            }
            return _BinaryOp(
              expr.substring(0, i).trim(),
              op,
              expr.substring(i + op.length).trim(),
            );
          }
        }
      }
    }
    return null;
  }

  static bool _compare(dynamic a, String op, dynamic b) {
    switch (op) {
      case '==':
      case 'is':
        return a == b;
      case '!=':
      case 'is not':
        return a != b;
      case '<':
        if (a is num && b is num) return a < b;
        return a.toString().compareTo(b.toString()) < 0;
      case '<=':
        if (a is num && b is num) return a <= b;
        return a.toString().compareTo(b.toString()) <= 0;
      case '>':
        if (a is num && b is num) return a > b;
        return a.toString().compareTo(b.toString()) > 0;
      case '>=':
        if (a is num && b is num) return a >= b;
        return a.toString().compareTo(b.toString()) >= 0;
      case 'in':
        if (b is Iterable) return b.contains(a);
        if (b is Map) return b.containsKey(a);
        if (b is String && a is String) return b.contains(a);
        return false;
      case 'not in':
        return !_compare(a, 'in', b);
    }
    return false;
  }

  static _BinaryOp? _splitTopLevelAddSub(String expr) {
    int depth = 0;
    String? quote;
    bool escaped = false;
    int splitIdx = -1;
    String? splitOp;

    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (expr.startsWith(quote, i)) {
          i += quote.length - 1;
          quote = null;
        }
        continue;
      }
      if (expr.startsWith('"""', i) || expr.startsWith("'''", i)) {
        quote = expr.substring(i, i + 3);
        i += 2;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
        continue;
      }
      if (ch == ')' || ch == ']' || ch == '}') {
        depth--;
        continue;
      }
      if (depth == 0 && i > 0 && (ch == '+' || ch == '-')) {
        splitIdx = i;
        splitOp = ch;
      }
    }

    if (splitIdx > 0 && splitOp != null) {
      final left = expr.substring(0, splitIdx).trim();
      final right = expr.substring(splitIdx + 1).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        return _BinaryOp(left, splitOp, right);
      }
    }
    return null;
  }

  static _BinaryOp? _splitTopLevelMulDiv(String expr) {
    int depth = 0;
    String? quote;
    bool escaped = false;
    int splitIdx = -1;
    String? splitOp;

    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (expr.startsWith(quote, i)) {
          i += quote.length - 1;
          quote = null;
        }
        continue;
      }
      if (expr.startsWith('"""', i) || expr.startsWith("'''", i)) {
        quote = expr.substring(i, i + 3);
        i += 2;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
        continue;
      }
      if (ch == ')' || ch == ']' || ch == '}') {
        depth--;
        continue;
      }
      if (depth == 0 && i > 0) {
        if (expr.startsWith('//', i)) {
          splitIdx = i;
          splitOp = '//';
          i++;
        } else if (ch == '*' || ch == '/' || ch == '%') {
          splitIdx = i;
          splitOp = ch;
        }
      }
    }

    if (splitIdx > 0 && splitOp != null) {
      final left = expr.substring(0, splitIdx).trim();
      final right = expr.substring(splitIdx + splitOp.length).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        return _BinaryOp(left, splitOp, right);
      }
    }
    return null;
  }

  static String? _tryParseStringLiteral(String expr) {
    var s = expr;
    bool raw = false;
    if ((s.startsWith('r"') ||
            s.startsWith("r'") ||
            s.startsWith('u"') ||
            s.startsWith("u'")) &&
        s.length >= 3) {
      raw = s.startsWith('r');
      s = s.substring(1);
    }
    String? quote;
    if (s.startsWith('"""') && s.endsWith('"""') && s.length >= 6) {
      quote = '"""';
    } else if (s.startsWith("'''") && s.endsWith("'''") && s.length >= 6) {
      quote = "'''";
    } else if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      quote = '"';
    } else if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) {
      quote = "'";
    }
    if (quote == null) return null;

    // Make sure the opening quote doesn't close before the end of `s`
    int i = quote.length;
    final sb = StringBuffer();
    while (i <= s.length - quote.length) {
      if (s.startsWith(quote, i)) {
        if (i == s.length - quote.length) {
          return sb.toString();
        }
        return null; // Closed early (e.g. `"a" + "b"`)
      }
      if (!raw && s[i] == r'\' && i + 1 < s.length - quote.length) {
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
      sb.write(s[i]);
      i++;
    }
    return null;
  }

  static List<String> _splitTopLevelArgs(String s) {
    final result = <String>[];
    int depth = 0;
    String? quote;
    bool escaped = false;
    int start = 0;

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
      if (s.startsWith('"""', i) || s.startsWith("'''", i)) {
        quote = s.substring(i, i + 3);
        i += 2;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') depth++;
      if (ch == ')' || ch == ']' || ch == '}') depth--;
      if (depth == 0 && ch == ',') {
        final item = s.substring(start, i).trim();
        if (item.isNotEmpty) result.add(item);
        start = i + 1;
      }
    }

    final tail = s.substring(start).trim();
    if (tail.isNotEmpty) result.add(tail);
    return result;
  }

  static int _findTopLevelChar(String s, String target) {
    int depth = 0;
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
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') depth++;
      if (ch == ')' || ch == ']' || ch == '}') depth--;
      if (depth == 0 && ch == target) return i;
    }
    return -1;
  }

  static int _findKeywordEquals(String arg) {
    int depth = 0;
    String? quote;
    bool escaped = false;
    for (int i = 0; i < arg.length; i++) {
      final ch = arg[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') depth++;
      if (ch == ')' || ch == ']' || ch == '}') depth--;
      if (depth == 0 && ch == '=') {
        final prev = i > 0 ? arg[i - 1] : '';
        final next = i + 1 < arg.length ? arg[i + 1] : '';
        if (prev != '=' &&
            prev != '!' &&
            prev != '<' &&
            prev != '>' &&
            next != '=') {
          final key = arg.substring(0, i).trim();
          if (RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(key)) {
            return i;
          }
        }
      }
    }
    return -1;
  }

  static bool _isIdentChar(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        codeUnit == 0x5f;
  }
}

class _BinaryOp {
  const _BinaryOp(this.left, this.op, this.right);

  final String left;
  final String op;
  final String right;
}
