import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show User;
import 'models/approve_add_time_log.dart'; // Ensure this model is updated as well

// --- Helper Functions ---
String _formatTimeOfDayToString(TimeOfDay tod) {
  final now = DateTime.now();
  final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
  final format = DateFormat.Hm();
  return format.format(dt);
}

String _formatThaiDate(DateTime date) {
  final DateFormat formatter = DateFormat('d MMMM yyyy', 'th');
  return formatter.format(date);
}

Color _getStateColor(String state) {
  switch (state) {
    case 'รออนุมัติ':
      return Colors.amber.shade700;
    case 'อนุมัติ':
      return Colors.green.shade700;
    case 'ไม่อนุมัติ':
      return Colors.red.shade700;
    case 'ยกเลิก': // Added new case for 'ยกเลิก'
      return Colors.blueGrey.shade700;
    default:
      return Colors.grey.shade700;
  }
}

Color _getStateBackgroundColor(String state) {
  switch (state) {
    case 'รออนุมัติ':
      return Colors.amber.shade100;
    case 'อนุมัติ':
      return Colors.green.shade100;
    case 'ไม่อนุมัติ':
      return Colors.red.shade100;
    case 'ยกเลิก': // Added new case for 'ยกเลิก'
      return Colors.blueGrey.shade100;
    default:
      return Colors.grey.shade100;
  }
}
// --- End Helper Functions ---

class ApproveAddTimeScreen extends StatefulWidget {
  final User user;

  const ApproveAddTimeScreen({super.key, required this.user});

  @override
  State<ApproveAddTimeScreen> createState() => ApproveAddTimeScreenState();
}

class ApproveAddTimeScreenState extends State<ApproveAddTimeScreen> {
  // GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  String? _errorMessage;
  List<ApproveAddTimeLog> _pendingRequests = [];
  List<ApproveAddTimeLog> _historyRequests = [];

  static const String _fetchApiUrl =
      'https://npdhrms.com/api/approve_add_time_screen_test.php';
  static const String _processApiUrl =
      'https://npdhrms.com/api/approve_add_time_screen_test.php';

  bool _needsRefresh = true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('th', null);
  }

  Future<void> refreshData() async {
    debugPrint('ApproveAddTimeScreen: refreshData() called.');
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _pendingRequests = [];
        _historyRequests = [];
      });
    }
    await _fetchRequests();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsRefresh) {
      _needsRefresh = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        refreshData();
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchRequests() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _pendingRequests = [];
        _historyRequests = [];
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse('$_fetchApiUrl?user_id=${widget.user.id}'),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint(
          'Fetch API Request URL: $_fetchApiUrl?user_id=${widget.user.id}');
      debugPrint('Fetch API Response Status: ${response.statusCode}');
      debugPrint('Fetch API Response Body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          _errorMessage = 'API response body is empty.';
          debugPrint('Error: API response body is empty.');
          if (mounted)
            setState(() {
              _isLoading = false;
            });
          return;
        }
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['status'] == 'success') {
          _pendingRequests =
              (responseData['data']?['pending_requests'] as List?)
                      ?.map((json) => ApproveAddTimeLog.fromJson(json))
                      .toList() ??
                  [];
          _historyRequests =
              (responseData['data']?['history_requests'] as List?)
                      ?.map((json) => ApproveAddTimeLog.fromJson(json))
                      .toList() ??
                  [];
          _errorMessage = null;
        } else {
          _errorMessage = responseData['message'] ?? 'Failed to load requests.';
        }
      } else {
        _errorMessage =
            'Error: ${response.statusCode} - ${response.reasonPhrase ?? 'Unknown Error'}';
        try {
          final Map<String, dynamic> errorData = json.decode(response.body);
          if (errorData.containsKey('message')) {
            _errorMessage =
                'Error: ${response.statusCode} - ${errorData['message']}';
          }
        } catch (e) {
          debugPrint('Failed to parse error body: $e');
        }
      }
    } on TimeoutException {
      _errorMessage = 'การเชื่อมต่อล่าช้าเกินกำหนด. โปรดลองใหม่อีกครั้ง';
    } on FormatException catch (e) {
      _errorMessage = 'รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์. ($e)';
      debugPrint('FormatException during _fetchRequests: $e');
    } catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e';
      debugPrint('Exception during _fetchRequests: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _processRequest(int requestId, String action,
      {String? reason, String? newState}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final response = await http.post(
        Uri.parse(_processApiUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'user_id': widget.user.id.toString(),
          'request_id': requestId.toString(),
          'action': action,
          if (reason != null) 'reason': reason,
          if (newState != null) 'new_state': newState,
        },
      ).timeout(const Duration(seconds: 25));

      debugPrint('Process API Response Status: ${response.statusCode}');
      debugPrint('Process API Response Body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          _showSnackBar('API response body is empty after process.',
              isError: true);
          debugPrint('Error: API response body is empty after process.');
          if (mounted)
            setState(() {
              _isLoading = false;
            });
          return;
        }
        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData['status'] == 'success') {
          _showSnackBar(responseData['message'] ?? 'ดำเนินการสำเร็จ',
              isError: false);
          await _fetchRequests();
        } else {
          _showSnackBar(responseData['message'] ?? 'ดำเนินการไม่สำเร็จ',
              isError: true);
        }
      } else {
        String serverMessage =
            'Error: ${response.statusCode} - ${response.reasonPhrase ?? 'Unknown Error'}';
        try {
          final Map<String, dynamic> errorData = json.decode(response.body);
          if (errorData.containsKey('message')) {
            serverMessage =
                'Error: ${response.statusCode} - ${errorData['message']}';
          }
        } catch (e) {
          debugPrint('Failed to parse error body for process API: $e');
        }
        _showSnackBar(serverMessage, isError: true);
      }
    } on TimeoutException {
      _showSnackBar('การเชื่อมต่อล่าช้าเกินกำหนด', isError: true);
    } on FormatException catch (e) {
      _showSnackBar('รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์หลังการประมวลผล. ($e)',
          isError: true);
      debugPrint('FormatException during _processRequest: $e');
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาด: $e', isError: true);
      debugPrint('Exception during _processRequest: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).primaryColor,
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  // ฟังก์ชันแสดง popup ไฟล์แนบ
  // ✅ ฟังก์ชันเปิดไฟล์แนบ (Popup + กรอบ + Zoom ได้)
  void _openAttachment(String filePath) {
    final fullUrl = filePath.startsWith('http')
        ? filePath
        : 'https://npdhrms.com/api/$filePath';

    debugPrint("📂 กำลังเปิดไฟล์แนบ: $fullUrl"); // ✅ log path

    if (filePath.endsWith('.jpg') ||
        filePath.endsWith('.jpeg') ||
        filePath.endsWith('.png')) {
      // แสดงภาพใน popup พร้อมกรอบ
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // มนเล็กน้อย
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.grey.shade300, width: 2), // ✅ กรอบเรียบๆ
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            padding: const EdgeInsets.all(8),
            child: InteractiveViewer(
              child: Image.network(
                fullUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Text(
                    'โหลดไฟล์ไม่สำเร็จ',
                    style: GoogleFonts.kanit(color: Colors.red)),
              ),
            ),
          ),
        ),
      );
    } else if (filePath.endsWith('.pdf')) {
      launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
    } else {
      launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showDisapproveDialog(int requestId) async {
    final TextEditingController reasonController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('ไม่อนุมัติคำขอเพิ่มเวลา', style: GoogleFonts.kanit()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'เหตุผลในการไม่อนุมัติ',
                    labelStyle: GoogleFonts.kanit(),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('ยกเลิก',
                  style: GoogleFonts.kanit(color: Colors.grey.shade700)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              child: Text('ยืนยันไม่อนุมัติ',
                  style: GoogleFonts.kanit(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _processRequest(requestId, 'disapprove',
                    reason: reasonController.text);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditStatusDialog(ApproveAddTimeLog request) async {
    final TextEditingController reasonController =
        TextEditingController(text: request.reason);
    String selectedState = request.state;

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              title:
                  Text('แก้ไขสถานะคำขอเพิ่มเวลา', style: GoogleFonts.kanit()),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      value: selectedState,
                      decoration: InputDecoration(
                        labelText: 'สถานะใหม่',
                        labelStyle: GoogleFonts.kanit(),
                        border: const OutlineInputBorder(),
                      ),
                      items: <String>[
                        'รออนุมัติ',
                        'อนุมัติ',
                        'ไม่อนุมัติ',
                        'ยกเลิก'
                      ].map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value, style: GoogleFonts.kanit()),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setStateDialog(() {
                            selectedState = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        labelText: 'เหตุผล (หากมีการเปลี่ยนแปลงสถานะหรือแก้ไข)',
                        labelStyle: GoogleFonts.kanit(),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('ยกเลิก',
                      style: GoogleFonts.kanit(color: Colors.grey.shade700)),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
                ElevatedButton(
                  child: Text('บันทึกการแก้ไข',
                      style: GoogleFonts.kanit(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _processRequest(request.id, 'edit_status',
                        reason: reasonController.text, newState: selectedState);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Helper widget specifically for rows inside dialogs
  Widget _buildInfoRowInDialog(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.kanit(color: Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }

  // Function to show full details in a dialog
  Future<void> _showDetailDialog(ApproveAddTimeLog request) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('รายละเอียดคำขอเพิ่มเวลา', style: GoogleFonts.kanit()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildInfoRowInDialog(
                  'ชื่อผู้ขอ:',
                  (request.requesterFirstname?.isNotEmpty == true ||
                          request.requesterLastname?.isNotEmpty == true)
                      ? '${request.requesterFirstname ?? ''} ${request.requesterLastname ?? ''}'
                      : (request.username ?? 'ไม่ระบุชื่อ'),
                ),
                _buildInfoRowInDialog(
                    'วันที่ทำงาน:', _formatThaiDate(request.workDate)),
                _buildInfoRowInDialog(
                    'เวลาเข้า:', _formatTimeOfDayToString(request.checkinTime)),
                _buildInfoRowInDialog(
                    'เวลาออก:', _formatTimeOfDayToString(request.checkoutTime)),
                _buildInfoRowInDialog('แผนก:', request.department),
                _buildInfoRowInDialog('ตำแหน่ง:', request.position),
                if (request.reasonType != null &&
                    request.reasonType!.isNotEmpty)
                  _buildInfoRowInDialog(
                      'ประเภทเพิ่มเวลา:', request.reasonType!),
                if (request.userNote != null && request.userNote!.isNotEmpty)
                  _buildInfoRowInDialog('หมายเหตุผู้ขอ:', request.userNote!),
                _buildInfoRowInDialog('สถานะ:', request.state),
                if (request.reason != null && request.reason!.isNotEmpty)
                  _buildInfoRowInDialog(
                      'เหตุผล (ไม่อนุมัติ):', request.reason!),
                _buildInfoRowInDialog(
                    'ส่งคำขอเมื่อ:',
                    DateFormat('d/M/yyyy HH:mm', 'th')
                        .format(request.createdAt!)),
                if (request.approvedBy != null)
                  _buildInfoRowInDialog('ผู้อนุมัติ:',
                      '${request.approverFirstname ?? ''} ${request.approverLastname ?? ''}'),
                if (request.approvedAt != null)
                  _buildInfoRowInDialog(
                      'อนุมัติเมื่อ:',
                      DateFormat('d/M/yyyy HH:mm', 'th')
                          .format(request.approvedAt!)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('ปิด',
                  style: GoogleFonts.kanit(color: Colors.grey.shade700)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Helper widget to build info rows for readability (used in main list)
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.kanit(color: Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color greenColor = Colors.green;
    final Color redColor = Colors.red;
    final Color orangeColor = Colors.orange.shade700;
    final Color blueColor = Colors.blue.shade700;
    final Color foregroundColor = Colors.white;

    Widget _buildActionButton({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      required Color backgroundColor,
    }) {
      return Expanded(
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label,
              style:
                  GoogleFonts.kanit(fontSize: 13, fontWeight: FontWeight.w500)),
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 2,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('คำขออนุมัติเพิ่มเวลา'),
      ),
      body: _isLoading &&
              _pendingRequests.isEmpty &&
              _historyRequests.isEmpty &&
              _errorMessage == null
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : RefreshIndicator(
              onRefresh: _fetchRequests,
              color: primaryColor,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Center(
                        child: Column(
                          children: [
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _fetchRequests,
                              icon: const Icon(Icons.refresh),
                              label: const Text('ลองอีกครั้ง'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // --- Pending Requests Section ---
                  Text(
                    'รายการคำขอเพิ่มเวลาที่รออนุมัติ',
                    style: GoogleFonts.kanit(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _pendingRequests.isEmpty && !_isLoading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'ยังไม่มีคำขอเพิ่มเวลาที่รออนุมัติ',
                              style: GoogleFonts.kanit(
                                  fontSize: 16, color: Colors.grey.shade600),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _pendingRequests.length,
                          itemBuilder: (context, index) {
                            final request = _pendingRequests[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: _getStateBackgroundColor(
                                        request.state)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          (request.requesterFirstname
                                                          ?.isNotEmpty ==
                                                      true ||
                                                  request.requesterLastname
                                                          ?.isNotEmpty ==
                                                      true)
                                              ? '${request.requesterFirstname ?? ''} ${request.requesterLastname ?? ''}'
                                              : (request.username ??
                                                  'ไม่ระบุชื่อ'),
                                          style: GoogleFonts.kanit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                _getStateColor(request.state),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            request.state,
                                            style: GoogleFonts.kanit(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 20, thickness: 1),
                                    _buildInfoRow(
                                      'ชื่อผู้ขอ:',
                                      (request.requesterFirstname?.isNotEmpty ==
                                                  true ||
                                              request.requesterLastname
                                                      ?.isNotEmpty ==
                                                  true)
                                          ? '${request.requesterFirstname ?? ''} ${request.requesterLastname ?? ''}'
                                          : (request.username ?? 'ไม่ระบุชื่อ'),
                                    ),
                                    _buildInfoRow('วันที่ทำงาน:',
                                        _formatThaiDate(request.workDate)),
                                    _buildInfoRow(
                                        'เวลาเข้า:',
                                        _formatTimeOfDayToString(
                                            request.checkinTime)),
                                    _buildInfoRow(
                                        'เวลาออก:',
                                        _formatTimeOfDayToString(
                                            request.checkoutTime)),
                                    _buildInfoRow('แผนก:', request.department),
                                    _buildInfoRow('ตำแหน่ง:', request.position),

                                    if (request.reasonType != null &&
                                        request.reasonType!.isNotEmpty)
                                      _buildInfoRow('ประเภทเพิ่มเวลา:',
                                          request.reasonType!),

                                    if (request.userNote != null &&
                                        request.userNote!.isNotEmpty)
                                      _buildInfoRow(
                                          'หมายเหตุผู้ขอ:', request.userNote!),
                                    // Action Buttons for Pending Requests

                                    if (request.filePath != null &&
                                        request.filePath!.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () =>
                                            _openAttachment(request.filePath!),
                                        icon: const Icon(Icons.attach_file,
                                            color: Colors.blue),
                                        label: Text(
                                          'ดูไฟล์แนบ',
                                          style: GoogleFonts.kanit(
                                              color: Colors.blue),
                                        ),
                                      ),

                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        _buildActionButton(
                                          icon: Icons.info_outline,
                                          label: 'รายละเอียด',
                                          onPressed: () =>
                                              _showDetailDialog(request),
                                          backgroundColor: blueColor,
                                        ),
                                        const SizedBox(width: 8),
                                        _buildActionButton(
                                          icon: Icons.check_circle_outline,
                                          label: 'อนุมัติ',
                                          onPressed: () => _processRequest(
                                              request.id, 'approve'),
                                          backgroundColor: greenColor,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(
                                        height:
                                            8), // Space between rows of buttons
                                    Row(
                                      children: [
                                        _buildActionButton(
                                          icon: Icons.cancel_outlined,
                                          label: 'ไม่อนุมัติ',
                                          onPressed: () =>
                                              _showDisapproveDialog(request.id),
                                          backgroundColor: redColor,
                                        ),
                                        const SizedBox(width: 8),
                                        _buildActionButton(
                                          icon: Icons.edit,
                                          label: 'แก้ไข',
                                          onPressed: () =>
                                              _showEditStatusDialog(request),
                                          backgroundColor: orangeColor,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                  const SizedBox(height: 32),

                  // --- History Requests Section ---
                  Text(
                    'ประวัติการเพิ่มเวลา (7 วันล่าสุด)',
                    style: GoogleFonts.kanit(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _historyRequests.isEmpty && !_isLoading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'ยังไม่มีประวัติคำขอเพิ่มเวลาใน 7 วันล่าสุด',
                              style: GoogleFonts.kanit(
                                  fontSize: 16, color: Colors.grey.shade600),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _historyRequests.length,
                          itemBuilder: (context, index) {
                            final request = _historyRequests[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: _getStateBackgroundColor(
                                        request.state)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${request.requesterFirstname ?? ''} ${request.requesterLastname ?? ''}',
                                          style: GoogleFonts.kanit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                _getStateColor(request.state),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            request.state,
                                            style: GoogleFonts.kanit(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 20, thickness: 1),
                                    _buildInfoRow(
                                      'ชื่อผู้ขอ:',
                                      (request.requesterFirstname?.isNotEmpty ==
                                                  true ||
                                              request.requesterLastname
                                                      ?.isNotEmpty ==
                                                  true)
                                          ? '${request.requesterFirstname ?? ''} ${request.requesterLastname ?? ''}'
                                          : (request.username ?? 'ไม่ระบุชื่อ'),
                                    ),

                                    _buildInfoRow('วันที่ทำงาน:',
                                        _formatThaiDate(request.workDate)),
                                    _buildInfoRow(
                                        'เวลาเข้า:',
                                        _formatTimeOfDayToString(
                                            request.checkinTime)),
                                    _buildInfoRow(
                                        'เวลาออก:',
                                        _formatTimeOfDayToString(
                                            request.checkoutTime)),
                                    _buildInfoRow('แผนก:', request.department),
                                    _buildInfoRow('ตำแหน่ง:', request.position),
                                    if (request.reasonType != null &&
                                        request.reasonType!.isNotEmpty)
                                      _buildInfoRow('ประเภทเพิ่มเวลา:',
                                          request.reasonType!),

                                    if (request.userNote != null &&
                                        request.userNote!.isNotEmpty)
                                      _buildInfoRow(
                                          'หมายเหตุผู้ขอ:', request.userNote!),
                                    if (request.reason != null &&
                                        request.reason!.isNotEmpty)
                                      _buildInfoRow('เหตุผล (ไม่อนุมัติ):',
                                          request.reason!),
                                    if (request.approvedBy != null)
                                      _buildInfoRow('ผู้อนุมัติ:',
                                          '${request.approverFirstname ?? ''} ${request.approverLastname ?? ''}'),
                                    if (request.approvedAt != null)
                                      _buildInfoRow(
                                          'อนุมัติเมื่อ:',
                                          DateFormat('d/M/yyyy HH:mm', 'th')
                                              .format(request.approvedAt!)),
                                    if (request.filePath != null &&
                                        request.filePath!.isNotEmpty)
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: TextButton.icon(
                                          onPressed: () => _openAttachment(
                                              request.filePath!),
                                          icon: const Icon(Icons.attach_file,
                                              size: 18, color: Colors.blue),
                                          label: Text('ดูไฟล์แนบ',
                                              style: GoogleFonts.kanit(
                                                  color: Colors.blue)),
                                        ),
                                      ),
                                    // No view details or edit/approve/disapprove buttons for history
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }
}
