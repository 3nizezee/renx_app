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
  final List<RenpyGame> _games = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int _selectedFilter = 0; // 0: All, 1: Favorites, 2: Recent
  bool _isPluginInstalled = false;

  @override
  void initState() {
    super.initState();
    _loadGames();
    _checkPlugin();
  }

  Future<void> _checkPlugin() async {
    final installed = await RenpyBridge.isPluginInstalled();
    setState(() {
      _isPluginInstalled = installed;
    });
  }

  Future<void> _loadGames() async {
    setState(() => _isLoading = true);
    final saved = await RenpyBridge.loadSavedGames();

    _games.clear();
    if (saved != null && saved.isNotEmpty) {
      _games.addAll(saved);
    } else {
      // Add default demo game for immediate testing if empty
      _games.add(GameScanner.createDemoGame());
      await _saveGames();
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveGames() async {
    await RenpyBridge.saveGames(_games);
  }

  void _addGame(RenpyGame game) {
    setState(() {
      _games.insert(0, game);
    });
    _saveGames();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เพิ่มเกม "${game.title}" เรียบร้อยแล้ว!'),
        backgroundColor: Colors.green.shade800,
      ),
    );
  }

  void _deleteGame(RenpyGame game) {
    setState(() {
      _games.removeWhere((g) => g.id == game.id);
    });
    _saveGames();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ลบเกม "${game.title}" ออกแล้ว')),
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
      _processSelectedPath(selectedDirectory);
    }
  }

  Future<void> _pickGameFile() async {
    final String? selectedFile = await showDialog<String>(
      context: context,
      builder: (_) => const FolderPickerDialog(pickExecutableFile: true),
    );

    if (selectedFile != null) {
      _processSelectedPath(selectedFile);
    }
  }

  Future<void> _processSelectedPath(String path) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('กำลังสแกนโครงสร้างเกม Ren\'Py...'),
              ],
            ),
          ),
        ),
      ),
    );

    final scanResult = await GameScanner.scanDirectory(path);
    if (mounted) Navigator.pop(context); // Close loading dialog

    if (!scanResult.isValidRenpy) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('ไม่ใช่เกม Ren\'Py ที่ถูกต้อง'),
              ],
            ),
            content: Text(
              scanResult.errorMessage ??
                  'โฟลเดอร์นี้ไม่มีโฟลเดอร์ "game" หรือไฟล์สคริปต์ .rpyc ของ Ren\'Py\nกรุณาเลือกโฟลเดอร์หลักของเกม',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Prompt for title confirmation
    final titleController = TextEditingController(text: scanResult.title);
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('พบเกม Ren\'Py!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อเกม',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'เวอร์ชันที่ตรวจพบ: ${scanResult.renpyVersion}',
                style: const TextStyle(color: Colors.purpleAccent, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'ตำแหน่ง: ${scanResult.rootPath}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final newGame = RenpyGame(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleController.text.trim().isNotEmpty
                      ? titleController.text.trim()
                      : scanResult.title,
                  path: scanResult.rootPath,
                  executableName: scanResult.executableName,
                  iconPath: scanResult.iconPath,
                  coverPath: scanResult.coverPath,
                  renpyVersion: scanResult.renpyVersion,
                  dateAdded: DateTime.now(),
                );
                _addGame(newGame);
                Navigator.pop(context);
              },
              child: const Text('เพิ่มเกม'),
            ),
          ],
        ),
      );
    }
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
          g.title.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      if (_selectedFilter == 1) return g.isFavorite;
      if (_selectedFilter == 2) return g.lastPlayed != null;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final games = _filteredGames;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_esports_rounded, color: Colors.purpleAccent),
            SizedBox(width: 10),
            Text('RenPlay Runner'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'การตั้งค่าและคำแนะนำ',
            icon: Stack(
              children: [
                const Icon(Icons.settings_rounded),
                if (!_isPluginInstalled)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _checkPlugin();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Engine Status Banner (Built-in Engine Ready + External Plugin Option)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.green.shade900.withOpacity(0.22),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isPluginInstalled
                        ? 'เอนจินพร้อมใช้งาน (Built-in + External Plugin)'
                        : 'Built-in RenPlay Engine พร้อมใช้งานทันที',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      RenpyBridge.showPluginDownloadDialog(context),
                  icon: const Icon(Icons.extension_rounded, size: 16),
                  label: const Text('จัดการปลั๊กอิน'),
                ),
              ],
            ),
          ),

          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
                    hintText: 'ค้นหาเกมในคลัง...',
                    leading: const Icon(Icons.search_rounded),
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _filterChip('ทั้งหมด', 0),
                const SizedBox(width: 8),
                _filterChip('รายการโปรด ❤️', 1),
                const SizedBox(width: 8),
                _filterChip('เล่นล่าสุด 🕒', 2),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Game Grid or Empty state
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : games.isEmpty
                    ? _buildEmptyState(theme)
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
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
        onPressed: _showAddGameBottomSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('เพิ่มเกม'),
      ),
    );
  }

  Widget _filterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _selectedFilter = index);
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded,
                size: 72, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'ยังไม่มีเกมในคลังของคุณ',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'กดปุ่ม "เพิ่มเกม" ด้านล่าง แล้วเลือกโฟลเดอร์เกม Ren\'Py จาก PC บนเครื่องของคุณ',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => _addGame(GameScanner.createDemoGame()),
              icon: const Icon(Icons.auto_stories_rounded),
              label: const Text('เพิ่มเกมตัวอย่างเพื่อทดสอบ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddGameBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  leading: Icon(Icons.add_circle_outline_rounded,
                      color: Colors.purpleAccent),
                  title: Text(
                    'เลือกวิธีเพิ่มเกม Ren\'Py',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.folder_rounded, color: Colors.amber),
                  title: const Text('เลือกโฟลเดอร์เกม (Folder)'),
                  subtitle: const Text('เลือกโฟลเดอร์ที่มี game/ และ .rpyc'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickGameFolder();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.terminal_rounded,
                      color: Colors.blueAccent),
                  title: const Text('เลือกไฟล์เกม (.exe)'),
                  subtitle: const Text('เลือกไฟล์เปิดเกม .exe ของ Ren\'Py'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickGameFile();
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.gamepad_rounded, color: Colors.green),
                  title: const Text('เพิ่มเกมตัวอย่าง (Demo Game)'),
                  subtitle: const Text('ทดสอบระบบคลังและปุ่มควบคุมเสมือน'),
                  onTap: () {
                    Navigator.pop(context);
                    _addGame(GameScanner.createDemoGame());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
