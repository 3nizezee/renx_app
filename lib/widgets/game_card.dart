import 'dart:io';
import 'package:flutter/material.dart';
import '../models/renpy_game.dart';

class GameCard extends StatelessWidget {
  final RenpyGame game;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const GameCard({
    super.key,
    required this.game,
    required this.onPlay,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasCover =
        game.coverPath != null && File(game.coverPath!).existsSync();
    final bool hasIcon =
        game.iconPath != null && File(game.iconPath!).existsSync();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11151F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF232A3B),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Artwork Hero Section
              Expanded(
                flex: 56,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      Image.file(
                        File(game.coverPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackArtwork(hasIcon),
                      )
                    else
                      _buildFallbackArtwork(hasIcon),

                    // Subtle vignette overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF090B10).withOpacity(0.45),
                              Colors.transparent,
                              const Color(0xFF11151F).withOpacity(0.95),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Top-left technical badges
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 44,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildBadge(
                            label: game.renpyVersion,
                            color: const Color(0xFF3B82F6),
                          ),
                          if (game.archiveCount > 0)
                            _buildBadge(
                              label: 'RPA x${game.archiveCount}',
                              color: const Color(0xFF06B6D4),
                            ),
                        ],
                      ),
                    ),

                    // Top-right favorite button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: const Color(0xFF090B10).withOpacity(0.68),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onToggleFavorite,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: game.isFavorite
                                    ? const Color(0xFF3B82F6).withOpacity(0.6)
                                    : const Color(0xFF232A3B),
                              ),
                            ),
                            child: Icon(
                              game.isFavorite
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              size: 16,
                              color: game.isFavorite
                                  ? const Color(0xFF60A5FA)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Bottom-left icon + Launch pill
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      child: Row(
                        children: [
                          if (hasIcon)
                            Container(
                              width: 32,
                              height: 32,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                image: DecorationImage(
                                  image: FileImage(File(game.iconPath!)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6),
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF3B82F6).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'PLAY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
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

              // Metadata Section
              Expanded(
                flex: 44,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            game.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF3F6FC),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            game.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              game.playTimeMinutes > 0
                                  ? '${game.playTimeMinutes} นาที'
                                  : 'พร้อมเล่น',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              color: const Color(0xFF171C29),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(
                                  color: Color(0xFF232A3B),
                                ),
                              ),
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                              onSelected: (val) {
                                if (val == 'delete') onDelete();
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'นำออกจากคลังเกม',
                                        style: TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackArtwork(bool hasIcon) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF131B2E),
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
      ),
      child: Center(
        child: hasIcon
            ? Image.file(
                File(game.iconPath!),
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              )
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withOpacity(0.3),
                  ),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  size: 24,
                  color: Color(0xFF60A5FA),
                ),
              ),
      ),
    );
  }

  Widget _buildBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF090B10).withOpacity(0.78),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.45), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color. computeLuminance() > 0.4 ? color : const Color(0xFF93C5FD),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
