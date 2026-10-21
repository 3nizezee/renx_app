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
    if (mounted) {
      setState(() {
        _isPluginInstalled = plugin;
        _hasFullStorage = storage;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'การตั้งค่าระบบและสถาปัตยกรรมเอนจิน',
          style: TextStyle(
            color: Color(0xFFF3F6FC),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFF171C29),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF3B82F6),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Core Engine Specification Card
                _buildSectionCard(
                  icon: Icons.memory_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'RenPlay Core Engine (AST VM)',
                  badgeText: 'ACTIVE',
                  badgeColor: const Color(0xFF10B981),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'เอนจินในตัวแอปสำหรับอ่านและรันเกม Ren\'Py ของ PC โดยตรง ไม่ใช้สคริปต์จำลองหรือเกมตัวอย่าง:',
                        style: TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 10),
                      _TechSpecRow(
                        label: 'Binary Script (.rpyc)',
                        detail:
                            'ถอดรหัสคอนเทนเนอร์ RENPY RPC2, Zlib และ Python Pickle Protocols 0–5',
                      ),
                      _TechSpecRow(
                        label: 'Archive Reader (.rpa)',
                        detail:
                            'เมานต์ไฟล์คลังข้อมูล RPA-3.0 / RPA-2.0 พร้อมถอดรหัส XOR Index แบบสุ่มตำแหน่ง',
                      ),
                      _TechSpecRow(
                        label: 'Text Script (.rpy)',
                        detail:
                            'ตัวแปลภาษาแบบคำนวณย่อหน้า รองรับ label, menu, if/elif/else, jump, call, python',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Storage Permission Card
                _buildSectionCard(
                  icon: _hasFullStorage
                      ? Icons.folder_special_rounded
                      : Icons.lock_outline_rounded,
                  iconColor: _hasFullStorage
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFFF59E0B),
                  title: 'สิทธิ์การเข้าถึงพื้นที่จัดเก็บข้อมูล (Storage)',
                  badgeText: _hasFullStorage ? 'GRANTED' : 'REQUIRED',
                  badgeColor: _hasFullStorage
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFFF59E0B),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasFullStorage
                            ? 'ได้รับสิทธิ์เข้าถึงไฟล์ทั้งหมดแล้ว สามารถอ่านโฟลเดอร์เกมและไฟล์ .rpa จากทุกโฟลเดอร์ในเครื่องได้'
                            : 'จำเป็นต้องเปิดสิทธิ์ All Files Access บน Android 11 ขึ้นไป เพื่อให้แอปอ่านไฟล์ .rpyc และ .rpa ในโฟลเดอร์ Download ได้',
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      if (!_hasFullStorage) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            await RenpyBridge.requestAllFilesAccess();
                            await _checkStatus();
                          },
                          icon: const Icon(
                            Icons.verified_user_rounded,
                            size: 17,
                          ),
                          label: const Text('เปิดหน้าตั้งค่าสิทธิ์เข้าถึงไฟล์'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 3. External Runtime Bridge Card
                _buildSectionCard(
                  icon: Icons.hub_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  title: 'External Runtime Bridge (JoiPlay Plugin)',
                  badgeText: _isPluginInstalled ? 'DETECTED' : 'OPTIONAL',
                  badgeColor: _isPluginInstalled
                      ? const Color(0xFF06B6D4)
                      : const Color(0xFF64748B),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPluginInstalled
                            ? 'ตรวจพบปลั๊กอินภายนอกบนอุปกรณ์ สามารถสลับไปรันผ่านปลั๊กอินภายนอกได้จากเมนูในเกม'
                            : 'ทางเลือกเสริมสำหรับเกมที่ใช้โมดูล C-Extension เฉพาะทาง สามารถดาวน์โหลดได้จากลิงก์ทางการด้านล่าง',
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              foregroundColor: const Color(0xFFF3F6FC),
                            ),
                            onPressed: () =>
                                RenpyBridge.showPluginDownloadDialog(context),
                            icon: const Icon(Icons.download_rounded, size: 17),
                            label: const Text('จัดการแหล่งดาวน์โหลด'),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFCBD5E1),
                              side: const BorderSide(color: Color(0xFF232A3B)),
                            ),
                            onPressed: () => RenpyBridge.openUrl(
                              RenpyBridge.officialPatreonUrl,
                            ),
                            icon: const Icon(Icons.public_rounded, size: 16),
                            label: const Text('Patreon'),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFCBD5E1),
                              side: const BorderSide(color: Color(0xFF232A3B)),
                            ),
                            onPressed: () => RenpyBridge.openUrl(
                              RenpyBridge.officialGithubUrl,
                            ),
                            icon: const Icon(Icons.code_rounded, size: 16),
                            label: const Text('GitHub'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Operation Guide Card
                _buildSectionCard(
                  icon: Icons.integration_instructions_rounded,
                  iconColor: const Color(0xFF60A5FA),
                  title: 'ขั้นตอนการนำเกม PC มาเล่นบนมือถือ',
                  badgeText: 'GUIDE',
                  badgeColor: const Color(0xFF64748B),
                  child: const Column(
                    children: [
                      _StepItem(
                        number: '01',
                        text:
                            'แตกไฟล์เกม Ren\'Py ของ PC ลงในเครื่อง (เช่นในโฟลเดอร์ Download) โดยให้มีโฟลเดอร์ย่อย game/ อยู่ครบถ้วน',
                      ),
                      _StepItem(
                        number: '02',
                        text:
                            'กดปุ่ม "นำเข้าเกม" ที่หน้าคลังเกม แล้วเลือกโฟลเดอร์หลักของเกม',
                      ),
                      _StepItem(
                        number: '03',
                        text:
                            'ระบบจะสแกนหาไฟล์ .rpa, .rpyc และ .rpy พร้อมดึงชื่อเกมและภาพปกจากในคลังข้อมูลให้อัตโนมัติ',
                      ),
                      _StepItem(
                        number: '04',
                        text:
                            'กด PLAY เพื่อรันเกมจริง พร้อมใช้แถบควบคุม HUD (MENU, LOG, BACK, HIDE, SKIP, AUTO, NEXT) และระบบ Save/Load 4 ช่อง',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11151F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232A3B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withOpacity(0.45)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFF171C29)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _TechSpecRow extends StatelessWidget {
  final String label;
  final String detail;

  const _TechSpecRow({
    required this.label,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Color(0xFF3B82F6),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF94A3B8),
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      color: Color(0xFFF3F6FC),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: detail),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String number;
  final String text;

  const _StepItem({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF171C29),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF232A3B)),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
