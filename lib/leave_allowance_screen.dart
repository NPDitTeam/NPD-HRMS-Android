import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import 'main.dart' show User; // ใช้ User model จาก main.dart

class LeaveAllowanceScreen extends StatefulWidget {
  final User user;

  const LeaveAllowanceScreen({super.key, required this.user});

  @override
  State<LeaveAllowanceScreen> createState() => _LeaveAllowanceScreenState();
}

class _LeaveAllowanceScreenState extends State<LeaveAllowanceScreen> {
  Map<String, dynamic>? _leaveData;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLeaveAllowance();
  }

  Future<void> _fetchLeaveAllowance() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final String employeeCode = widget.user.employeeCode ?? '';
    final String apiUrl =
        'https://npdhrms.com/api/get_leave_allowance.php?employee_code=$employeeCode';

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _leaveData = data['data'];
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'ไม่พบข้อมูลสิทธิ์การลา';
          });
        }
      } else {
        setState(() {
          _errorMessage =
              'เกิดข้อผิดพลาดในการเชื่อมต่อ: ${response.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Widget สำหรับแสดงรายการสิทธิ์การลาในรูปแบบหลอด
  // หมายเหตุ: parameter ที่สอง (remaining) คือจำนวนวันที่ "เหลือ" (ไม่ใช่ที่ใช้ไป)
  Widget _buildAllowanceListTile(String label, int? remaining, int? total) {
    // ✅ progress = สัดส่วนของวันที่ "เหลืออยู่"
    //   1.0 = เต็ม (ยังไม่เคยใช้)
    //   0.0 = หมดแล้ว
    double progress = 0.0;
    Color progressColor = Colors.grey;

    if (total != null && total > 0 && remaining != null) {
      // คลีนค่า: ป้องกัน remaining ติดลบ หรือ > total
      final r = remaining.clamp(0, total);
      progress = r / total;

      if (r <= 0) {
        // 🔘 หมดแล้ว → สีเทา
        progressColor = Colors.grey;
      } else if (r >= total) {
        // 🟢 เต็ม (ยังไม่เคยใช้) → สีเขียว
        progressColor = Colors.green;
      } else if (progress <= 0.25) {
        // 🔴 ใกล้หมด (เหลือ ≤ 25%) → สีแดง
        progressColor = Colors.red;
      } else {
        // 🟡 ใช้ไปแล้วบางส่วน → สีเหลือง
        progressColor = Colors.amber;
      }
    } else if ((total ?? 0) == 0) {
      // ไม่มีสิทธิ์ตั้งแต่แรก (total = 0)
      progress = 0.0;
      progressColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexSansThai(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'คงเหลือ: ${remaining ?? 0} / ทั้งหมด: ${total ?? 0}',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('สิทธิ์การลา', style: GoogleFonts.ibmPlexSansThai()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.ibmPlexSansThai(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchLeaveAllowance,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20.0, vertical: 15.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10.0),
                              child: Text(
                                'สรุปสิทธิ์การลาคงเหลือ',
                                style: GoogleFonts.ibmPlexSansThai(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Divider(height: 0, thickness: 1),
                            _buildAllowanceListTile(
                                _leaveData?['leave_personal_paid_used'] ??
                                    'ลากิจ (มีค่าจ้าง)',
                                _leaveData?[
                                    'leave_personal_paid_total_remaining'],
                                _leaveData?['leave_personal_paid_total']),
                            _buildAllowanceListTile(
                                _leaveData?['leave_personal_unpaid_used'] ??
                                    'ลากิจ (ไม่มีค่าจ้าง)',
                                _leaveData?[
                                    'leave_personal_unpaid_total_remaining'],
                                _leaveData?['leave_personal_unpaid_total']),
                            _buildAllowanceListTile(
                                _leaveData?['leave_sick_used'] ?? 'ลาป่วย',
                                _leaveData?['leave_sick_total_remaining'],
                                _leaveData?['leave_sick_total']),
                            _buildAllowanceListTile(
                                _leaveData?['leave_maternity_paid_used'] ??
                                    'ลาคลอด (มีค่าจ้าง)',
                                _leaveData?[
                                    'leave_maternity_paid_total_remaining'],
                                _leaveData?['leave_maternity_paid_total']),
                            _buildAllowanceListTile(
                                _leaveData?['leave_maternity_unpaid_used'] ??
                                    'ลาคลอด (ไม่มีค่าจ้าง)',
                                _leaveData?[
                                    'leave_maternity_unpaid_total_remaining'],
                                _leaveData?['leave_maternity_unpaid_total']),
                            _buildAllowanceListTile(
                                _leaveData?['leave_vacation_used'] ??
                                    'ลาพักร้อน',
                                _leaveData?['leave_vacation_total_remaining'],
                                _leaveData?['leave_vacation_total']),
                            _buildAllowanceListTile(
                                _leaveData?['leave_saturday_used'] ??
                                    'สิทธิหยุดวันเสาร์',
                                _leaveData?['leave_saturday_total_remaining'],
                                _leaveData?['leave_saturday_total']),
                            _buildAllowanceListTile(
                                _leaveData?['leave_emergency_used'] ??
                                    'ลาฉุกเฉิน',
                                _leaveData?['leave_emergency_total_remaining'],
                                _leaveData?['leave_emergency_total']),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
