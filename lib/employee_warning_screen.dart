import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'odoo_rpc_service.dart';
import 'notification_service.dart';
import 'ui/app_theme.dart';

/// หน้าจอแสดงรายการใบเตือนพนักงาน
class EmployeeWarningScreen extends StatefulWidget {
  final String employeeCode;

  const EmployeeWarningScreen({super.key, required this.employeeCode});

  @override
  State<EmployeeWarningScreen> createState() => _EmployeeWarningScreenState();
}

class _EmployeeWarningScreenState extends State<EmployeeWarningScreen> {
  // ✅ อ่านสีจาก Theme ใน build context (ไม่ใช้ static แล้ว)
  Color get npdYellow => Theme.of(context).colorScheme.primary;
  Color get npdBlack => Theme.of(context).colorScheme.onPrimary;

  bool _loading = true;
  Map<String, dynamic> _data = {};
  final Set<int> _downloadingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    // ✅ ยกเลิกแจ้งเตือนใบเตือนทันทีเมื่อเปิดหน้า (ถือว่าอ่านแล้ว)
    _dismissWarningNotification();
  }

  Future<void> _dismissWarningNotification() async {
    try {
      await NotificationService().cancelWarningNotification();
      // บันทึกว่าอ่านใบเตือนแล้ว
      final prefs = await SharedPreferences.getInstance();
      final count =
          await OdooRpcService().getEmployeeWarningCount(widget.employeeCode);
      // null = ดึงไม่ได้ (เน็ตหลุด) อย่าเขียนทับสถานะอ่านแล้วด้วยค่ามั่ว
      if (count == null) return;
      await prefs.setInt(
          'warning_read_count_${widget.employeeCode}', count);
      // อ่านแล้ว → กันไม่ให้แจ้งเตือนใบเดิมเด้งซ้ำในรอบเช็คถัดไป
      await prefs.setInt(
          'warning_notified_count_${widget.employeeCode}', count);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await OdooRpcService().getEmployeeWarnings(widget.employeeCode);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('โหลดข้อมูลไม่สำเร็จ: $e', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.ibmPlexSansThai()),
        backgroundColor: error ? Colors.red.shade700 : AppColors.text,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openAttachment(Map<String, dynamic> line) async {
    final int attachmentId = (line['attachment_id'] as num?)?.toInt() ?? 0;
    final String filename = (line['attachment_filename'] ?? 'attachment').toString();
    if (attachmentId == 0) {
      _showSnack('ไม่พบไฟล์แนบ', error: true);
      return;
    }
    setState(() => _downloadingIds.add(attachmentId));

    try {
      // ดึง bytes ผ่าน controller ก่อน
      var bytes = await OdooRpcService().getWarningAttachmentBytes(attachmentId);
      // ถ้าล้มเหลว ลองผ่าน ir.attachment RPC
      bytes ??= await OdooRpcService().getAttachmentDatasById(attachmentId);

      if (bytes == null || bytes.isEmpty) {
        _showSnack('ดาวน์โหลดไฟล์ไม่สำเร็จ', error: true);
        return;
      }

      final dir = await getTemporaryDirectory();
      final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = '${dir.path}/$safeName';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);

      await OpenFilex.open(path);
    } catch (e) {
      _showSnack('เปิดไฟล์ไม่สำเร็จ: $e', error: true);
    } finally {
      if (mounted) setState(() => _downloadingIds.remove(attachmentId));
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final d = DateTime.parse(iso);
      return DateFormat('d MMM y', 'th').format(d);
    } catch (_) {
      return iso;
    }
  }

  Color _typeColor(String type) {
    return type == 'written' ? Colors.red.shade600 : Colors.orange.shade600;
  }

  IconData _typeIcon(String type) {
    return type == 'written' ? Icons.description_rounded : Icons.record_voice_over_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final emp = (_data['employee'] as Map?) ?? {};
    final lines = (_data['lines'] as List?) ?? [];
    final warningCount = (_data['warning_count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppGradientBar(
        title: Text('ใบเตือนพนักงาน',
            style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: npdYellow))
          : RefreshIndicator(
              color: npdYellow,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeaderCard(emp, warningCount),
                  const SizedBox(height: 16),
                  if (lines.isEmpty)
                    _buildEmptyState()
                  else
                    ...lines.map<Widget>((l) =>
                        _buildWarningCard(Map<String, dynamic>.from(l))),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard(Map emp, int warningCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: npdYellow.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    color: Colors.red.shade700, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${emp['firstname'] ?? ''} ${emp['lastname'] ?? ''}'.trim(),
                      style: GoogleFonts.ibmPlexSansThai(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text),
                    ),
                    Text(
                      'รหัส: ${emp['code'] ?? '-'}',
                      style: GoogleFonts.ibmPlexSansThai(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$warningCount ครั้ง',
                  style: GoogleFonts.ibmPlexSansThai(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _buildKV('ตำแหน่ง', emp['position']),
          _buildKV('สาขา', emp['branch']),
          _buildKV('แผนก', emp['department']),
        ],
      ),
    );
  }

  Widget _buildKV(String k, dynamic v) {
    final value = (v == null || v.toString().isEmpty) ? '-' : v.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(k,
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF333333))),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 56, color: Colors.green.shade400),
          const SizedBox(height: 12),
          Text(
            'ไม่มีใบเตือน',
            style: GoogleFonts.ibmPlexSansThai(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            'ไม่พบประวัติใบเตือนในระบบ',
            style: GoogleFonts.ibmPlexSansThai(
                fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard(Map<String, dynamic> line) {
    final String type = (line['warning_type'] ?? '').toString();
    final bool hasAtt = line['has_attachment'] == true;
    final int attId = (line['attachment_id'] as num?)?.toInt() ?? 0;
    final bool downloading = _downloadingIds.contains(attId);
    final String numDisplay = (line['warning_number_display'] ?? '').toString();
    final String typeDisplay = (line['warning_type_display'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _typeColor(type).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _typeColor(type).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Icon(_typeIcon(type), color: _typeColor(type), size: 20),
                const SizedBox(width: 8),
                Text(
                  numDisplay,
                  style: GoogleFonts.ibmPlexSansThai(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _typeColor(type)),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _typeColor(type),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    typeDisplay,
                    style: GoogleFonts.ibmPlexSansThai(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 15, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(line['warning_date']?.toString()),
                      style: GoogleFonts.ibmPlexSansThai(
                          fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'เรื่อง',
                  style: GoogleFonts.ibmPlexSansThai(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  (line['subject'] ?? '-').toString(),
                  style: GoogleFonts.ibmPlexSansThai(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text),
                ),
                if ((line['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'รายละเอียดเพิ่มเติม',
                    style: GoogleFonts.ibmPlexSansThai(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line['description'].toString(),
                    style: GoogleFonts.ibmPlexSansThai(
                        fontSize: 13, color: const Color(0xFF444444)),
                  ),
                ],
                if (hasAtt) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: downloading ? null : () => _openAttachment(line),
                      icon: downloading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: npdBlack))
                          : const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(
                        downloading
                            ? 'กำลังเปิดไฟล์...'
                            : 'เปิดไฟล์แนบ (${line['attachment_filename'] ?? 'ไฟล์'})',
                        style: GoogleFonts.ibmPlexSansThai(
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: npdYellow,
                        foregroundColor: npdBlack,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
