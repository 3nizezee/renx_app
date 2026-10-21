import 'dart:convert';
import 'dart:typed_data';

/// Represents a reconstructed Python object from a pickle stream whose class
/// is not a primitive Dart type (for example `renpy.ast.Say` or
/// `renpy.ast.PyExpr`).
class PyObject {
  PyObject(this.klass, {List<dynamic>? args, this.state})
      : args = args ?? <dynamic>[];

  /// Full `module.ClassName` identifier.
  final String klass;

  /// Positional arguments passed to `__new__` / callable constructor.
  final List<dynamic> args;

  /// State passed to `BUILD` (`__setstate__`). Usually a `Map`, a 2-element
  /// `List` `[slotDict, stateDict]`, or a tuple.
  dynamic state;

  Map<String, dynamic>? _cachedFields;

  /// Helper that returns a unified field map regardless of whether the pickle
  /// stored fields in a dict, a `(None, dict)` tuple, or positional args.
  Map<String, dynamic> get fields {
    if (_cachedFields != null) return _cachedFields!;
    final result = <String, dynamic>{};
    if (state is Map) {
      for (final entry in (state as Map).entries) {
        result[entry.key.toString()] = entry.value;
      }
    } else if (state is List) {
      for (final item in state as List) {
        if (item is Map) {
          for (final entry in item.entries) {
            result[entry.key.toString()] = entry.value;
          }
        }
      }
    }
    _cachedFields = result;
    return result;
  }

  dynamic operator [](String key) => fields[key];

  @override
  String toString() => 'PyObject($klass)';
}

/// Sentinel placed on the operand stack by the `MARK` opcode.
class _Mark {
  const _Mark();
}

const _mark = _Mark();

/// Represents a global class or callable reference (`module.name`).
class PyClassRef {
  const PyClassRef(this.module, this.name);

  final String module;
  final String name;

  String get fullName => module.isEmpty ? name : '$module.$name';

  @override
  String toString() => 'PyClassRef($fullName)';
}

/// Pure Dart decoder for Python pickle streams (Protocols 0 through 5).
/// Specifically handles CPython 2.7 and 3.x pickles produced by Ren'Py 6, 7,
/// and 8 when saving `.rpyc` AST structures and `.rpa` archive indices.
class PickleDecoder {
  PickleDecoder(Uint8List bytes)
      : _bytes = bytes,
        _view = ByteData.sublistView(bytes);

  final Uint8List _bytes;
  final ByteData _view;
  int _pos = 0;

  final List<dynamic> _stack = <dynamic>[];
  final Map<int, dynamic> _memo = <int, dynamic>{};
  int _nextMemoId = 0;

  dynamic _pop() => _stack.isNotEmpty ? _stack.removeLast() : null;
  dynamic get _top => _stack.isNotEmpty ? _stack.last : null;

  dynamic decode() {
    final len = _bytes.length;
    while (_pos < len) {
      final op = _bytes[_pos++];
      if (op == 0x2e) {
        // '.' STOP
        break;
      }
      _dispatch(op);
    }
    return _stack.isNotEmpty ? _stack.last : null;
  }

  void _dispatch(int op) {
    switch (op) {
      case 0x80: // PROTO
        if (_pos < _bytes.length) _pos += 1;
        break;

      case 0x95: // FRAME (Protocol 4+) - 8 byte frame length, data follows inline
        if (_pos + 8 <= _bytes.length) {
          _pos += 8;
        } else {
          _pos = _bytes.length;
        }
        break;

      case 0x28: // '(' MARK
        _stack.add(_mark);
        break;

      case 0x30: // '0' POP
        _pop();
        break;

      case 0x31: // '1' POP_MARK
        _popToMark();
        break;

      case 0x32: // '2' DUP
        if (_stack.isNotEmpty) _stack.add(_stack.last);
        break;

      case 0x4e: // 'N' NONE
        _stack.add(null);
        break;

      case 0x88: // NEWTRUE
        _stack.add(true);
        break;

      case 0x89: // NEWFALSE
        _stack.add(false);
        break;

      case 0x49: // 'I' INT (newline-terminated ASCII)
        final s = _readLine();
        if (s == '00') {
          _stack.add(false);
        } else if (s == '01') {
          _stack.add(true);
        } else {
          _stack.add(int.tryParse(s) ?? 0);
        }
        break;

      case 0x4a: // 'J' BININT (signed 32-bit LE)
        if (_pos + 4 <= _bytes.length) {
          final v = _view.getInt32(_pos, Endian.little);
          _pos += 4;
          _stack.add(v);
        } else {
          _pos = _bytes.length;
          _stack.add(0);
        }
        break;

      case 0x4b: // 'K' BININT1 (unsigned 8-bit)
        _stack.add(_pos < _bytes.length ? _bytes[_pos++] : 0);
        break;

      case 0x4d: // 'M' BININT2 (unsigned 16-bit LE)
        if (_pos + 2 <= _bytes.length) {
          final v = _view.getUint16(_pos, Endian.little);
          _pos += 2;
          _stack.add(v);
        } else {
          _pos = _bytes.length;
          _stack.add(0);
        }
        break;

      case 0x4c: // 'L' LONG (newline-terminated ASCII, possibly trailing 'L')
        var s = _readLine();
        if (s.endsWith('L') || s.endsWith('l')) {
          s = s.substring(0, s.length - 1);
        }
        _stack.add(int.tryParse(s) ?? BigInt.tryParse(s)?.toInt() ?? 0);
        break;

      case 0x8a: // LONG1 (1-byte length, signed little-endian integer)
        final n = _pos < _bytes.length ? _bytes[_pos++] : 0;
        _stack.add(_readSignedLeInt(n));
        break;

      case 0x8b: // LONG4 (4-byte length, signed little-endian integer)
        if (_pos + 4 <= _bytes.length) {
          final n = _view.getInt32(_pos, Endian.little);
          _pos += 4;
          _stack.add(_readSignedLeInt(n));
        } else {
          _pos = _bytes.length;
          _stack.add(0);
        }
        break;

      case 0x46: // 'F' FLOAT (newline-terminated ASCII)
        final s = _readLine();
        _stack.add(double.tryParse(s) ?? 0.0);
        break;

      case 0x47: // 'G' BINFLOAT (64-bit big-endian IEEE 754)
        if (_pos + 8 <= _bytes.length) {
          final v = _view.getFloat64(_pos, Endian.big);
          _pos += 8;
          _stack.add(v);
        } else {
          _pos = _bytes.length;
          _stack.add(0.0);
        }
        break;

      case 0x53: // 'S' STRING (newline-terminated quoted string)
        final raw = _readLine();
        _stack.add(_unescapeQuotedString(raw));
        break;

      case 0x54: // 'T' BINSTRING (4-byte length LE)
        if (_pos + 4 <= _bytes.length) {
          final len = _view.getInt32(_pos, Endian.little);
          _pos += 4;
          _stack.add(_readStringBytes(len));
        } else {
          _pos = _bytes.length;
          _stack.add('');
        }
        break;

      case 0x55: // 'U' SHORT_BINSTRING (1-byte length)
        final len = _pos < _bytes.length ? _bytes[_pos++] : 0;
        _stack.add(_readStringBytes(len));
        break;

      case 0x56: // 'V' UNICODE (newline-terminated raw-unicode-escape)
        final raw = _readLine();
        _stack.add(_unescapeQuotedString(raw));
        break;

      case 0x58: // 'X' BINUNICODE (4-byte length LE, UTF-8)
        if (_pos + 4 <= _bytes.length) {
          final len = _view.getUint32(_pos, Endian.little);
          _pos += 4;
          _stack.add(_readUtf8(len));
        } else {
          _pos = _bytes.length;
          _stack.add('');
        }
        break;

      case 0x8c: // SHORT_BINUNICODE (1-byte length, UTF-8)
        final len = _pos < _bytes.length ? _bytes[_pos++] : 0;
        _stack.add(_readUtf8(len));
        break;

      case 0x8d: // BINUNICODE8 (8-byte length LE, UTF-8)
        final len = _readUint64Le();
        _stack.add(_readUtf8(len));
        break;

      case 0x42: // 'B' BINBYTES (4-byte length LE)
        if (_pos + 4 <= _bytes.length) {
          final len = _view.getUint32(_pos, Endian.little);
          _pos += 4;
          _stack.add(_readRawBytes(len));
        } else {
          _pos = _bytes.length;
          _stack.add(Uint8List(0));
        }
        break;

      case 0x43: // 'C' SHORT_BINBYTES (1-byte length)
        final len = _pos < _bytes.length ? _bytes[_pos++] : 0;
        _stack.add(_readRawBytes(len));
        break;

      case 0x8e: // BINBYTES8 (8-byte length LE)
        final len = _readUint64Le();
        _stack.add(_readRawBytes(len));
        break;

      case 0x96: // BYTEARRAY8 (8-byte length LE)
        final len = _readUint64Le();
        _stack.add(_readRawBytes(len));
        break;

      case 0x29: // ')' EMPTY_TUPLE
        _stack.add(<dynamic>[]);
        break;

      case 0x85: // TUPLE1
        final a = _pop();
        _stack.add(<dynamic>[a]);
        break;

      case 0x86: // TUPLE2
        final b = _pop();
        final a = _pop();
        _stack.add(<dynamic>[a, b]);
        break;

      case 0x87: // TUPLE3
        final c = _pop();
        final b = _pop();
        final a = _pop();
        _stack.add(<dynamic>[a, b, c]);
        break;

      case 0x74: // 't' TUPLE
        _stack.add(_popToMark());
        break;

      case 0x5d: // ']' EMPTY_LIST
        _stack.add(<dynamic>[]);
        break;

      case 0x6c: // 'l' LIST
        _stack.add(_popToMark());
        break;

      case 0x61: // 'a' APPEND
        final item = _pop();
        final target = _top;
        if (target is List) {
          target.add(item);
        } else if (target is PyObject) {
          target.args.add(item);
        }
        break;

      case 0x65: // 'e' APPENDS
        final items = _popToMark();
        final target = _top;
        if (target is List) {
          target.addAll(items);
        } else if (target is PyObject) {
          target.args.addAll(items);
        }
        break;

      case 0x7d: // '}' EMPTY_DICT
        _stack.add(<dynamic, dynamic>{});
        break;

      case 0x64: // 'd' DICT
        final items = _popToMark();
        final map = <dynamic, dynamic>{};
        for (int i = 0; i + 1 < items.length; i += 2) {
          map[items[i]] = items[i + 1];
        }
        _stack.add(map);
        break;

      case 0x73: // 's' SETITEM
        final val = _pop();
        final key = _pop();
        final target = _top;
        if (target is Map) {
          target[key] = val;
        } else if (target is PyObject) {
          final m = target.state is Map
              ? (target.state as Map)
              : <dynamic, dynamic>{};
          m[key] = val;
          target.state = m;
          target._cachedFields = null;
        }
        break;

      case 0x75: // 'u' SETITEMS
        final items = _popToMark();
        final target = _top;
        if (target is Map) {
          for (int i = 0; i + 1 < items.length; i += 2) {
            target[items[i]] = items[i + 1];
          }
        } else if (target is PyObject) {
          final m = target.state is Map
              ? (target.state as Map)
              : <dynamic, dynamic>{};
          for (int i = 0; i + 1 < items.length; i += 2) {
            m[items[i]] = items[i + 1];
          }
          target.state = m;
          target._cachedFields = null;
        }
        break;

      case 0x8f: // EMPTY_SET
        _stack.add(<dynamic>{});
        break;

      case 0x90: // ADDITEMS
        final items = _popToMark();
        final target = _top;
        if (target is Set) {
          target.addAll(items);
        } else if (target is List) {
          target.addAll(items);
        }
        break;

      case 0x91: // FROZENSET
        final items = _popToMark();
        _stack.add(items.toSet());
        break;

      case 0x63: // 'c' GLOBAL (module\nname\n)
        final module = _readLine();
        final name = _readLine();
        _stack.add(PyClassRef(module, name));
        break;

      case 0x93: // STACK_GLOBAL
        final name = _pop()?.toString() ?? '';
        final module = _pop()?.toString() ?? '';
        _stack.add(PyClassRef(module, name));
        break;

      case 0x52: // 'R' REDUCE
        final args = _pop();
        final callable = _pop();
        _stack.add(
          _instantiate(callable, args is List ? args : <dynamic>[args]),
        );
        break;

      case 0x81: // NEWOBJ
        final args = _pop();
        final cls = _pop();
        _stack.add(_instantiate(cls, args is List ? args : <dynamic>[args]));
        break;

      case 0x92: // NEWOBJ_EX
        final kwargs = _pop();
        final args = _pop();
        final cls = _pop();
        final obj = _instantiate(cls, args is List ? args : <dynamic>[args]);
        if (obj is PyObject && kwargs is Map && kwargs.isNotEmpty) {
          obj.state = kwargs;
          obj._cachedFields = null;
        }
        _stack.add(obj);
        break;

      case 0x69: // 'i' INST (module\nname\n, args on stack after MARK)
        final module = _readLine();
        final name = _readLine();
        final args = _popToMark();
        _stack.add(_instantiate(PyClassRef(module, name), args));
        break;

      case 0x6f: // 'o' OBJ (stack after MARK: [cls, ...args])
        final items = _popToMark();
        if (items.isNotEmpty) {
          final cls = items.first;
          final args = items.sublist(1);
          _stack.add(_instantiate(cls, args));
        } else {
          _stack.add(null);
        }
        break;

      case 0x62: // 'b' BUILD
        final state = _pop();
        final target = _top;
        if (target is PyObject) {
          target._cachedFields = null;
          if (target.state == null) {
            target.state = state;
          } else if (target.state is Map && state is Map) {
            (target.state as Map).addAll(state);
          } else {
            target.state = <dynamic>[target.state, state];
          }
        }
        break;

      case 0x67: // 'g' GET (newline-terminated decimal memo index)
        final idx = int.tryParse(_readLine()) ?? 0;
        _stack.add(_memo[idx]);
        break;

      case 0x68: // 'h' BINGET (1-byte memo index)
        final idx = _pos < _bytes.length ? _bytes[_pos++] : 0;
        _stack.add(_memo[idx]);
        break;

      case 0x6a: // 'j' LONG_BINGET (4-byte LE memo index)
        if (_pos + 4 <= _bytes.length) {
          final idx = _view.getUint32(_pos, Endian.little);
          _pos += 4;
          _stack.add(_memo[idx]);
        } else {
          _pos = _bytes.length;
          _stack.add(null);
        }
        break;

      case 0x70: // 'p' PUT (newline-terminated decimal memo index)
        final idx = int.tryParse(_readLine()) ?? 0;
        if (_stack.isNotEmpty) {
          _memo[idx] = _stack.last;
          if (idx >= _nextMemoId) _nextMemoId = idx + 1;
        }
        break;

      case 0x71: // 'q' BINPUT (1-byte memo index)
        final idx = _pos < _bytes.length ? _bytes[_pos++] : 0;
        if (_stack.isNotEmpty) {
          _memo[idx] = _stack.last;
          if (idx >= _nextMemoId) _nextMemoId = idx + 1;
        }
        break;

      case 0x72: // 'r' LONG_BINPUT (4-byte LE memo index)
        if (_pos + 4 <= _bytes.length) {
          final idx = _view.getUint32(_pos, Endian.little);
          _pos += 4;
          if (_stack.isNotEmpty) {
            _memo[idx] = _stack.last;
            if (idx >= _nextMemoId) _nextMemoId = idx + 1;
          }
        } else {
          _pos = _bytes.length;
        }
        break;

      case 0x94: // MEMOIZE
        if (_stack.isNotEmpty) {
          _memo[_nextMemoId++] = _stack.last;
        }
        break;

      case 0x82: // EXT1
        if (_pos < _bytes.length) _pos += 1;
        _stack.add(null);
        break;

      case 0x83: // EXT2
        if (_pos + 2 <= _bytes.length) _pos += 2;
        _stack.add(null);
        break;

      case 0x84: // EXT4
        if (_pos + 4 <= _bytes.length) _pos += 4;
        _stack.add(null);
        break;

      case 0x50: // 'P' PERSID
        _stack.add(_readLine());
        break;

      case 0x51: // 'Q' BINPERSID
        break;

      case 0x97: // NEXT_BUFFER (Protocol 5)
      case 0x98: // READONLY_BUFFER (Protocol 5)
        break;

      default:
        // Unknown opcode: stop decoding cleanly rather than crashing
        _pos = _bytes.length;
        break;
    }
  }

  dynamic _instantiate(dynamic callable, List<dynamic> args) {
    if (callable is PyClassRef) {
      final full = callable.fullName;
      if (full == '__builtin__.set' ||
          full == 'builtins.set' ||
          full == '__builtin__.frozenset' ||
          full == 'builtins.frozenset' ||
          full.endsWith('RevertableSet')) {
        if (args.isNotEmpty && args.first is Iterable) {
          return (args.first as Iterable).toSet();
        }
        return <dynamic>{};
      }
      if (full == '__builtin__.unicode' ||
          full == '__builtin__.str' ||
          full == 'builtins.str') {
        return args.isNotEmpty ? (args.first?.toString() ?? '') : '';
      }
      if (full == '_codecs.encode' || full == 'codecs.encode') {
        if (args.isNotEmpty) {
          final s = args.first.toString();
          return Uint8List.fromList(latin1.encode(s));
        }
      }
      if (full == 'copy_reg._reconstructor' ||
          full == 'copyreg._reconstructor') {
        if (args.isNotEmpty) {
          final innerCls = args.first;
          // In Python 2/3, _reconstructor(cls, base, state) passes the base
          // class at args[1] and the primitive value (e.g. string for PyExpr)
          // at args[2]. Strip `base` if it is a PyClassRef so `innerArgs.first`
          // is the actual primitive value.
          List<dynamic> innerArgs;
          if (args.length >= 3 && args[1] is PyClassRef) {
            innerArgs = args.sublist(2);
          } else if (args.length == 2 &&
              args[1] is PyClassRef &&
              (args[1] as PyClassRef).name == 'object') {
            innerArgs = <dynamic>[];
          } else {
            innerArgs = args.length > 1 ? args.sublist(1) : <dynamic>[];
          }
          return _instantiate(innerCls, innerArgs);
        }
      }
      if (full == '__builtin__.object' || full == 'builtins.object') {
        return PyObject('object', args: args);
      }
      if (full.endsWith('RevertableDict') ||
          full == 'collections.OrderedDict' ||
          full == 'collections.defaultdict') {
        final map = <dynamic, dynamic>{};
        if (args.isNotEmpty && args.first is List) {
          for (final pair in args.first as List) {
            if (pair is List && pair.length >= 2) {
              map[pair[0]] = pair[1];
            }
          }
        }
        return map;
      }
      if (full.endsWith('RevertableList')) {
        if (args.isNotEmpty && args.first is List) {
          return List<dynamic>.from(args.first as List);
        }
        return <dynamic>[];
      }
      return PyObject(full, args: args);
    }
    if (callable is PyObject) {
      return PyObject(callable.klass, args: args, state: callable.state);
    }
    return PyObject(callable?.toString() ?? 'unknown', args: args);
  }

  List<dynamic> _popToMark() {
    final items = <dynamic>[];
    while (_stack.isNotEmpty) {
      final top = _stack.removeLast();
      if (identical(top, _mark)) {
        break;
      }
      items.add(top);
    }
    return items.reversed.toList();
  }

  String _readLine() {
    final start = _pos;
    final len = _bytes.length;
    while (_pos < len && _bytes[_pos] != 0x0a) {
      _pos++;
    }
    final end = _pos;
    if (_pos < len && _bytes[_pos] == 0x0a) {
      _pos++;
    }
    final trimmedEnd =
        (end > start && _bytes[end - 1] == 0x0d) ? end - 1 : end;
    return latin1.decode(Uint8List.sublistView(_bytes, start, trimmedEnd));
  }

  String _readUtf8(int len) {
    if (len <= 0) return '';
    final end = (_pos + len).clamp(0, _bytes.length);
    final slice = Uint8List.sublistView(_bytes, _pos, end);
    _pos = end;
    return utf8.decode(slice, allowMalformed: true);
  }

  /// Fast non-throwing decoder for Python 2 `BINSTRING` / `SHORT_BINSTRING`.
  /// Avoids throwing `FormatException` on binary bytecode blobs.
  String _readStringBytes(int len) {
    if (len <= 0) return '';
    final end = (_pos + len).clamp(0, _bytes.length);
    final slice = Uint8List.sublistView(_bytes, _pos, end);
    _pos = end;

    bool hasHighBytes = false;
    for (int i = 0; i < slice.length; i++) {
      if (slice[i] >= 0x80) {
        hasHighBytes = true;
        break;
      }
    }
    if (!hasHighBytes) {
      return latin1.decode(slice);
    }
    return utf8.decode(slice, allowMalformed: true);
  }

  Uint8List _readRawBytes(int len) {
    if (len <= 0) return Uint8List(0);
    final end = (_pos + len).clamp(0, _bytes.length);
    final slice = Uint8List.sublistView(_bytes, _pos, end);
    _pos = end;
    return slice;
  }

  int _readUint64Le() {
    if (_pos + 8 > _bytes.length) {
      _pos = _bytes.length;
      return 0;
    }
    final lo = _view.getUint32(_pos, Endian.little);
    final hi = _view.getUint32(_pos + 4, Endian.little);
    _pos += 8;
    return (hi * 0x100000000) + lo;
  }

  int _readSignedLeInt(int byteCount) {
    if (byteCount <= 0 || _pos >= _bytes.length) return 0;
    final end = (_pos + byteCount).clamp(0, _bytes.length);
    final slice = Uint8List.sublistView(_bytes, _pos, end);
    _pos = end;
    if (slice.isEmpty) return 0;

    if (slice.length <= 6) {
      int result = 0;
      for (int i = slice.length - 1; i >= 0; i--) {
        result = (result << 8) | slice[i];
      }
      if ((slice.last & 0x80) != 0) {
        result -= 1 << (slice.length * 8);
      }
      return result;
    }

    BigInt result = BigInt.zero;
    for (int i = slice.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(slice[i]);
    }
    if ((slice.last & 0x80) != 0) {
      result -= BigInt.one << (slice.length * 8);
    }
    return result.toInt();
  }

  String _unescapeQuotedString(String raw) {
    var s = raw;
    if (s.length >= 2 &&
        ((s.startsWith("'") && s.endsWith("'")) ||
            (s.startsWith('"') && s.endsWith('"')))) {
      s = s.substring(1, s.length - 1);
    }
    if (!s.contains(r'\')) return s;

    final sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == r'\' && i + 1 < s.length) {
        final next = s[++i];
        switch (next) {
          case 'n':
            sb.write('\n');
            break;
          case 'r':
            sb.write('\r');
            break;
          case 't':
            sb.write('\t');
            break;
          case r'\':
            sb.write(r'\');
            break;
          case "'":
            sb.write("'");
            break;
          case '"':
            sb.write('"');
            break;
          case 'x':
            if (i + 2 < s.length) {
              final hex = s.substring(i + 1, i + 3);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) {
                sb.writeCharCode(code);
                i += 2;
                break;
              }
            }
            sb.write(next);
            break;
          case 'u':
            if (i + 4 < s.length) {
              final hex = s.substring(i + 1, i + 5);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) {
                sb.writeCharCode(code);
                i += 4;
                break;
              }
            }
            sb.write(next);
            break;
          default:
            sb.write(next);
        }
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }
}
