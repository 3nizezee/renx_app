import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VirtualGamepadOverlay extends StatefulWidget {
  final double opacity;
  final Function(String action)? onActionTriggered;

  const VirtualGamepadOverlay({
    super.key,
    this.opacity = 0.75,
    this.onActionTriggered,
  });

  @override
  State<VirtualGamepadOverlay> createState() => _VirtualGamepadOverlayState();
}

class _VirtualGamepadOverlayState extends State<VirtualGamepadOverlay> {
  bool _isCollapsed = false;
  double _opacity = 0.75;

  @override
  void initState() {
    super.initState();
    _opacity = widget.opacity;
  }

  void _triggerKey(String action, LogicalKeyboardKey? key) {
    HapticFeedback.lightImpact();
    widget.onActionTriggered?.call(action);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Stack(
          children: [
            // Floating control pill at the top right to collapse/expand
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isCollapsed
                            ? Icons.gamepad_rounded
                            : Icons.visibility_off_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: _isCollapsed ? 'แสดงปุ่มกด' : 'ซ่อนปุ่มกด',
                      onPressed: () {
                        setState(() {
                          _isCollapsed = !_isCollapsed;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            if (!_isCollapsed) ...[
              // Left Quick Actions (Menu, Rollback, Hide UI)
              Positioned(
                left: 16,
                bottom: 80,
                child: Opacity(
                  opacity: _opacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildOverlayButton(
                        label: 'ESC',
                        subtitle: 'Menu',
                        icon: Icons.menu_rounded,
                        color: Colors.indigo,
                        onTap: () =>
                            _triggerKey('ESC', LogicalKeyboardKey.escape),
                      ),
                      const SizedBox(height: 12),
                      _buildOverlayButton(
                        label: 'BACK',
                        subtitle: 'Rollback',
                        icon: Icons.replay_rounded,
                        color: Colors.blueGrey,
                        onTap: () =>
                            _triggerKey('PAGE_UP', LogicalKeyboardKey.pageUp),
                      ),
                      const SizedBox(height: 12),
                      _buildOverlayButton(
                        label: 'HIDE',
                        subtitle: 'Text',
                        icon: Icons.remove_red_eye_outlined,
                        color: Colors.teal,
                        onTap: () => _triggerKey('H', LogicalKeyboardKey.keyH),
                      ),
                    ],
                  ),
                ),
              ),

              // Right Quick Actions (Skip, Auto, Next/Enter)
              Positioned(
                right: 16,
                bottom: 80,
                child: Opacity(
                  opacity: _opacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildOverlayButton(
                        label: 'SKIP',
                        subtitle: 'Ctrl',
                        icon: Icons.fast_forward_rounded,
                        color: Colors.deepOrange,
                        onTap: () => _triggerKey(
                            'CTRL', LogicalKeyboardKey.controlLeft),
                      ),
                      const SizedBox(height: 12),
                      _buildOverlayButton(
                        label: 'AUTO',
                        subtitle: 'Read',
                        icon: Icons.play_arrow_rounded,
                        color: Colors.amber.shade800,
                        onTap: () => _triggerKey('A', LogicalKeyboardKey.keyA),
                      ),
                      const SizedBox(height: 12),
                      _buildOverlayButton(
                        label: 'NEXT',
                        subtitle: 'Enter',
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green.shade700,
                        size: 64,
                        onTap: () =>
                            _triggerKey('ENTER', LogicalKeyboardKey.enter),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 56,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: Colors.white.withOpacity(0.6),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: size * 0.4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.2,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
