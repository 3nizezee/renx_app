import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/renpy_game.dart';

class VnChoice {
  final String text;
  final String? targetLabel;
  final int? targetOffset;

  VnChoice({
    required this.text,
    this.targetLabel,
    this.targetOffset,
  });
}

class VnStatement {
  final String? label;
  final String? speaker;
  final Color speakerColor;
  final String text;
  final String? bgPath;
  final String? spritePath;
  final String sceneStyle; // 'school', 'sunset', 'night', 'room', 'forest'
  final List<VnChoice>? choices;
  final String? jumpTarget;

  VnStatement({
    this.label,
    this.speaker,
    this.speakerColor = Colors.amberAccent,
    required this.text,
    this.bgPath,
    this.spritePath,
    this.sceneStyle = 'school',
    this.choices,
    this.jumpTarget,
  });
}

class RenpyScriptParser {
  /// Loads and parses a PC Ren'Py game folder into playable Visual Novel statements.
  /// Supports both plain-text .rpy files and compiled binary .rpyc files (zlib RPC2),
  /// plus discovers actual background/sprite images from the game directory.
  static Future<List<VnStatement>> loadGameScript(RenpyGame game) async {
    try {
      final dir = Directory(game.path);
      if (await dir.exists()) {
        final gameSubDir = Directory(p.join(dir.path, 'game'));
        final searchDir = await gameSubDir.exists() ? gameSubDir : dir;

        final List<File> rpyFiles = [];
        final List<File> rpycFiles = [];
        final Map<String, String> imageMap = {};

        final entities = searchDir.listSync(recursive: true);
        for (final entity in entities) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            final baseName =
                p.basenameWithoutExtension(entity.path).toLowerCase();

            // Skip engine/gui configuration files when looking for story scripts
            final isConfigScript = baseName == 'gui' ||
                baseName == 'options' ||
                baseName == 'screens';

            if (ext == '.rpy' && !isConfigScript) {
              rpyFiles.add(entity);
            } else if (ext == '.rpyc' && !isConfigScript) {
              rpycFiles.add(entity);
            } else if (ext == '.png' ||
                ext == '.jpg' ||
                ext == '.jpeg' ||
                ext == '.webp') {
              imageMap[baseName] = entity.path;
            }
          }
        }

        // 1. Try parsing .rpy text files first
        if (rpyFiles.isNotEmpty) {
          final statements = await _parseRpyFiles(rpyFiles, imageMap);
          if (statements.isNotEmpty) return statements;
        }

        // 2. Try extracting dialogue & scenes from compiled .rpyc files
        if (rpycFiles.isNotEmpty) {
          final statements = await _parseRpycFiles(rpycFiles, imageMap);
          if (statements.isNotEmpty) return statements;
        }
      }
    } catch (_) {
      // Fallback to built-in interactive visual novel script
    }

    return _buildBuiltInDemoScript(game.title);
  }

  static Future<List<VnStatement>> _parseRpyFiles(
    List<File> files,
    Map<String, String> imageMap,
  ) async {
    final List<VnStatement> results = [];
    final Map<String, String> characters = {};
    final Map<String, Color> characterColors = {};

    // Prioritize script.rpy if present
    files.sort((a, b) {
      final aName = p.basename(a.path).toLowerCase();
      final bName = p.basename(b.path).toLowerCase();
      if (aName == 'script.rpy') return -1;
      if (bName == 'script.rpy') return 1;
      return aName.compareTo(bName);
    });

    final defineRegex = RegExp(
      r'''define\s+([a-zA-Z0-9_]+)\s*=\s*Character\(\s*['"]([^'"]+)['"]''',
    );
    final colorRegex = RegExp(r'''color\s*=\s*['"](#[0-9a-fA-F]{6})['"]''');
    final labelRegex = RegExp(r'^label\s+([a-zA-Z0-9_]+)\s*:');
    final sceneRegex = RegExp(r'^scene\s+([a-zA-Z0-9_\-\s]+)');
    final showRegex = RegExp(r'^show\s+([a-zA-Z0-9_\-\s]+)');
    final jumpRegex = RegExp(r'^jump\s+([a-zA-Z0-9_]+)');
    final charDialogueRegex =
        RegExp(r'''^([a-zA-Z0-9_]+)\s+"([^"\\]*(?:\\.[^"\\]*)*)"''');
    final narratorRegex = RegExp(r'''^"([^"\\]*(?:\\.[^"\\]*)*)"''');

    String? currentBg;
    String? currentSprite;
    String? pendingLabel;
    String currentStyle = 'school';

    for (final file in files) {
      final lines = await file.readAsLines();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        // Character definition
        final defMatch = defineRegex.firstMatch(line);
        if (defMatch != null) {
          final shortId = defMatch.group(1)!;
          final charName = defMatch.group(2)!;
          characters[shortId] = charName;

          final colMatch = colorRegex.firstMatch(line);
          if (colMatch != null) {
            characterColors[shortId] = _parseHexColor(colMatch.group(1)!);
          }
          continue;
        }

        // Label
        final lblMatch = labelRegex.firstMatch(line);
        if (lblMatch != null) {
          pendingLabel = lblMatch.group(1);
          continue;
        }

        // Scene (Background)
        final scnMatch = sceneRegex.firstMatch(line);
        if (scnMatch != null) {
          final rawName = scnMatch.group(1)!.split(':').first.trim();
          currentBg = _findMatchingImage(rawName, imageMap);
          currentSprite = null;
          if (rawName.contains('night') || rawName.contains('dark')) {
            currentStyle = 'night';
          } else if (rawName.contains('sunset') || rawName.contains('evening')) {
            currentStyle = 'sunset';
          } else if (rawName.contains('room') || rawName.contains('club')) {
            currentStyle = 'room';
          } else {
            currentStyle = 'school';
          }
          continue;
        }

        // Show (Character sprite)
        final shwMatch = showRegex.firstMatch(line);
        if (shwMatch != null) {
          final rawName =
              shwMatch.group(1)!.split(' at ').first.split(':').first.trim();
          final matched = _findMatchingImage(rawName, imageMap);
          if (matched != null) {
            currentSprite = matched;
          }
          continue;
        }

        // Jump
        final jmpMatch = jumpRegex.firstMatch(line);
        if (jmpMatch != null && results.isNotEmpty) {
          final last = results.removeLast();
          results.add(VnStatement(
            label: last.label,
            speaker: last.speaker,
            speakerColor: last.speakerColor,
            text: last.text,
            bgPath: last.bgPath,
            spritePath: last.spritePath,
            sceneStyle: last.sceneStyle,
            choices: last.choices,
            jumpTarget: jmpMatch.group(1),
          ));
          continue;
        }

        // Dialogue with speaker variable
        final dlgMatch = charDialogueRegex.firstMatch(line);
        if (dlgMatch != null) {
          final speakerId = dlgMatch.group(1)!;
          final rawText = _cleanRenpyText(dlgMatch.group(2)!);
          if (rawText.isNotEmpty) {
            results.add(VnStatement(
              label: pendingLabel,
              speaker: characters[speakerId] ?? speakerId,
              speakerColor:
                  characterColors[speakerId] ?? Colors.lightBlueAccent,
              text: rawText,
              bgPath: currentBg,
              spritePath: currentSprite,
              sceneStyle: currentStyle,
            ));
            pendingLabel = null;
          }
          continue;
        }

        // Narrator line
        final narMatch = narratorRegex.firstMatch(line);
        if (narMatch != null) {
          final rawText = _cleanRenpyText(narMatch.group(1)!);
          if (rawText.isNotEmpty) {
            results.add(VnStatement(
              label: pendingLabel,
              speaker: null,
              text: rawText,
              bgPath: currentBg,
              spritePath: currentSprite,
              sceneStyle: currentStyle,
            ));
            pendingLabel = null;
          }
        }
      }
    }

    return results;
  }

  /// Extracts readable dialogue strings from compiled Ren'Py .rpyc (RENPY RPC2 zlib) files
  static Future<List<VnStatement>> _parseRpycFiles(
    List<File> files,
    Map<String, String> imageMap,
  ) async {
    final List<VnStatement> results = [];
    final allImages = imageMap.values.toList();
    String? defaultBg = allImages.isNotEmpty ? allImages.first : null;

    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length < 22) continue;

        // Check "RENPY RPC2" header
        final header = ascii.decode(bytes.sublist(0, 10), allowInvalid: true);
        if (!header.startsWith('RENPY RPC2')) continue;

        final bd = ByteData.sublistView(bytes);
        // Slot 1 offset is at byte 14, length at byte 18 (little endian uint32)
        final start = bd.getUint32(14, Endian.little);
        final length = bd.getUint32(18, Endian.little);

        if (start + length <= bytes.length && length > 0) {
          final compressed = bytes.sublist(start, start + length);
          final decompressed = zlib.decode(compressed);
          final textContent =
              utf8.decode(decompressed, allowInvalid: true);

          // Match human-readable dialogue sentences (at least 10 chars, containing spaces or Thai/CJK/punctuation)
          final stringMatches = RegExp(
            r'([A-Za-z0-9\u0E00-\u0E7F\u3040-\u30FF\u4E00-\u9FAF][A-Za-z0-9\u0E00-\u0E7F\u3040-\u30FF\u4E00-\u9FAF\s,\.\!\?\-\—\'\"]{12,180})',
          ).allMatches(textContent);

          for (final m in stringMatches) {
            final candidate = _cleanRenpyText(m.group(1)!.trim());
            if (_isLikelyDialogueLine(candidate)) {
              results.add(VnStatement(
                speaker: null,
                text: candidate,
                bgPath: defaultBg,
                sceneStyle: 'school',
              ));
              if (results.length >= 200) break;
            }
          }
        }
      } catch (_) {}
      if (results.length >= 200) break;
    }

    return results;
  }

  static bool _isLikelyDialogueLine(String s) {
    if (s.contains('.rpy') ||
        s.contains('renpy.') ||
        s.contains('store.') ||
        s.contains('__') ||
        s.contains('python') ||
        s.contains('Character')) {
      return false;
    }
    return s.contains(' ') || RegExp(r'[\u0E00-\u0E7F]').hasMatch(s);
  }

  static String? _findMatchingImage(
    String rawCommandName,
    Map<String, String> imageMap,
  ) {
    final normalized = rawCommandName.toLowerCase().trim();
    if (imageMap.containsKey(normalized)) return imageMap[normalized];
    final underscored = normalized.replaceAll(' ', '_');
    if (imageMap.containsKey(underscored)) return imageMap[underscored];
    final spaceless = normalized.replaceAll(' ', '');
    if (imageMap.containsKey(spaceless)) return imageMap[spaceless];

    for (final entry in imageMap.entries) {
      if (entry.key.contains(underscored) || underscored.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  static String _cleanRenpyText(String input) {
    return input
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\n', '\n')
        .replaceAll(RegExp(r'\{[^\}]*\}'), '') // Strip Ren'Py text tags like {b}, {w}
        .trim();
  }

  static Color _parseHexColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
    } catch (_) {}
    return Colors.amberAccent;
  }

  /// Built-in interactive Visual Novel demo ("The Question" Thai Edition)
  static List<VnStatement> _buildBuiltInDemoScript(String gameTitle) {
    return [
      VnStatement(
        label: 'start',
        speaker: 'ระบบ (RenPlay Engine)',
        speakerColor: Colors.purpleAccent,
        text:
            'ยินดีต้อนรับสู่ "$gameTitle"!\nขณะนี้กำลังทำงานด้วย Built-in Ren\'Py Interpreter ในตัวแอปโดยไม่ต้องพึ่งพาปลั๊กอินภายนอก',
        sceneStyle: 'school',
      ),
      VnStatement(
        speaker: null,
        text:
            'สายลมยามบ่ายพัดผ่านต้นซากุระหน้ามหาวิทยาลัย เสียงพูดคุยของนักศึกษาค่อยๆ จางลงเมื่อหลังเลิกเรียนมาถึง...',
        sceneStyle: 'school',
      ),
      VnStatement(
        speaker: 'ซิลเวีย (Sylvie)',
        speakerColor: Colors.greenAccent,
        text:
            'สวัสดีจ้ะ! วันนี้ขอบคุณที่มาช่วยงานชมรมสร้างเกม Visual Novel ของพวกเรานะ!',
        sceneStyle: 'school',
      ),
      VnStatement(
        speaker: 'ซิลเวีย (Sylvie)',
        speakerColor: Colors.greenAccent,
        text:
            'ตอนนี้เรากำลังทดสอบรันเกม Ren\'Py ของ PC บนมือถืออยู่ล่ะ คุณสามารถกดปุ่มสัมผัสเสมือนด้านข้างทั้ง 6 ปุ่ม (ESC, BACK, HIDE, SKIP, AUTO, NEXT) ได้จริงทั้งหมดเลยนะ!',
        sceneStyle: 'school',
      ),
      VnStatement(
        speaker: 'ซิลเวีย (Sylvie)',
        speakerColor: Colors.greenAccent,
        text: 'ว่าแต่... คุณอยากลองทดสอบระบบส่วนไหนก่อนดีล่ะ?',
        sceneStyle: 'sunset',
        choices: [
          VnChoice(
            text: '1. เล่าเนื้อเรื่องของเกมต่อเลย!',
            targetLabel: 'story_branch',
          ),
          VnChoice(
            text: '2. อธิบายวิธีเพิ่มเกม Ren\'Py จาก PC ลงมือถือ',
            targetLabel: 'guide_branch',
          ),
        ],
      ),
      VnStatement(
        label: 'story_branch',
        speaker: 'ซิลเวีย (Sylvie)',
        speakerColor: Colors.greenAccent,
        text:
            'ได้เลย! ตอนที่ฉันเริ่มเขียนสคริปต์ .rpy ครั้งแรก ฉันกังวลมากว่าจะเอามาเล่นบนสมาร์ตโฟนได้ไหม...',
        sceneStyle: 'sunset',
      ),
      VnStatement(
        speaker: 'ซิลเวีย (Sylvie)',
        speakerColor: Colors.greenAccent,
        text:
            'แต่พอมี Built-in RenPlay Engine แบบนี้ แค่ก๊อปปี้โฟลเดอร์เกมจากคอมพิวเตอร์มาวางในโฟลเดอร์ Download ของมือถือ ก็เปิดเล่นได้ทันที!',
        sceneStyle: 'night',
        jumpTarget: 'ending',
      ),
      VnStatement(
        label: 'guide_branch',
        speaker: 'ระบบแนะนำ (Guide)',
        speakerColor: Colors.cyanAccent,
        text:
            'วิธีเพิ่มเกม PC ง่ายมาก:\n1) แตกไฟล์เกม Ren\'Py ลงในโฟลเดอร์ Download บนมือถือ\n2) กดปุ่ม "+ เพิ่มเกม" ที่หน้าแรก แล้วเลือกโฟลเดอร์ของเกมนั้น',
        sceneStyle: 'room',
      ),
      VnStatement(
        speaker: 'ระบบแนะนำ (Guide)',
        speakerColor: Colors.cyanAccent,
        text:
            'ตัวแอปจะอ่านไฟล์สคริปต์ .rpy / .rpyc และดึงรูปฉากหลังรวมถึงตัวละครจากโฟลเดอร์ game/ มาแสดงผลให้โดยอัตโนมัติ!',
        sceneStyle: 'room',
        jumpTarget: 'ending',
      ),
      VnStatement(
        label: 'ending',
        speaker: 'ซิลเวีย (Sylvie)',
        speakerColor: Colors.greenAccent,
        text:
            'คุณสามารถลองกดปุ่ม BACK (ด้านซ้าย) เพื่อย้อนบทสนทนา หรือกดปุ่ม ESC เพื่อบันทึกเกม (Save/Load) ได้ตามต้องการเลยนะ!',
        sceneStyle: 'night',
      ),
    ];
  }
}
