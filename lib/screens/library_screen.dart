import 'package:flutter/material.dart';
import '../models/renpy_game.dart';
import '../services/game_scanner.dart';
import '../services/renpy_bridge.dart';
import '../widgets/folder_picker_dialog.dart';
import '../widgets/game_card.dart';
import 'game_runner_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<RenpyGame> _games = <RenpyGame>[];
  bool _isLoading = true;
  String _searchQuery = '';
  int _selectedFilter = 0; // 0: All, 1: Bookmarked, 2: Recent
  bool _isPluginInstalled = false;
  bool _hasStorageAccess = true;

  @override
  void initState() {
    super.initState();
    _loadGames();
    _checkSystemStatus();
  }

  Future<void> _checkSystemStatus() async {
    final installed = await RenpyBridge.isPluginInstalled();
    final storage = await RenpyBridge.hasAllFilesAccess();
    if (mounted) {
      setState(() {
        _isPluginInstalled = installed;
        _hasStorageAccess = storage;
      });
    }
  }

  Future<void> _loadGames() async {
    setState(() => _isLoading = true);
    final saved = await RenpyBridge.loadSavedGames();

    _games
      ..clear()
      ..addAll(saved);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveGames() async {
    await RenpyBridge.saveGames(_games);
  }

  void _addGame(RenpyGame game) {
    setState(() {
      _games.removeWhere((g) => g.path == game.path);
      _games.insert(0, game);
    });
    _saveGames();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เพิ่ม "${game.title}" เข้าสู่คลังเกมเรียบร้อยแล้ว'),
      ),
    );
  }

  void _deleteGame(RenpyGame game) {
    setState(() {
      _games.removeWhere((g) => g.id == game.id);
    });
    _saveGames();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('นำ "${game.title}" ออกจากคลังเกมแล้ว'),
      ),
    );
  }

  void _toggleFavorite(RenpyGame game) {
    setState(() {
      game.isFavorite = !game.isFavorite;
    });
    _saveGames();
  }

  Future<void> _pickGameFolder() async {
    final String? selectedDirectory = await showDialog<String>(
      context: context,
      builder: (_) => const FolderPickerDialog(pickExecutableFile: false),
    );

    if (selectedDirectory != null) {
      await _processSelectedPath(selectedDirectory);
    }
  }

  Future<void> _pickGameFile() async {
    final String? selectedFile = await showDialog<String>(
      context: context,
      builder: (_) => const FolderPickerDialog(pickExecutableFile: true),
    );

    if (selectedFile != null) {
      await _processSelectedPath(selectedFile);
    }
  }

  Future<void> _processSelectedPath(String path) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF11151F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF232A3B)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF3B82F6),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'กำลังสแกนโครงสร้างไฟล์และคลังข้อมูล .rpa...',
                style: TextStyle(
                  color: Color(0xFFF3F6FC),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final scanResult = await GameScanner.scanDirectory(path);
    if (mounted) Navigator.pop(context);

    if (!scanResult.isValidRenpy) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFF59E0B),
                  size: 22,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ไม่พบโครงสร้างเกม Ren\'Py',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              scanResult.errorMessage ??
                  'โฟลเดอร์ที่เลือกไม่มีโฟลเดอร์ game/ หรือไฟล์ .rpyc / .rpa ที่รองรับ',
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('รับทราบ'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final titleController = TextEditingController(text: scanResult.title);
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFF11151F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF232A3B)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
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
                          color: const Color(0xFF10B981).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.check_circle_outline_rounded,
                          color: Color(0xFF34D399),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ตรวจสอบโครงสร้างเกมสำเร็จ',
                              style: TextStyle(
                                color: Color(0xFFF3F6FC),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'ยืนยันชื่อและรายละเอียดก่อนเพิ่มเข้าสู่คลังเกม',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(
                      color: Color(0xFFF3F6FC),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'ชื่อโปรเจกต์เกม',
                      filled: true,
                      fillColor: const Color(0xFF090B10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF232A3B)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090B10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF232A3B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSpecRow('เอนจิน', scanResult.renpyVersion),
                        const SizedBox(height: 4),
                        _buildSpecRow(
                          'คลังข้อมูล .rpa',
                          '${scanResult.archiveCount} ไฟล์',
                        ),
                        const SizedBox(height: 4),
                        _buildSpecRow(
                          'ไฟล์สคริปต์',
                          '${scanResult.scriptCount} ไฟล์ (${scanResult.assetCount} assets)',
                        ),
                        const SizedBox(height: 4),
                        _buildSpecRow('พาธ', scanResult.rootPath),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
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
                        onPressed: () {
                          final newGame = RenpyGame(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            title: titleController.text.trim().isNotEmpty
                                ? titleController.text.trim()
                                : scanResult.title,
                            path: scanResult.rootPath,
                            executableName: scanResult.executableName,
                            iconPath: scanResult.iconPath,
                            coverPath: scanResult.coverPath,
                            renpyVersion: scanResult.renpyVersion,
                            dateAdded: DateTime.now(),
                            archiveCount: scanResult.archiveCount,
                            scriptCount: scanResult.scriptCount,
                            assetCount: scanResult.assetCount,
                          );
                          _addGame(newGame);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          'บันทึกเข้าคลังเกม',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSpecRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  void _playGame(RenpyGame game) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameRunnerScreen(
          game: game,
          onSessionComplete: (additionalMinutes) {
            setState(() {
              game.lastPlayed = DateTime.now();
              game.playTimeMinutes += additionalMinutes;
            });
            _saveGames();
          },
        ),
      ),
    );
  }

  List<RenpyGame> get _filteredGames {
    return _games.where((g) {
      final matchesSearch =
          g.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              g.path.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      if (_selectedFilter == 1) return g.isFavorite;
      if (_selectedFilter == 2) return g.lastPlayed != null;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final games = _filteredGames;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF3B82F6),
                    Color(0xFF06B6D4),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.terminal_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RenPlay Studio',
                    style: TextStyle(
                      color: Color(0xFFF3F6FC),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'PC Ren\'Py Runtime Environment',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'จัดการเอนจิน',
            icon: const Icon(
              Icons.memory_rounded,
              color: Color(0xFF94A3B8),
              size: 21,
            ),
            onPressed: () => RenpyBridge.showPluginDownloadDialog(context),
          ),
          IconButton(
            tooltip: 'ตั้งค่าระบบ',
            icon: const Icon(
              Icons.tune_rounded,
              color: Color(0xFF94A3B8),
              size: 21,
            ),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _checkSystemStatus();
            },
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFF171C29),
          ),
        ),
      ),
      body: Column(
        children: [
          // System Telemetry & Storage Permission Bar
          _buildSystemStatusBar(),

          // Search and Filter Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF11151F),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFF232A3B)),
                  ),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(
                      color: Color(0xFFF3F6FC),
                      fontSize: 13.5,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'ค้นหาชื่อเกมหรือพาธโฟลเดอร์...',
                      hintStyle: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Color(0xFF64748B),
                        size: 19,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildFilterPill(
                      index: 0,
                      label: 'ทั้งหมด (${_games.length})',
                      icon: Icons.grid_view_rounded,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      index: 1,
                      label: 'บุ๊กมาร์ก',
                      icon: Icons.bookmark_border_rounded,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      index: 2,
                      label: 'เล่นล่าสุด',
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Content Area
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF3B82F6),
                    ),
                  )
                : games.isEmpty
                    ? _buildEmptyState()
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.76,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: games.length,
                        itemBuilder: (context, index) {
                          final game = games[index];
                          return GameCard(
                            game: game,
                            onPlay: () => _playGame(game),
                            onDelete: () => _deleteGame(game),
                            onToggleFavorite: () => _toggleFavorite(game),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onPressed: _showAddGameSheet,
        icon: const Icon(Icons.create_new_folder_rounded, size: 19),
        label: const Text(
          'นำเข้าเกม',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildSystemStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0xFF0D111A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF171C29)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isPluginInstalled
                  ? 'AST VM + RPA Reader พร้อมทำงาน • ตรวจพบ External Plugin'
                  : 'AST VM + RPA/RPYC Reader พร้อมทำงานในตัวแอป',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!_hasStorageAccess)
            InkWell(
              onTap: () async {
                await RenpyBridge.requestAllFilesAccess();
                await _checkSystemStatus();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withOpacity(0.5),
                  ),
                ),
                child: const Text(
                  'เปิดสิทธิ์อ่านไฟล์',
                  style: TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool selected = _selectedFilter == index;
    return Material(
      color: selected ? const Color(0xFF1E293B) : const Color(0xFF11151F),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _selectedFilter = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
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
                color: selected
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFF3F6FC)
                      : const Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF11151F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF232A3B)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withOpacity(0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.folder_copy_rounded,
                    size: 26,
                    color: Color(0xFF60A5FA),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ยังไม่มีโปรเจกต์เกมในคลัง',
                  style: TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'เลือกโฟลเดอร์เกม Ren\'Py ของ PC ที่คัดลอกไว้ในเครื่อง ระบบจะอ่านไฟล์สคริปต์ .rpyc, .rpy และคลังข้อมูล .rpa ของเกมนั้นโดยตรง',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _pickGameFolder,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text(
                      'เลือกโฟลเดอร์เกมจากเครื่อง',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCBD5E1),
                      side: const BorderSide(color: Color(0xFF232A3B)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _pickGameFile,
                    icon: const Icon(Icons.terminal_rounded, size: 18),
                    label: const Text('เลือกด้วยไฟล์ .exe / .rpa / .rpyc'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddGameSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF11151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: Color(0xFF232A3B)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'นำเข้าเกม Ren\'Py เข้าสู่คลัง',
                  style: TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'รองรับทั้งเกมที่แพ็กไฟล์ไว้ใน .rpa และเกมที่ใช้สคริปต์ .rpyc / .rpy',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSheetOption(
                  icon: Icons.folder_open_rounded,
                  accent: const Color(0xFF3B82F6),
                  title: 'เลือกโฟลเดอร์หลักของเกม (แนะนำ)',
                  subtitle: 'เลือกโฟลเดอร์ที่มีโฟลเดอร์ย่อย game/ หรือไฟล์ .rpa',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickGameFolder();
                  },
                ),
                const SizedBox(height: 10),
                _buildSheetOption(
                  icon: Icons.terminal_rounded,
                  accent: const Color(0xFF06B6D4),
                  title: 'เลือกไฟล์เปิดเกม (.exe / .rpa / .rpyc)',
                  subtitle: 'ระบุไฟล์ภายในโฟลเดอร์เกมเพื่อให้ระบบค้นหาอัตโนมัติ',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickGameFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetOption({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF171C29),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF232A3B)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF3F6FC),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF64748B),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
