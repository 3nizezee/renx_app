import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VirtualGamepadOverlay extends StatefulWidget {
  final double opacity;
  final bool isAutoActive;
  final bool isSkipActive;
  final bool canRollback;
  final Function(String action)? onActionTriggered;

  const VirtualGamepadOverlay({
    super.key,
    this.opacity = 0.88,
    this.isAutoActive = false,
    this.isSkipActive = false,
    this.canRollback = false,
    this.onActionTriggered,
  });

  @override
  State<VirtualGamepadOverlay> createState() => _VirtualGamepadOverlayState();
}

class _VirtualGamepadOverlayState extends State<VirtualGamepadOverlay> {
  bool _isCollapsed = false;

  void _trigger(String action) {
    HapticFeedback.selectionClick();
    widget.onActionTriggered?.call(action);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Stack(
          children: [
            // Top-right HUD visibility toggle
            Positioned(
              top: 52,
              right: 12,
              child: Opacity(
                opacity: widget.opacity,
                child: Material(
                  color: const Color(0xD9090B10),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _isCollapsed = !_isCollapsed;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF232A3B)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCollapsed
                                ? Icons.tune_rounded
                                : Icons.keyboard_hide_rounded,
                            color: const Color(0xFF94A3B8),
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isCollapsed ? 'HUD' : 'ซ่อนปุ่ม',
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (!_isCollapsed) ...[
              // Left Vertical Control Strip (ESC, LOG, BACK, HIDE)
              Positioned(
                left: 12,
                bottom: 24,
                child: Opacity(
                  opacity: widget.opacity,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xD9090B10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF232A3B)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHudButton(
                          label: 'MENU',
                          icon: Icons.grid_view_rounded,
                          onTap: () => _trigger('ESC'),
                        ),
                        const SizedBox(height: 6),
                        _buildHudButton(
                          label: 'LOG',
                          icon: Icons.subject_rounded,
                          onTap: () => _trigger('LOG'),
                        ),
                        const SizedBox(height: 6),
                        _buildHudButton(
                          label: 'BACK',
                          icon: Icons.undo_rounded,
                          enabled: widget.canRollback,
                          onTap: () => _trigger('PAGE_UP'),
                        ),
                        const SizedBox(height: 6),
                        _buildHudButton(
                          label: 'HIDE',
                          icon: Icons.visibility_off_outlined,
                          onTap: () => _trigger('H'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Right Vertical Control Strip (SKIP, AUTO, NEXT)
              Positioned(
                right: 12,
                bottom: 24,
                child: Opacity(
                  opacity: widget.opacity,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xD9090B10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF232A3B)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHudButton(
                          label: 'SKIP',
                          icon: Icons.fast_forward_rounded,
                          active: widget.isSkipActive,
                          activeColor: const Color(0xFFF59E0B),
                          onTap: () => _trigger('CTRL'),
                        ),
                        const SizedBox(height: 6),
                        _buildHudButton(
                          label: 'AUTO',
                          icon: Icons.autorenew_rounded,
                          active: widget.isAutoActive,
                          activeColor: const Color(0xFF06B6D4),
                          onTap: () => _trigger('A'),
                        ),
                        const SizedBox(height: 6),
                        _buildHudButton(
                          label: 'NEXT',
                          icon: Icons.keyboard_return_rounded,
                          isPrimary: true,
                          onTap: () => _trigger('ENTER'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHudButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    bool enabled = true,
    bool isPrimary = false,
    Color activeColor = const Color(0xFF3B82F6),
  }) {
    final Color bg = isPrimary
        ? const Color(0xFF3B82F6)
        : active
            ? activeColor.withOpacity(0.22)
            : const Color(0xFF171C29);

    final Color border = isPrimary
        ? const Color(0xFF60A5FA)
        : active
            ? activeColor
            : const Color(0xFF232A3B);

    final Color fg = !enabled
        ? const Color(0xFF475569)
        : isPrimary
            ? Colors.white
            : active
                ? activeColor
                : const Color(0xFFE2E8F0);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 48,
          height: isPrimary ? 54 : 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: isPrimary ? 20 : 17),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
