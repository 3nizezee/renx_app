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
  String _currentPath = '/storage/emulated/0/Download';
  List<FileSystemEntity> _entries = [];
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final extRoot = await RenpyBridge.getExternalStoragePath();
    final downloadDir = Directory(p.join(extRoot, 'Download'));
    if (await downloadDir.exists()) {
      _loadDirectory(downloadDir.path);
    } else {
      _loadDirectory(extRoot);
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
          _errorMessage = 'ไม่พบโฟลเดอร์: $targetPath';
          _isLoading = false;
        });
        return;
      }

      final rawList = dir.listSync();
      final filtered = rawList.where((entity) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) return false;
        if (entity is Directory) return true;
        if (widget.pickExecutableFile && entity is File) {
          final ext = p.extension(name).toLowerCase();
          return ext == '.exe' || ext == '.py' || ext == '.sh' || ext == '.rpy';
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
    } catch (e) {
      setState(() {
        _errorMessage =
            'ไม่สามารถเข้าถึงโฟลเดอร์นี้ได้ (กรุณาเปิดสิทธิ์ All Files Access ในหน้าตั้งค่า)';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.pickExecutableFile
                ? Icons.terminal_rounded
                : Icons.folder_open_rounded,
            color: Colors.purpleAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.pickExecutableFile
                  ? 'เลือกไฟล์เกม (.exe)'
                  : 'เลือกโฟลเดอร์เกม Ren\'Py',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current path bar + Up button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    tooltip: 'ขึ้นไปโฟลเดอร์ก่อนหน้า',
                    onPressed: _navigateUp,
                  ),
                  Expanded(
                    child: Text(
                      _currentPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Directory list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline_rounded,
                                    size: 48, color: Colors.orange),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await RenpyBridge.requestAllFilesAccess();
                                    _loadDirectory(_currentPath);
                                  },
                                  icon: const Icon(Icons.security_rounded),
                                  label: const Text('เปิดสิทธิ์เข้าถึงไฟล์'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _entries.isEmpty
                          ? const Center(
                              child: Text(
                                'ไม่มีโฟลเดอร์ย่อยหรือไฟล์ที่รองรับในหน้านี้',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _entries.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final entity = _entries[index];
                                final isDir = entity is Directory;
                                final name = p.basename(entity.path);

                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isDir
                                        ? Icons.folder_rounded
                                        : Icons.insert_drive_file_rounded,
                                    color: isDir
                                        ? Colors.amber
                                        : Colors.lightBlueAccent,
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        if (!widget.pickExecutableFile)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _currentPath),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('เลือกโฟลเดอร์นี้'),
          ),
      ],
    );
  }
}
