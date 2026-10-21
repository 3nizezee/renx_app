import 'package:flutter/material.dart';

void main() {
  runApp(const AXApp());
}

class AXApp extends StatefulWidget {
  const AXApp({super.key});

  @override
  State<AXApp> createState() => _AXAppState();
}

class _AXAppState extends State<AXApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AX Project App',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      home: HomeScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const HomeScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _counter = 0;
  int _selectedTabIndex = 0;
  final TextEditingController _textController = TextEditingController();
  String _savedNote = '';

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  void _decrementCounter() {
    setState(() {
      if (_counter > 0) _counter--;
    });
  }

  void _resetCounter() {
    setState(() {
      _counter = 0;
    });
  }

  void _saveNote() {
    if (_textController.text.trim().isNotEmpty) {
      setState(() {
        _savedNote = _textController.text.trim();
        _textController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกข้อความเรียบร้อย!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.rocket_launch_rounded),
            SizedBox(width: 10),
            Text('AX Project App'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'สลับธีม สว่าง/มืด',
            icon: Icon(
              widget.isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildHomeTab(theme),
          _buildFeaturesTab(theme),
          _buildAboutTab(theme),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'หน้าหลัก',
          ),
          NavigationDestination(
            icon: Icon(Icons.widgets_outlined),
            selectedIcon: Icon(Icons.widgets_rounded),
            label: 'ฟีเจอร์',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info_rounded),
            label: 'เกี่ยวกับ',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Card
          Card(
            elevation: 2,
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ยินดีต้อนรับสู่ AX App! 🚀',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'แอปพลิเคชัน Flutter ตัวนี้พร้อมสำหรับการ Build เป็นไฟล์ APK อัตโนมัติผ่าน GitHub Actions',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Counter Demo Card
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text(
                    'ตัวอย่างระบบนับแต้ม (State Management)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$_counter',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _decrementCounter,
                        icon: const Icon(Icons.remove),
                        label: const Text('ลด'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _incrementCounter,
                        icon: const Icon(Icons.add),
                        label: const Text('เพิ่ม'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _resetCounter,
                        child: const Text('รีเซ็ต'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick Note Card
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ตัวอย่างการรับข้อมูล (Form Input)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      labelText: 'พิมพ์ข้อความทดสอบ...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saveNote,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('บันทึกข้อความ'),
                  ),
                  if (_savedNote.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'ข้อความล่าสุดที่บันทึกไว้:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _savedNote,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesTab(ThemeData theme) {
    final features = [
      {
        'icon': Icons.cloud_done_rounded,
        'title': 'GitHub Actions CI/CD',
        'desc': 'ระบบสร้างไฟล์ APK บน Cloud อัตโนมัติทุกครั้งที่ Push โค้ด',
      },
      {
        'icon': Icons.palette_rounded,
        'title': 'Material 3 Design',
        'desc': 'รองรับทั้ง Light Mode และ Dark Mode ทันสมัยและสวยงาม',
      },
      {
        'icon': Icons.speed_rounded,
        'title': 'Flutter 3.x Performance',
        'desc': 'ประสิทธิภาพสูงสุด คอมไพล์เป็นเนทีฟโค้ดสำหรับ Android',
      },
      {
        'icon': Icons.code_rounded,
        'title': 'Easy Customization',
        'desc': 'โครงสร้างโค้ดสะอาด แยกไฟล์เป็นระเบียบ พร้อมต่อยอดฟังก์ชันใหม่ๆ',
      },
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: features.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = features[index];
        return Card(
          elevation: 1,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                item['icon'] as IconData,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              item['title'] as String,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(item['desc'] as String),
          ),
        );
      },
    );
  }

  Widget _buildAboutTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 48,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.android_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'AX Project APK Builder',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'เวอร์ชัน 1.0.0 (Build 1)',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _infoRow(context, 'Framework', 'Flutter 3.x'),
                  const Divider(),
                  _infoRow(context, 'Language', 'Dart'),
                  const Divider(),
                  _infoRow(context, 'Platform', 'Android (APK)'),
                  const Divider(),
                  _infoRow(context, 'Build System', 'GitHub Actions Cloud CI/CD'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
