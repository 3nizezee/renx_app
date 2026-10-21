import 'package:flutter/material.dart';
import '../services/renpy_bridge.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isPluginInstalled = false;
  bool _hasFullStorage = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    final plugin = await RenpyBridge.isPluginInstalled();
    final storage = await RenpyBridge.hasAllFilesAccess();
    setState(() {
      _isPluginInstalled = plugin;
      _hasFullStorage = storage;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('การตั้งค่าและคำแนะนำ'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Engine Status Card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isPluginInstalled
                                  ? Icons.check_circle_rounded
                                  : Icons.warning_amber_rounded,
                              color: _isPluginInstalled
                                  ? Colors.green
                                  : Colors.orange,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ren\'Py Engine Plugin',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _isPluginInstalled
                                        ? 'ติดตั้งแล้ว พร้อมรันเกม PC ได้เต็มประสิทธิภาพ'
                                        : 'ยังไม่ได้ติดตั้ง Plugin สำหรับรัน Python/Ren\'Py',
                                    style: TextStyle(
                                      color: _isPluginInstalled
                                          ? Colors.green
                                          : Colors.orange,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!_isPluginInstalled) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () =>
                                RenpyBridge.openPluginDownloadPage(),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('ดาวน์โหลด Ren\'Py Plugin ฟรี'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Storage Access Card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _hasFullStorage
                                  ? Icons.folder_special_rounded
                                  : Icons.folder_off_rounded,
                              color: _hasFullStorage
                                  ? Colors.blue
                                  : Colors.deepOrange,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'สิทธิ์การเข้าถึงไฟล์ทั้งหมด (Storage)',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _hasFullStorage
                                        ? 'ได้รับสิทธิ์แล้ว สามารถเข้าถึงโฟลเดอร์เกมในเครื่องได้'
                                        : 'ต้องการสิทธิ์ All Files Access เพื่ออ่านไฟล์เกมจาก Downloads',
                                    style: TextStyle(
                                      color: _hasFullStorage
                                          ? Colors.blue
                                          : Colors.deepOrange,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!_hasFullStorage) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await RenpyBridge.requestAllFilesAccess();
                              await _checkStatus();
                            },
                            icon: const Icon(Icons.security_rounded),
                            label: const Text('อนุญาตสิทธิ์เข้าถึงไฟล์'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Guide Card
                Card(
                  elevation: 1,
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.menu_book_rounded,
                                color: Colors.purpleAccent),
                            const SizedBox(width: 8),
                            Text(
                              'วิธีนำเกม Ren\'Py ของ PC มาเล่นบนมือถือ',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _stepRow(
                          '1',
                          'คัดลอกโฟลเดอร์เกม Ren\'Py ของ PC (ที่มีโฟลเดอร์ game และไฟล์ .exe) ลงในมือถือ เช่น ในโฟลเดอร์ Downloads',
                        ),
                        _stepRow(
                          '2',
                          'ในแอปนี้ กดปุ่ม "+" ที่หน้าหลัก แล้วเลือกโฟลเดอร์เกม หรือเลือกไฟล์ .exe ของเกม',
                        ),
                        _stepRow(
                          '3',
                          'ระบบจะตรวจสอบไฟล์ .rpyc และดึงหน้าปกพร้อมตั้งค่าให้อัตโนมัติ',
                        ),
                        _stepRow(
                          '4',
                          'กดปุ่ม "เล่น" เพื่อเริ่มเกม พร้อมใช้ปุ่มสัมผัสเสมือน (ESC, SKIP, AUTO, BACK, HIDE) บนหน้าจอได้ทันที!',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _stepRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.purpleAccent.withOpacity(0.2),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.purpleAccent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
