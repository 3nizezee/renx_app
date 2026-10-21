import 'dart:async';
import 'package:flutter/material.dart';
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
  Timer? _timer;
  String _lastAction = '';
  double _overlayOpacity = 0.8;
  bool _isPluginInstalled = false;
  bool _hasLaunchedPlugin = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _checkPluginAndLaunch();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsPlayed++;
      });
    });
  }

  Future<void> _checkPluginAndLaunch() async {
    final installed = await RenpyBridge.isPluginInstalled();
    setState(() {
      _isPluginInstalled = installed;
    });

    if (installed) {
      final success = await RenpyBridge.launchRenpyGame(
        gamePath: widget.game.path,
        executable: widget.game.executableName,
      );
      setState(() {
        _hasLaunchedPlugin = success;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final minutes = (_secondsPlayed / 60).round();
    widget.onSessionComplete(minutes);
    super.dispose();
  }

  void _handleAction(String action) {
    setState(() {
      _lastAction = action;
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ปุ่ม $action ทำงาน'),
        duration: const Duration(milliseconds: 500),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 100, right: 100),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Display Canvas
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  border: Border.all(color: Colors.purple.shade700, width: 2),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background simulation art or status
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videogame_asset_rounded,
                            size: 64,
                            color: Colors.purple.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.game.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ren\'Py Engine Active • ${_formatTime(_secondsPlayed)}',
                            style: TextStyle(
                              color: Colors.purple.shade200,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (!_isPluginInstalled)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade900.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.amber.shade400),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.info_outline,
                                      color: Colors.amber, size: 18),
                                  const SizedBox(width: 8),
                                  const Flexible(
                                    child: Text(
                                      'ยังไม่ได้ติดตั้ง Ren\'Py Plugin — กำลังจำลองหน้าจอและปุ่มกดเสมือน',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () =>
                                        RenpyBridge.openPluginDownloadPage(),
                                    child: const Text('ดาวน์โหลด'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Top Navigation Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.black.withOpacity(0.5),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.opacity_rounded,
                          color: Colors.white),
                      tooltip: 'ปรับความโปร่งใสปุ่มกด',
                      onPressed: _showOpacityDialog,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white),
                      tooltip: 'เปิดเกมใหม่ผ่าน Plugin',
                      onPressed: _checkPluginAndLaunch,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Virtual Gamepad Overlay (Touch Controls for Visual Novels)
          VirtualGamepadOverlay(
            opacity: _overlayOpacity,
            onActionTriggered: _handleAction,
          ),
        ],
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
