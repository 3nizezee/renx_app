import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/renpy_game.dart';
import '../services/renpy_bridge.dart';
import '../services/renpy_parser.dart';
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

  double _overlayOpacity = 0.85;
  bool _isPluginInstalled = false;

  // Built-in Visual Novel Engine State
  List<VnStatement> _script = [];
  bool _isLoadingScript = true;
  int _currentIndex = 0;
  final List<int> _history = []; // For Rollback (BACK / PageUp)
  final Map<int, int> _saveSlots = {}; // Slot number -> statement index
  bool _isUiHidden = false; // For HIDE (H key)
  bool _isAutoMode = false; // For AUTO (A key)
  bool _isSkipMode = false; // For SKIP (Ctrl key)

  @override
  void initState() {
    super.initState();
    _startPlayTimer();
    _initEngine();
  }

  void _startPlayTimer() {
    _playTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsPlayed++;
        });
      }
    });
  }

  Future<void> _initEngine() async {
    final installed = await RenpyBridge.isPluginInstalled();
    final statements = await RenpyScriptParser.loadGameScript(widget.game);

    if (mounted) {
      setState(() {
        _isPluginInstalled = installed;
        _script = statements;
        _isLoadingScript = false;
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

  VnStatement? get _currentStatement {
    if (_script.isEmpty || _currentIndex < 0 || _currentIndex >= _script.length) {
      return null;
    }
    return _script[_currentIndex];
  }

  void _advanceDialogue() {
    if (_isUiHidden) {
      setState(() => _isUiHidden = false);
      return;
    }

    final current = _currentStatement;
    if (current == null) return;

    // Stop auto/skip if waiting at a branching choice menu
    if (current.choices != null && current.choices!.isNotEmpty) {
      _stopAutoAndSkip();
      return;
    }

    // Handle jump target if present
    if (current.jumpTarget != null) {
      final targetIdx =
          _script.indexWhere((s) => s.label == current.jumpTarget);
      if (targetIdx != -1) {
        setState(() {
          _history.add(_currentIndex);
          _currentIndex = targetIdx;
        });
        return;
      }
    }

    if (_currentIndex < _script.length - 1) {
      setState(() {
        _history.add(_currentIndex);
        _currentIndex++;
      });
    } else {
      _stopAutoAndSkip();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('จบเนื้อเรื่องในส่วนนี้แล้ว (กด ESC เพื่อเริ่มใหม่หรือย้อนกลับ)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _rollbackDialogue() {
    _stopAutoAndSkip();
    if (_history.isNotEmpty) {
      setState(() {
        _isUiHidden = false;
        _currentIndex = _history.removeLast();
      });
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('อยู่ที่ประโยคแรกสุดแล้ว'),
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  void _selectChoice(VnChoice choice) {
    _stopAutoAndSkip();
    if (choice.targetLabel != null) {
      final idx = _script.indexWhere((s) => s.label == choice.targetLabel);
      if (idx != -1) {
        setState(() {
          _history.add(_currentIndex);
          _currentIndex = idx;
        });
        return;
      }
    }
    if (_currentIndex < _script.length - 1) {
      setState(() {
        _history.add(_currentIndex);
        _currentIndex++;
      });
    }
  }

  void _toggleSkipMode() {
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
          Timer.periodic(const Duration(milliseconds: 280), (_) {
        _advanceDialogue();
      });
    } else if (_isAutoMode) {
      _autoSkipTimer =
          Timer.periodic(const Duration(milliseconds: 2500), (_) {
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
      case 'ESC':
        _stopAutoAndSkip();
        _showInGameEscMenu();
        break;
    }
  }

  void _showInGameEscMenu() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A24),
              title: Row(
                children: [
                  const Icon(Icons.menu_book_rounded,
                      color: Colors.purpleAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'เมนูเกม — ${widget.game.title}',
                      style: const TextStyle(fontSize: 17),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'บันทึก / โหลดเซฟด่วน (Quick Save / Load):',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      for (int slot = 1; slot <= 3; slot++)
                        Card(
                          color: Colors.black26,
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor:
                                  Colors.purpleAccent.withOpacity(0.2),
                              child: Text(
                                '$slot',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.purpleAccent,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              _saveSlots.containsKey(slot)
                                  ? 'Slot $slot (ฉากที่ ${_saveSlots[slot]! + 1})'
                                  : 'Slot $slot (ว่าง)',
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _saveSlots[slot] = _currentIndex;
                                    });
                                    setModalState(() {});
                                  },
                                  child: const Text('Save'),
                                ),
                                if (_saveSlots.containsKey(slot))
                                  FilledButton.tonal(
                                    onPressed: () {
                                      setState(() {
                                        _currentIndex = _saveSlots[slot]!;
                                      });
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text('Load'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const Divider(height: 20),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.restart_alt_rounded,
                            color: Colors.amber),
                        title: const Text('เริ่มเนื้อเรื่องใหม่ตั้งแต่ต้น'),
                        onTap: () {
                          setState(() {
                            _history.clear();
                            _currentIndex = 0;
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.extension_rounded,
                            color: Colors.cyanAccent),
                        title: Text(_isPluginInstalled
                            ? 'สลับไปรันผ่าน External Plugin'
                            : 'ตั้งค่า / ดาวน์โหลด External Plugin'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (_isPluginInstalled) {
                            await RenpyBridge.launchRenpyGame(
                              gamePath: widget.game.path,
                              executable: widget.game.executableName,
                            );
                          } else {
                            await RenpyBridge.showPluginDownloadDialog(context);
                          }
                        },
                      ),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.exit_to_app_rounded,
                            color: Colors.redAccent),
                        title: const Text('ออกจากเกมกลับสู่หน้าคลัง'),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('กลับเข้าสู่เกม'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stmt = _currentStatement;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Visual Novel Display Canvas
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _stopAutoAndSkip();
                _advanceDialogue();
              },
              child: _isLoadingScript
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.purpleAccent),
                          SizedBox(height: 14),
                          Text(
                            'กำลังโหลดสคริปต์ Ren\'Py...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. Scene Background Layer
                        _buildBackgroundLayer(stmt),

                        // 2. Character Sprite Layer
                        if (stmt != null) _buildCharacterSpriteLayer(stmt),

                        // 3. Branching Choice Overlay (if choices exist)
                        if (stmt != null &&
                            stmt.choices != null &&
                            stmt.choices!.isNotEmpty &&
                            !_isUiHidden)
                          _buildChoicesOverlay(stmt.choices!),

                        // 4. Ren'Py ADV Dialogue Box at the bottom
                        if (stmt != null && !_isUiHidden)
                          _buildDialogueBox(stmt),
                      ],
                    ),
            ),
          ),

          // Top Navigation Bar
          if (!_isUiHidden)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.game.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Built-in Engine • ฉาก ${_currentIndex + 1}/${_script.length} • ${_formatTime(_secondsPlayed)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_isSkipMode || _isAutoMode)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: _isSkipMode
                                ? Colors.deepOrange
                                : Colors.amber.shade800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _isSkipMode ? 'SKIPPING ⏩' : 'AUTO ▶',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.opacity_rounded,
                            color: Colors.white, size: 20),
                        tooltip: 'ปรับความโปร่งใสปุ่มกด',
                        onPressed: _showOpacityDialog,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_applications_rounded,
                            color: Colors.white, size: 22),
                        tooltip: 'เมนูเกม (ESC)',
                        onPressed: _showInGameEscMenu,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Virtual Gamepad Overlay (Touch Controls for Visual Novels)
          VirtualGamepadOverlay(
            opacity: _overlayOpacity,
            onActionTriggered: _handleGamepadAction,
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundLayer(VnStatement? stmt) {
    if (stmt?.bgPath != null && File(stmt!.bgPath!).existsSync()) {
      return Image.file(
        File(stmt.bgPath!),
        fit: BoxFit.cover,
      );
    }

    // Styled Visual Novel atmospheric background
    List<Color> colors;
    IconData bgIcon;
    switch (stmt?.sceneStyle) {
      case 'sunset':
        colors = [
          const Color(0xFF3B1D5A),
          const Color(0xFF8B2F52),
          const Color(0xFFD96B43),
        ];
        bgIcon = Icons.wb_twilight_rounded;
        break;
      case 'night':
        colors = [
          const Color(0xFF0A0E24),
          const Color(0xFF17224D),
          const Color(0xFF283566),
        ];
        bgIcon = Icons.nights_stay_rounded;
        break;
      case 'room':
        colors = [
          const Color(0xFF1F242D),
          const Color(0xFF2E3846),
          const Color(0xFF3E4C5E),
        ];
        bgIcon = Icons.computer_rounded;
        break;
      default:
        colors = [
          const Color(0xFF1D3557),
          const Color(0xFF457B9D),
          const Color(0xFFA8DADC),
        ];
        bgIcon = Icons.park_rounded;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.12,
          child: Icon(bgIcon, size: 200, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildCharacterSpriteLayer(VnStatement stmt) {
    if (stmt.spritePath != null && File(stmt.spritePath!).existsSync()) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 50),
          child: Image.file(
            File(stmt.spritePath!),
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    if (stmt.speaker != null && !stmt.speaker!.startsWith('ระบบ')) {
      return Align(
        alignment: const Alignment(0, -0.15),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Container(
            key: ValueKey(stmt.speaker),
            width: 140,
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  stmt.speakerColor.withOpacity(0.35),
                  Colors.black.withOpacity(0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: stmt.speakerColor.withOpacity(0.75),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 72,
                  color: stmt.speakerColor,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    stmt.speaker!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: stmt.speakerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildChoicesOverlay(List<VnChoice> choices) {
    return Container(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: choices.map((choice) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xDD1F1B3A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                            color: Colors.purpleAccent, width: 1.5),
                      ),
                    ),
                    onPressed: () => _selectChoice(choice),
                    child: Text(
                      choice.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogueBox(VnStatement stmt) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(84, 0, 84, 12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          decoration: BoxDecoration(
            color: const Color(0xD9101018),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (stmt.speakerColor).withOpacity(0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stmt.speaker != null) ...[
                Text(
                  stmt.speaker!,
                  style: TextStyle(
                    color: stmt.speakerColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                stmt.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'แตะหน้าจอ หรือกด NEXT เพื่อไปต่อ ▶',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOpacityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('ความโปร่งใสของปุ่มกด'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: _overlayOpacity,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  label: '${(_overlayOpacity * 100).round()}%',
                  onChanged: (val) {
                    setDialogState(() => _overlayOpacity = val);
                    setState(() => _overlayOpacity = val);
                  },
                ),
                Text('${(_overlayOpacity * 100).round()}%'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ตกลง'),
              ),
            ],
          );
        });
      },
    );
  }

  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
