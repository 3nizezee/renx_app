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
                // Built-in Engine Status Card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.greenAccent,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Built-in RenPlay Engine (ในตัวแอป)',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'พร้อมใช้งานทันที • รองรับไฟล์สคริปต์ .rpy / .rpyc, ฉากหลัง, ตัวละคร และ Save/Load',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Icon(
                              _isPluginInstalled
                                  ? Icons.extension_rounded
                                  : Icons.extension_off_rounded,
                              color: _isPluginInstalled
                                  ? Colors.cyanAccent
                                  : Colors.amber,
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'External JoiPlay Ren\'Py Plugin',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _isPluginInstalled
                                        ? 'ตรวจพบปลั๊กอินเสริมบนเครื่องแล้ว'
                                        : 'ปลั๊กอินเสริมภายนอก (ทางเลือกสำหรับเกม 3D/Python ขั้นสูง)',
                                    style: TextStyle(
                                      color: _isPluginInstalled
                                          ? Colors.cyanAccent
                                          : Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () =>
                                  RenpyBridge.showPluginDownloadDialog(context),
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('เปิดศูนย์ดาวน์โหลดปลั๊กอิน'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => RenpyBridge.openUrl(
                                  RenpyBridge.officialPatreonUrl),
                              icon: const Icon(Icons.public_rounded, size: 18),
                              label: const Text('Patreon ทางการ'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => RenpyBridge.openUrl(
                                  RenpyBridge.officialGithubUrl),
                              icon: const Icon(Icons.code_rounded, size: 18),
                              label: const Text('GitHub'),
                            ),
                          ],
                        ),
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
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
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
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.4),
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
                          'คัดลอกโฟลเดอร์เกม Ren\'Py ของ PC (ที่มีโฟลเดอร์ game และไฟล์ .exe) ลงในมือถือ เช่น ในโฟลเดอร์ Download',
                        ),
                        _stepRow(
                          '2',
                          'ในแอปนี้ กดปุ่ม "+ เพิ่มเกม" ที่หน้าหลัก แล้วเลือกโฟลเดอร์เกม หรือเลือกไฟล์ .exe ของเกม',
                        ),
                        _stepRow(
                          '3',
                          'ระบบจะตรวจสอบไฟล์สคริปต์ .rpy / .rpyc และดึงหน้าปกพร้อมตั้งค่าให้อัตโนมัติ',
                        ),
                        _stepRow(
                          '4',
                          'กดปุ่ม "เล่น" เพื่อเริ่มเกมผ่าน Built-in Engine ได้ทันที พร้อมใช้ปุ่มสัมผัสเสมือน (ESC, SKIP, AUTO, BACK, HIDE, NEXT) บนหน้าจอ!',
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
