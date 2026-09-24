import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'main.dart' show User;
import 'models/leave_log.dart';
import 'utils/attachment_utils.dart';
import 'widgets/expandable_history_card.dart';
import 'ui/app_theme.dart';

/// หน้า "ประวัติการลาทั้งหมด" — เลือกดูย้อนหลังได้ทีละเดือน/ปี
/// รูปแบบเดียวกับ FullCheckinHistoryScreen ของเมนูลงเวลา
class FullLeaveHistoryScreen extends StatefulWidget {
  final User user;
  final int initialMonth;
  final int initialYear;

  const FullLeaveHistoryScreen({
    super.key,
    required this.user,
    required this.initialMonth,
    required this.initialYear,
  });

  @override
  State<FullLeaveHistoryScreen> createState() => _FullLeaveHistoryScreenState();
}

class _FullLeaveHistoryScreenState extends State<FullLeaveHistoryScreen> {
  static const String _apiUrl = 'https://npdhrms.com/api/get_leave_history.php';

  late int _selectedMonth;
  late int _selectedYear;
  bool _isLoading = true;
  List<LeaveLog> _leaves = [];
  String _errorMessage = '';

  static const List<String> _thaiMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
  ];

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth;
    _selectedYear = widget.initialYear;
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final String url =
        '$_apiUrl?user_id=${widget.user.id}&month=$_selectedMonth&year=$_selectedYear';

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['status'] == 'success') {
          final List<dynamic> list = data['data'] ?? [];
          setState(() {
            _leaves = list
                .map((e) => LeaveLog.fromJson(e as Map<String, dynamic>))
                .toList();
          });
        } else {
          setState(() =>
              _errorMessage = data['message'] ?? 'ไม่สามารถดึงข้อมูลได้');
        }
      } else {
        setState(() =>
            _errorMessage = 'เกิดข้อผิดพลาด: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'รออนุมัติ':
        return Colors.amber.shade700;
      case 'อนุมัติ':
        return Colors.green.shade700;
      case 'ไม่อนุมัติ':
        return Colors.red.shade700;
      case 'ยกเลิก':
        return Colors.blueGrey.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _formatThaiDate(DateTime date) =>
      DateFormat('d MMMM yyyy', 'th').format(date);

  String _formatTime(TimeOfDay tod) {
    final now = DateTime.now();
    return DateFormat('HH:mm')
        .format(DateTime(now.year, now.month, now.day, tod.hour, tod.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppGradientBar(
        title: Text('ประวัติการลาทั้งหมด',
            style: GoogleFonts.ibmPlexSansThai()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchHistory,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildMonthYearSelector(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'พบ ${_leaves.length} รายการ',
                  style: GoogleFonts.ibmPlexSansThai(
                      fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildMonthYearSelector() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.frame(Theme.of(context).colorScheme.primary)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedMonth,
                  isExpanded: true,
                  style: GoogleFonts.ibmPlexSansThai(
                      fontSize: 14, color: Colors.black),
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                        value: i + 1, child: Text(_thaiMonths[i])),
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedMonth = value);
                      _fetchHistory();
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.frame(Theme.of(context).colorScheme.primary)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedYear,
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 14, color: Colors.black),
                items: List.generate(5, (i) {
                  final int year = DateTime.now().year - 2 + i;
                  return DropdownMenuItem(
                      value: year, child: Text('${year + 543}'));
                }),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedYear = value);
                    _fetchHistory();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.ibmPlexSansThai(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchHistory,
                icon: const Icon(Icons.refresh),
                label:
                    Text('ลองอีกครั้ง', style: GoogleFonts.ibmPlexSansThai()),
              ),
            ],
          ),
        ),
      );
    }
    if (_leaves.isEmpty) {
      return Center(
        child: Text(
          'ไม่มีข้อมูลการลาในเดือนนี้',
          style: GoogleFonts.ibmPlexSansThai(
              fontSize: 16, color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _leaves.length,
        itemBuilder: (context, index) => _buildLeaveCard(_leaves[index]),
      ),
    );
  }

  Widget _buildLeaveCard(LeaveLog leave) {
    final String dateLabel = leave.leaveStartDate == leave.leaveEndDate
        ? _formatThaiDate(leave.leaveStartDate)
        : '${_formatThaiDate(leave.leaveStartDate)} - ${_formatThaiDate(leave.leaveEndDate)}';

    return ExpandableHistoryCard(
      leadingIcon: Icons.event_note_rounded,
      accentColor: _getStateColor(leave.state),
      dateLabel: dateLabel,
      typeLabel: leave.leaveType,
      status: leave.state,
      statusColor: _getStateColor(leave.state),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'เวลาเริ่ม: ${_formatTime(leave.leaveStartTime)} น.  |  สิ้นสุด: ${_formatTime(leave.leaveEndTime)} น.',
            style: GoogleFonts.ibmPlexSansThai(
                fontSize: 13, color: Colors.grey.shade800),
          ),
          if (leave.note != null && leave.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'หมายเหตุ: ${leave.note}',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade700),
              ),
            ),
          if (leave.reason != null && leave.reason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'เหตุผล (ไม่อนุมัติ): ${leave.reason}',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13, color: Colors.red.shade700),
              ),
            ),
          if (leave.approverFirstname != null ||
              leave.approverLastname != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ผู้อนุมัติ: ${leave.approverFirstname ?? ''} ${leave.approverLastname ?? ''}',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13, color: Colors.grey.shade800),
              ),
            ),
          if (leave.approvedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'อนุมัติเมื่อ: ${DateFormat('d/M/yyyy HH:mm', 'th').format(leave.approvedAt!)}',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13, color: Colors.grey.shade800),
              ),
            ),
          if (leave.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ส่งคำขอเมื่อ: ${DateFormat('d/M/yyyy HH:mm', 'th').format(leave.createdAt!)}',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          buildAttachmentButton(
            context: context,
            filePath: leave.filePath,
            urlBuilder: buildLeaveAttachmentUrl,
          ),
        ],
      ),
    );
  }
}
