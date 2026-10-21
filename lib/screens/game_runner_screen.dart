import 'dart:async';
import 'package:flutter/material.dart';

import '../engine/game_fs.dart';
import '../engine/renpy_runtime.dart';
import '../models/renpy_game.dart';
import '../services/renpy_bridge.dart';
import '../widgets/virtual_gamepad_overlay.dart';

class GameRunnerScreen extends StatefulWidget {
  final RenpyGame game;
  final Function(int additionalMinutes) onSessionComplete;

  const GameRunnerScreen({
    super.key,
    required this.game,
    required this.onSessionComplete,
  });

  @override
  State<GameRunnerScreen> createState() => _GameRunnerScreenState();
}

class _GameRunnerScreenState extends State<GameRunnerScreen> {
  int _secondsPlayed = 0;
  Timer? _playTimer;
  Timer? _autoSkipTimer;

  double _overlayOpacity = 0.88;
  bool _isPluginInstalled = false;

  bool _isLoading = true;
  String? _loadError;
  GameFileSystem? _fs;
  ScriptLoadResult? _loadResult;
  RenpyRuntime? _runtime;

  Map<int, Map<String, dynamic>> _saveSlots = <int, Map<String, dynamic>>{};

  bool _isUiHidden = false;
  bool _isAutoMode = false;
  bool _isSkipMode = false;

  @override
  void initState() {
    super.initState();
    _startPlayTimer();
    _bootEngine();
  }

  void _startPlayTimer() {
    _playTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _secondsPlayed++;
        });
      }
    });
  }

  Future<void> _bootEngine() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final installed = await RenpyBridge.isPluginInstalled();
    final savedSlots = await RenpyBridge.loadGameSaveSlots(widget.game.id);
    final fs = await GameFileSystem.mount(widget.game.path);

    if (fs == null) {
      if (mounted) {
        setState(() {
          _isPluginInstalled = installed;
          _saveSlots = savedSlots;
          _isLoading = false;
          _loadError =
              'ไม่พบโฟลเดอร์เกมที่ตำแหน่ง:\n${widget.game.path}\nกรุณาตรวจสอบว่าโฟลเดอร์ยังอยู่ในเครื่องและเปิดสิทธิ์เข้าถึงไฟล์แล้ว';
        });
      }
      return;
    }

    final scripts = await fs.loadAllScripts();
    if (scripts.files.isEmpty) {
      if (mounted) {
        setState(() {
          _isPluginInstalled = installed;
          _saveSlots = savedSlots;
          _fs = fs;
          _loadResult = scripts;
          _isLoading = false;
          _loadError = scripts.errors.isNotEmpty
              ? 'ไม่สามารถถอดรหัสไฟล์สคริปต์ของเกมได้:\n${scripts.errors.take(3).join('\n')}'
              : 'ไม่พบไฟล์สคริปต์ .rpyc หรือ .rpy ที่สามารถรันได้ในโฟลเดอร์:\n${fs.gameDirPath}';
        });
      }
      return;
    }

    final runtime = RenpyRuntime(fs: fs, loadResult: scripts);
    final ok = await runtime.initialize();

    if (mounted) {
      setState(() {
        _isPluginInstalled = installed;
        _saveSlots = savedSlots;
        _fs = fs;
        _loadResult = scripts;
        _runtime = runtime;
        _isLoading = false;
        if (!ok) {
          _loadError =
              'สคริปต์ของเกมไม่มีจุดเริ่มต้น (label start) หรือคำสั่งเนื้อเรื่องที่รองรับ';
        }
      });
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _autoSkipTimer?.cancel();
    final minutes = (_secondsPlayed / 60).ceil();
    widget.onSessionComplete(minutes);
    super.dispose();
  }

  Future<void> _advanceDialogue() async {
    if (_isUiHidden) {
      setState(() => _isUiHidden = false);
      return;
    }

    final rt = _runtime;
    if (rt == null) return;

    if (rt.isWaitingForChoice) {
      _stopAutoAndSkip();
      return;
    }

    if (rt.isFinished) {
      _stopAutoAndSkip();
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ถึงจุดสิ้นสุดสคริปต์เนื้อเรื่องแล้ว สามารถกดปุ่ม MENU เพื่อเริ่มใหม่หรือโหลดเซฟ',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    await rt.stepForward();
    if (mounted) {
      setState(() {});
      if (rt.isWaitingForChoice || rt.isFinished) {
        _stopAutoAndSkip();
      }
    }
  }

  Future<void> _selectChoice(int choiceIdx) async {
    _stopAutoAndSkip();
    final rt = _runtime;
    if (rt == null) return;
    await rt.choose(choiceIdx);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _rollbackDialogue() async {
    _stopAutoAndSkip();
    final rt = _runtime;
    if (rt == null) return;

    final ok = await rt.rollback();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _isUiHidden = false;
      });
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('อยู่ที่จุดเริ่มต้นของประวัติการย้อนกลับแล้ว'),
          duration: Duration(milliseconds: 900),
        ),
      );
    }
  }

  void _toggleSkipMode() {
    final rt = _runtime;
    if (rt == null || rt.isWaitingForChoice || rt.isFinished) return;
    setState(() {
      _isSkipMode = !_isSkipMode;
      if (_isSkipMode) {
        _isAutoMode = false;
        _isUiHidden = false;
      }
    });
    _updateAutoSkipTimer();
  }

  void _toggleAutoMode() {
    final rt = _runtime;
    if (rt == null || rt.isWaitingForChoice || rt.isFinished) return;
    setState(() {
      _isAutoMode = !_isAutoMode;
      if (_isAutoMode) {
        _isSkipMode = false;
        _isUiHidden = false;
      }
    });
    _updateAutoSkipTimer();
  }

  void _stopAutoAndSkip() {
    _autoSkipTimer?.cancel();
    if (_isAutoMode || _isSkipMode) {
      setState(() {
        _isAutoMode = false;
        _isSkipMode = false;
      });
    }
  }

  void _updateAutoSkipTimer() {
    _autoSkipTimer?.cancel();
    if (_isSkipMode) {
      _autoSkipTimer =
          Timer.periodic(const Duration(milliseconds: 220), (_) {
        _advanceDialogue();
      });
    } else if (_isAutoMode) {
      _autoSkipTimer =
          Timer.periodic(const Duration(milliseconds: 2400), (_) {
        _advanceDialogue();
      });
    }
  }

  void _handleGamepadAction(String action) {
    switch (action) {
      case 'ENTER':
        _stopAutoAndSkip();
        _advanceDialogue();
        break;
      case 'PAGE_UP':
        _rollbackDialogue();
        break;
      case 'H':
        _stopAutoAndSkip();
        setState(() {
          _isUiHidden = !_isUiHidden;
        });
        break;
      case 'CTRL':
        _toggleSkipMode();
        break;
      case 'A':
        _toggleAutoMode();
        break;
      case 'LOG':
        _stopAutoAndSkip();
        _showHistoryLogSheet();
        break;
      case 'ESC':
        _stopAutoAndSkip();
        _showInGameEscMenu();
        break;
    }
  }

  Color _parseColorHex(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    var clean = hex.trim().replaceAll('#', '');
    if (clean.length == 3) {
      clean = clean.split('').map((c) => '$c$c').join();
    }
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    } else if (clean.length == 8) {
      // Ren'Py uses #RRGGBBAA
      final rgb = clean.substring(0, 6);
      final aa = clean.substring(6, 8);
      final v = int.tryParse('$aa$rgb', radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }

  void _showHistoryLogSheet() {
    final rt = _runtime;
    if (rt == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: Color(0xFF232A3B)),
      ),
      builder: (ctx) {
        final entries = rt.historyLog.reversed.toList();
        return SafeArea(
          child: SizedBox(
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.subject_rounded,
                        color: Color(0xFF60A5FA),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'ประวัติบทสนทนา (Dialogue Backlog)',
                          style: TextStyle(
                            color: Color(0xFFF3F6FC),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF232A3B)),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(
                          child: Text(
                            'ยังไม่มีประวัติบทสนทนา',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        )
                      : ListView.separated(
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 18,
                            color: Color(0xFF171C29),
                          ),
                          itemBuilder: (_, idx) {
                            final item = entries[idx];
                            final nameColor = _parseColorHex(
                              item.speakerColorHex,
                              const Color(0xFF60A5FA),
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.speaker != null &&
                                    item.speaker!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      item.speaker!,
                                      style: TextStyle(
                                        color: nameColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                Text(
                                  item.text,
                                  style: const TextStyle(
                                    color: Color(0xFFE2E8F0),
                                    fontSize: 13.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLabelJumpDialog() {
    final rt = _runtime;
    if (rt == null) return;
    final labels = rt.sortedLabelNames;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF11151F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232A3B)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 480),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.alt_route_rounded,
                        color: Color(0xFF60A5FA),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ข้ามไปยัง Label ในสคริปต์ (${labels.length})',
                          style: const TextStyle(
                            color: Color(0xFFF3F6FC),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF090B10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF232A3B)),
                      ),
                      child: ListView.separated(
                        itemCount: labels.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: Color(0xFF171C29),
                        ),
                        itemBuilder: (_, idx) {
                          final lbl = labels[idx];
                          return ListTile(
                            dense: true,
                            title: Text(
                              lbl,
                              style: const TextStyle(
                                color: Color(0xFFF3F6FC),
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.login_rounded,
                              size: 16,
                              color: Color(0xFF60A5FA),
                            ),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await rt.jumpToLabel(lbl);
                              if (mounted) setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('ปิด'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInGameEscMenu() {
    final rt = _runtime;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              backgroundColor: const Color(0xFF11151F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF232A3B)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF3B82F6).withOpacity(0.14),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                color: Color(0xFF60A5FA),
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.game.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFF3F6FC),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (rt != null)
                                    Text(
                                      'สคริปต์ ${rt.scriptFileCount} ไฟล์ • ${rt.labelCount} Labels • ${rt.currentFile}:${rt.currentLine}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        if (rt != null) ...[
                          const Text(
                            'ระบบบันทึกสถานะเกม (Save / Load Slots)',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (int slot = 1; slot <= 4; slot++)
                            Container(
                              margin: const EdgeInsets.only(bottom: 7),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF171C29),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF232A3B),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$slot',
                                      style: const TextStyle(
                                        color: Color(0xFF60A5FA),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _saveSlots.containsKey(slot)
                                              ? 'Slot $slot • บทที่ ${(_saveSlots[slot]!['stepCount'] ?? 0)}'
                                              : 'Slot $slot • ว่าง',
                                          style: const TextStyle(
                                            color: Color(0xFFF3F6FC),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (_saveSlots.containsKey(slot))
                                          Text(
                                            (_saveSlots[slot]!['dialogueText']
                                                    as String?) ??
                                                '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      _saveSlots[slot] = rt.exportSaveState();
                                      await RenpyBridge.saveGameSaveSlots(
                                        widget.game.id,
                                        _saveSlots,
                                      );
                                      setModalState(() {});
                                      if (mounted) setState(() {});
                                    },
                                    child: const Text(
                                      'SAVE',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (_saveSlots.containsKey(slot))
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () async {
                                        final data = _saveSlots[slot]!;
                                        await rt.importSaveState(data);
                                        if (mounted) {
                                          Navigator.pop(ctx);
                                          setState(() {});
                                        }
                                      },
                                      child: const Text(
                                        'LOAD',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],

                        const Divider(height: 16, color: Color(0xFF232A3B)),

                        if (rt != null && rt.labelCount > 0)
                          _buildMenuActionTile(
                            icon: Icons.alt_route_rounded,
                            color: const Color(0xFF06B6D4),
                            title: 'ข้ามไปยังฉากหรือ Label (Jump to Label)',
                            onTap: () {
                              Navigator.pop(ctx);
                              _showLabelJumpDialog();
                            },
                          ),

                        _buildMenuActionTile(
                          icon: Icons.restart_alt_rounded,
                          color: const Color(0xFFF59E0B),
                          title: 'เริ่มรันสคริปต์ใหม่ตั้งแต่ต้น (Restart)',
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _bootEngine();
                          },
                        ),

                        _buildMenuActionTile(
                          icon: Icons.memory_rounded,
                          color: const Color(0xFF3B82F6),
                          title: _isPluginInstalled
                              ? 'ส่งต่อไปรันบน External Plugin'
                              : 'จัดการเอนจินและปลั๊กอินเสริม',
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (_isPluginInstalled) {
                              await RenpyBridge.launchRenpyGame(
                                gamePath: widget.game.path,
                                executable: widget.game.executableName,
                              );
                            } else {
                              await RenpyBridge.showPluginDownloadDialog(
                                context,
                              );
                            }
                          },
                        ),

                        _buildMenuActionTile(
                          icon: Icons.logout_rounded,
                          color: const Color(0xFFEF4444),
                          title: 'ออกจากเกมกลับสู่หน้าคลัง',
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).pop();
                          },
                        ),

                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF232A3B),
                              foregroundColor: const Color(0xFFF3F6FC),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('กลับเข้าสู่เกม'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMenuActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFF3F6FC),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rt = _runtime;

    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: Stack(
        children: [
          // Main Interactive Canvas
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _stopAutoAndSkip();
                _advanceDialogue();
              },
              child: _isLoading
                  ? _buildLoadingView()
                  : _loadError != null || rt == null
                      ? _buildDiagnosticErrorView()
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. Background Layer (from .rpa or loose file or solid color)
                            _buildBackgroundLayer(rt),

                            // 2. Character Sprites Layer
                            _buildSpritesLayer(rt),

                            // 3. Branching Menu Choices Overlay
                            if (rt.isWaitingForChoice && !_isUiHidden)
                              _buildChoicesOverlay(rt.activeChoices),

                            // 4. Bottom ADV Dialogue Window
                            if (!_isUiHidden &&
                                (rt.dialogueText.isNotEmpty || rt.isFinished))
                              _buildDialogueBox(rt),
                          ],
                        ),
            ),
          ),

          // Top Studio Telemetry Bar
          if (!_isUiHidden) _buildTopBar(rt),

          // Virtual HUD Controls
          if (!_isLoading && _loadError == null && rt != null)
            VirtualGamepadOverlay(
              opacity: _overlayOpacity,
              isAutoActive: _isAutoMode,
              isSkipActive: _isSkipMode,
              canRollback: rt.canRollback,
              onActionTriggered: _handleGamepadAction,
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF11151F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF232A3B)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'กำลังโหลด ${widget.game.title}',
              style: const TextStyle(
                color: Color(0xFFF3F6FC),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'กำลังเมานต์คลังข้อมูล .rpa และถอดรหัสต้นไม้สคริปต์ .rpyc...',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticErrorView() {
    final fs = _fs;
    final res = _loadResult;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF11151F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF232A3B)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.analytics_outlined,
                      color: Color(0xFFFBBF24),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'รายงานการตรวจสอบสคริปต์เกม',
                      style: TextStyle(
                        color: Color(0xFFF3F6FC),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _loadError ?? 'ไม่สามารถเริ่มรันสคริปต์ของเกมนี้ได้',
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (fs != null && res != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF232A3B)),
                  ),
                  child: Text(
                    'Root: ${fs.rootPath}\n'
                    'RPA Archives: ${res.archiveCount} ไฟล์\n'
                    'Indexed Assets: ${res.totalAssetsCount} รายการ\n'
                    'Decoded Scripts: ${res.files.length} ไฟล์',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 17),
                    label: const Text('กลับสู่คลังเกม'),
                  ),
                  if (_isPluginInstalled)
                    OutlinedButton.icon(
                      onPressed: () {
                        RenpyBridge.launchRenpyGame(
                          gamePath: widget.game.path,
                          executable: widget.game.executableName,
                        );
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 17),
                      label: const Text('รันผ่าน External Plugin'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundLayer(RenpyRuntime rt) {
    if (rt.bgBytes != null && rt.bgBytes!.isNotEmpty) {
      return Image.memory(
        rt.bgBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildSolidBackdrop(rt),
      );
    }
    return _buildSolidBackdrop(rt);
  }

  Widget _buildSolidBackdrop(RenpyRuntime rt) {
    final baseColor = _parseColorHex(rt.bgSolidHex, const Color(0xFF090B10));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.25,
          colors: [
             Color.lerp(baseColor, const Color(0xFF1E293B), 0.28) ?? baseColor,
            baseColor,
          ],
        ),
      ),
    );
  }

  Widget _buildSpritesLayer(RenpyRuntime rt) {
    if (rt.sprites.isEmpty) return const SizedBox.shrink();

    final entries = rt.sprites.values.toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final sprite in entries) _buildSingleSprite(rt, sprite),
      ],
    );
  }

  Widget _buildSingleSprite(RenpyRuntime rt, ActiveSprite sprite) {
    final bytes = rt.spriteBytes[sprite.tag];
    if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();

    Alignment alignment;
    switch (sprite.position) {
      case SpritePosition.left:
        alignment = const Alignment(-0.55, 1.0);
        break;
      case SpritePosition.right:
        alignment = const Alignment(0.55, 1.0);
        break;
      case SpritePosition.center:
        alignment = Alignment.bottomCenter;
        break;
    }

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.only(top: 44),
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _buildChoicesOverlay(List<ActiveChoice> choices) {
    return Container(
      color: const Color(0x99090B10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 76),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < choices.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Material(
                        color: const Color(0xEE11151F),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _selectChoice(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF3B82F6).withOpacity(0.6),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.45),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              choices[i].text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFF3F6FC),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogueBox(RenpyRuntime rt) {
    final speakerColor = _parseColorHex(
      rt.speakerColorHex,
      const Color(0xFF60A5FA),
    );

    final String displayText = rt.isFinished && rt.dialogueText.isEmpty
        ? 'จบเนื้อเรื่องในส่วนนี้แล้ว กดปุ่ม MENU เพื่อเริ่มใหม่หรือกลับสู่คลังเกม'
        : rt.dialogueText;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(76, 0, 76, 14),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: const Color(0xE80D111A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF232A3B),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.65),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rt.speakerName != null && rt.speakerName!.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 15,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: speakerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        rt.speakerName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: speakerColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
              ],
              Text(
                displayText,
                style: const TextStyle(
                  color: Color(0xFFF3F6FC),
                  fontSize: 15,
                  height: 1.48,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rt.currentFile.isNotEmpty
                        ? '${rt.currentFile}:${rt.currentLine}'
                        : '',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'แตะหน้าจอหรือกด NEXT เพื่อไปต่อ',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: speakerColor.withOpacity(0.8),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(RenpyRuntime? rt) {
    final displayTitle = rt?.configuredGameTitle ?? widget.game.title;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF090B10).withOpacity(0.86),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFFF3F6FC),
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF3F6FC),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            rt != null
                                ? 'AST VM • Step ${rt.stepCount} • ${_formatTime(_secondsPlayed)}'
                                : _formatTime(_secondsPlayed),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isSkipMode || _isAutoMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _isSkipMode
                        ? const Color(0xFFF59E0B).withOpacity(0.2)
                        : const Color(0xFF06B6D4).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isSkipMode
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF06B6D4),
                    ),
                  ),
                  child: Text(
                    _isSkipMode ? 'SKIP ACTIVE' : 'AUTO ACTIVE',
                    style: TextStyle(
                      color: _isSkipMode
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF22D3EE),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(
                  Icons.tune_rounded,
                  color: Color(0xFFCBD5E1),
                  size: 20,
                ),
                tooltip: 'เมนูเกม (ESC)',
                onPressed: _showInGameEscMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final int mins = totalSeconds ~/ 60;
    final int secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
