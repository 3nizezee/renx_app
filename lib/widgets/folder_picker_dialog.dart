import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/renpy_bridge.dart';

class FolderPickerDialog extends StatefulWidget {
  final bool pickExecutableFile;

  const FolderPickerDialog({
    super.key,
    this.pickExecutableFile = false,
  });

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  String _extRoot = '/storage/emulated/0';
  String _currentPath = '/storage/emulated/0/Download';
  List<FileSystemEntity> _entries = <FileSystemEntity>[];
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final extRoot = await RenpyBridge.getExternalStoragePath();
    _extRoot = extRoot;
    final downloadDir = Directory(p.join(extRoot, 'Download'));
    if (await downloadDir.exists()) {
      await _loadDirectory(downloadDir.path);
    } else {
      await _loadDirectory(extRoot);
    }
  }

  Future<void> _loadDirectory(String targetPath) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dir = Directory(targetPath);
      if (!await dir.exists()) {
        setState(() {
          _errorMessage = 'ไม่พบโฟลเดอร์ที่ระบุ: $targetPath';
          _isLoading = false;
        });
        return;
      }

      final rawList = dir.listSync(followLinks: false);
      final filtered = rawList.where((entity) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) return false;
        if (entity is Directory) return true;
        if (entity is File) {
          final ext = p.extension(name).toLowerCase();
          if (widget.pickExecutableFile) {
            return ext == '.exe' ||
                ext == '.py' ||
                ext == '.sh' ||
                ext == '.rpyc' ||
                ext == '.rpy' ||
                ext == '.rpa';
          }
          return ext == '.exe' || ext == '.rpa' || ext == '.rpyc';
        }
        return false;
      }).toList();

      filtered.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });

      setState(() {
        _currentPath = targetPath;
        _entries = filtered;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage =
            'ระบบต้องการสิทธิ์เข้าถึงพื้นที่จัดเก็บข้อมูล (All Files Access) เพื่ออ่านโฟลเดอร์เกม';
        _isLoading = false;
      });
    }
  }

  void _navigateUp() {
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath && parent.isNotEmpty) {
      _loadDirectory(parent);
    }
  }

  bool _looksLikeRenpyDirectory(Directory dir) {
    try {
      if (Directory(p.join(dir.path, 'game')).existsSync()) return true;
      for (final child in dir.listSync(followLinks: false)) {
        if (child is File) {
          final ext = p.extension(child.path).toLowerCase();
          if (ext == '.rpa' || ext == '.rpyc' || ext == '.rpy') return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _promptManualPath() async {
    final controller = TextEditingController(text: _currentPath);
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'ระบุพาธโฟลเดอร์โดยตรง',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            labelText: 'พาธโฟลเดอร์เกม',
            filled: true,
            fillColor: const Color(0xFF090B10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('ไปที่พาธนี้'),
          ),
        ],
      ),
    );
    if (entered != null && entered.isNotEmpty) {
      await _loadDirectory(entered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentRenpy = _looksLikeRenpyDirectory(Directory(_currentPath));

    return Dialog(
      backgroundColor: const Color(0xFF11151F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF232A3B), width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.14),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withOpacity(0.4),
                      ),
                    ),
                    child: Icon(
                      widget.pickExecutableFile
                          ? Icons.terminal_rounded
                          : Icons.folder_open_rounded,
                      color: const Color(0xFF60A5FA),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.pickExecutableFile
                              ? 'เลือกไฟล์เปิดเกม (.exe / .rpyc / .rpa)'
                              : 'เลือกโฟลเดอร์เกม Ren\'Py',
                          style: const TextStyle(
                            color: Color(0xFFF3F6FC),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'เปิดเข้าไปในโฟลเดอร์หลักของเกมแล้วกดปุ่มเลือกโฟลเดอร์',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'พิมพ์พาธเอง',
                    icon: const Icon(
                      Icons.edit_road_rounded,
                      size: 19,
                      color: Color(0xFF94A3B8),
                    ),
                    onPressed: _promptManualPath,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Quick Bookmarks
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickPathBtn(
                      label: 'Download',
                      icon: Icons.download_rounded,
                      target: p.join(_extRoot, 'Download'),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickPathBtn(
                      label: 'Internal Root',
                      icon: Icons.storage_rounded,
                      target: _extRoot,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickPathBtn(
                      label: 'Documents',
                      icon: Icons.folder_copy_rounded,
                      target: p.join(_extRoot, 'Documents'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Current Path Bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF090B10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCurrentRenpy
                        ? const Color(0xFF10B981).withOpacity(0.5)
                        : const Color(0xFF232A3B),
                  ),
                ),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: _navigateUp,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171C29),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          size: 16,
                          color: Color(0xFFF3F6FC),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _currentPath,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentRenpy)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.45),
                          ),
                        ),
                        child: const Text(
                          'REN\'PY READY',
                          style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Directory Entries
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF232A3B)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF3B82F6),
                          ),
                        )
                      : _errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 40,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFCBD5E1),
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        await RenpyBridge
                                            .requestAllFilesAccess();
                                        await _loadDirectory(_currentPath);
                                      },
                                      icon: const Icon(
                                        Icons.verified_user_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'อนุญาตสิทธิ์เข้าถึงไฟล์',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _entries.isEmpty
                              ? const Center(
                                  child: Text(
                                    'ไม่มีโฟลเดอร์ย่อยในตำแหน่งนี้ สามารถกดเลือกโฟลเดอร์นี้ได้ทันที',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _entries.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: Color(0xFF171C29),
                                  ),
                                  itemBuilder: (context, index) {
                                    final entity = _entries[index];
                                    final isDir = entity is Directory;
                                    final name = p.basename(entity.path);
                                    final isRenpyFolder = isDir &&
                                        _looksLikeRenpyDirectory(entity);

                                    return ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 2,
                                      ),
                                      leading: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: isRenpyFolder
                                              ? const Color(0xFF10B981)
                                                  .withOpacity(0.15)
                                              : isDir
                                                  ? const Color(0xFF3B82F6)
                                                      .withOpacity(0.12)
                                                  : const Color(0xFF06B6D4)
                                                      .withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          isDir
                                              ? Icons.folder_rounded
                                              : Icons.insert_drive_file_rounded,
                                          size: 17,
                                          color: isRenpyFolder
                                              ? const Color(0xFF34D399)
                                              : isDir
                                                  ? const Color(0xFF60A5FA)
                                                  : const Color(0xFF22D3EE),
                                        ),
                                      ),
                                      title: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFF3F6FC),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      trailing: isRenpyFolder
                                          ? Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981)
                                                    .withOpacity(0.16),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: const Text(
                                                'GAME',
                                                style: TextStyle(
                                                  color: Color(0xFF34D399),
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            )
                                          : isDir
                                              ? const Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 18,
                                                  color: Color(0xFF64748B),
                                                )
                                              : null,
                                      onTap: () {
                                        if (isDir) {
                                          _loadDirectory(entity.path);
                                        } else {
                                          Navigator.pop(context, entity.path);
                                        }
                                      },
                                    );
                                  },
                                ),
                ),
              ),
              const SizedBox(height: 14),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'ยกเลิก',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, _currentPath),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text(
                      'เลือกโฟลเดอร์นี้',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

  Widget _buildQuickPathBtn({
    required String label,
    required IconData icon,
    required String target,
  }) {
    final bool active = _currentPath == target;
    return Material(
      color: active ? const Color(0xFF1E293B) : const Color(0xFF171C29),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _loadDirectory(target),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? const Color(0xFF3B82F6).withOpacity(0.6)
                  : const Color(0xFF232A3B),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? const Color(0xFFF3F6FC)
                      : const Color(0xFFCBD5E1),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
