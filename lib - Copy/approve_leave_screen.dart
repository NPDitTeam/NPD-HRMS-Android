import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:photo_view/photo_view.dart';

import 'main.dart' show User;
import 'models/leave_log.dart';

// --- Global Helper Functions (can stay global as they have no dependency on State/Context) ---
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

// --- End Global Helper Functions ---
String _formatThaiTime(TimeOfDay tod) {
  final now = DateTime.now();
  final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
  // ใช้ locale 'th' และเพิ่ม "น." ต่อท้าย
  final format = DateFormat('HH:mm', 'th');
  return '${format.format(dt)} น.';
}

class ApproveLeaveScreen extends StatefulWidget {
  final User user;

  const ApproveLeaveScreen({super.key, required this.user});

  @override
  State<ApproveLeaveScreen> createState() => ApproveLeaveScreenState();
}

class ApproveLeaveScreenState extends State<ApproveLeaveScreen> {
  // GlobalKey<FormState> _formKey = GlobalKey<FormState>(); // Note: _formKey is not used in this file. Can be removed if truly unused.
  bool _isLoading = true;
  String? _errorMessage;
  List<LeaveLog> _pendingRequests = [];
  List<LeaveLog> _historyRequests = [];

  final String _fetchApiUrl =
      'https://npdhrms.com/api/approve_leave_screen_test.php';
  final String _processApiUrl =
      'https://npdhrms.com/api/approve_leave_screen_test.php';

  final String _baseUploadsUrl =
      'https://npdhrms.com/'; // Base URL for uploaded files

  bool _needsRefresh = true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('th', null);
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

  // === All Helper Methods and Business Logic Methods are defined here, BEFORE build() ===

  // Public refreshData method for parent to call
  Future<void> refreshData() async {
    debugPrint('ApproveLeaveScreen: refreshData() called.');
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    await _fetchRequests();
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

  Color _getStateColor(String state) {
    switch (state) {
      case 'รออนุมัติ':
        return Colors.amber.shade700;
      case 'อนุมัติ':
        return Colors.green.shade700;
      case 'ไม่อนุมัติ':
        return Colors.red.shade700;
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
      default:
        return Colors.grey.shade100;
    }
  }

  bool _isImageFile(String? fileIdentifierOrExtension) {
    if (fileIdentifierOrExtension == null) return false;
    final lowerCaseIdentifier = fileIdentifierOrExtension.toLowerCase();
    String extension;
    if (lowerCaseIdentifier.contains('.')) {
      extension = lowerCaseIdentifier.split('.').last;
    } else {
      extension = lowerCaseIdentifier;
    }
    return extension == 'jpg' ||
        extension == 'jpeg' ||
        extension == 'png' ||
        extension == 'gif';
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: PhotoView(
                  imageProvider: NetworkImage(imageUrl),
                  backgroundDecoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 2,
                  enableRotation: true,
                  loadingBuilder: (context, event) {
                    if (event == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Center(
                      child: CircularProgressIndicator(
                        value: event.cumulativeBytesLoaded /
                            (event.expectedTotalBytes ??
                                event.cumulativeBytesLoaded + 1),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('PhotoView Error: $error');
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              size: 50, color: Colors.grey),
                          Text('ไม่สามารถโหลดรูปภาพได้',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16.0),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openFileUrl(String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      _showSnackBar('ไม่มีไฟล์แนบ', isError: true);
      return;
    }

    String finalPathOrUrl;
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      finalPathOrUrl = filePath;
    } else {
      String cleanedPath = filePath;
      if (cleanedPath.startsWith('../uploads/')) {
        cleanedPath = cleanedPath.substring('../uploads/'.length);
      } else if (cleanedPath.startsWith('uploads/')) {
        cleanedPath = cleanedPath.substring('uploads/'.length);
      }
      finalPathOrUrl = _baseUploadsUrl + 'uploads/' + cleanedPath;
    }

    final String fileExtension = finalPathOrUrl.split('.').last.toLowerCase();

    if (!_isImageFile(fileExtension)) {
      _showSnackBar(
          'ไม่รองรับไฟล์ประเภท .$fileExtension ไม่สามารถแสดงไฟล์นี้ได้ (รองรับเฉพาะรูปภาพ)',
          isError: true);
      debugPrint(
          'Attempted to open non-image file type: .$fileExtension for path: $finalPathOrUrl');
      return;
    }

    debugPrint(
        'Attempting to open file: $finalPathOrUrl (extension: .$fileExtension)');

    _showImageDialog(finalPathOrUrl);
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

      if (!mounted) return;

      debugPrint(
          'ApproveLeaveScreen Fetch API Response Status: ${response.statusCode}');
      debugPrint(
          'ApproveLeaveScreen Fetch API Response Body: ${response.body}');

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
                      ?.map((json) => LeaveLog.fromJson(json))
                      .toList() ??
                  [];
          _historyRequests =
              (responseData['data']?['history_requests'] as List?)
                      ?.map((json) => LeaveLog.fromJson(json))
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
          debugPrint('Failed to parse error body for fetch API: $e');
        }
      }
    } on TimeoutException {
      _errorMessage = 'การเชื่อมต่อล่าช้าเกินกำหนด. โปรดลองใหม่อีกครั้ง';
    } on FormatException catch (e) {
      _errorMessage = 'รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์. ($e)';
      debugPrint(
          'ApproveLeaveScreen FormatException during _fetchRequests: $e');
    } catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e';
      debugPrint('ApproveLeaveScreen Exception during _fetchRequests: $e');
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

      debugPrint(
          'ApproveLeaveScreen Process API Response Status: ${response.statusCode}');
      debugPrint(
          'ApproveLeaveScreen Process API Response Body: ${response.body}');

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
      debugPrint(
          'ApproveLeaveScreen FormatException during _processRequest: $e');
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาด: $e', isError: true);
      debugPrint('ApproveLeaveScreen Exception during _processRequest: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showDisapproveDialog(int requestId) async {
    final TextEditingController reasonController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('ไม่อนุมัติคำขอลา', style: GoogleFonts.kanit()),
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

  Future<void> _showEditStatusDialog(LeaveLog request) async {
    final TextEditingController reasonController =
        TextEditingController(text: request.reason);
    String selectedState = request.state;

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              title: Text('แก้ไขสถานะคำขอลา', style: GoogleFonts.kanit()),
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
                      items: <String>['รออนุมัติ', 'อนุมัติ', 'ไม่อนุมัติ']
                          .map<DropdownMenuItem<String>>((String value) {
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
  Future<void> _showDetailDialog(LeaveLog request) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('รายละเอียดคำขอลา', style: GoogleFonts.kanit()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildInfoRowInDialog('ชื่อผู้ขอ:',
                    '${request.requesterFirstname ?? ''} ${request.requesterLastname ?? ''}'),
                _buildInfoRowInDialog('ประเภทการลา:', request.leaveType),
                _buildInfoRowInDialog('วันที่ลาเริ่มต้น:',
                    _formatThaiDate(request.leaveStartDate)),
                _buildInfoRowInDialog('เวลาที่ลาเริ่มต้น:',
                    _formatThaiTime(request.leaveStartTime)),
                _buildInfoRowInDialog(
                    'เวลาที่ลาสิ้นสุด:', _formatThaiTime(request.leaveEndTime)),

                _buildInfoRowInDialog('เวลาที่ลาสิ้นสุด:',
                    _formatTimeOfDayToString(request.leaveEndTime)),
                _buildInfoRowInDialog('หมายเหตุ:', request.note ?? '-'),
                _buildInfoRowInDialog('แผนก:', request.department ?? '-'),
                _buildInfoRowInDialog('ตำแหน่ง:', request.position ?? '-'),

                // File Attachment Link in Dialog
                if (request.filePath != null && request.filePath!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text('เอกสารแนบ:',
                              style: GoogleFonts.kanit(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade700)),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () => _openFileUrl(request.filePath),
                            icon: const Icon(Icons.image,
                                size: 18), // Only image icon
                            label:
                                Text('ดูไฟล์แนบ', style: GoogleFonts.kanit()),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                              foregroundColor: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

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

  @override // The build method must be within the State class
  Widget build(BuildContext context) {
    // Define theme colors here for cleaner access within build
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color greenColor = Colors.green; // Assuming green for approve
    final Color redColor = Colors.red; // Assuming red for disapprove
    final Color orangeColor =
        Colors.orange.shade700; // Assuming orange for edit
    final Color blueColor = Colors.blue.shade700; // Assuming blue for details
    final Color foregroundColor = Colors.white; // Text color on colored buttons

    // Inner helper function for creating uniform buttons for pending requests
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
              style: GoogleFonts.kanit(
                  fontSize: 13,
                  fontWeight:
                      FontWeight.w500)), // Adjusted font size for better fit
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 8), // Adjusted padding
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(8)), // Rounded corners for buttons
            elevation: 2, // Little elevation
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('คำขออนุมัติการลา'),
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
                    'รายการคำขอลาที่รออนุมัติ',
                    style: GoogleFonts.kanit(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _pendingRequests.isEmpty && !_isLoading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'ยังไม่มีคำขอลาที่รออนุมัติ',
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
                                        'ประเภทการลา:', request.leaveType),
                                    _buildInfoRow(
                                        'วันที่ลา:',
                                        _formatThaiDate(
                                                request.leaveStartDate) +
                                            (request.leaveStartDate !=
                                                    request.leaveEndDate
                                                ? ' ถึง ${_formatThaiDate(request.leaveEndDate)}'
                                                : '')),
                                    _buildInfoRow('เวลา:',
                                        '${_formatThaiTime(request.leaveStartTime)} - ${_formatThaiTime(request.leaveEndTime)}'),

                                    if (request.note != null &&
                                        request.note!.isNotEmpty)
                                      _buildInfoRow('หมายเหตุ:', request.note!),
                                    if (request.department != null &&
                                        request.department!.isNotEmpty)
                                      _buildInfoRow(
                                          'แผนก:', request.department!),
                                    if (request.position != null &&
                                        request.position!.isNotEmpty)
                                      _buildInfoRow(
                                          'ตำแหน่ง:', request.position!),

                                    // Redesigned Action Buttons Layout for Pending Requests
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
                    'ประวัติการลา (7 วันล่าสุด)',
                    style: GoogleFonts.kanit(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _historyRequests.isEmpty && !_isLoading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'ยังไม่มีประวัติการลาใน 7 วันล่าสุด',
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
                                        'ประเภทการลา:', request.leaveType),
                                    _buildInfoRow(
                                        'วันที่ลา:',
                                        _formatThaiDate(
                                                request.leaveStartDate) +
                                            (request.leaveStartDate !=
                                                    request.leaveEndDate
                                                ? ' ถึง ${_formatThaiDate(request.leaveEndDate)}'
                                                : '')),
                                    _buildInfoRow('เวลา:',
                                        '${_formatThaiTime(request.leaveStartTime)} - ${_formatThaiTime(request.leaveEndTime)}'),

                                    if (request.note != null &&
                                        request.note!.isNotEmpty)
                                      _buildInfoRow('หมายเหตุ:', request.note!),
                                    if (request.department != null &&
                                        request.department!.isNotEmpty)
                                      _buildInfoRow(
                                          'แผนก:', request.department!),
                                    if (request.position != null &&
                                        request.position!.isNotEmpty)
                                      _buildInfoRow(
                                          'ตำแหน่ง:', request.position!),
                                    if (request.reason != null &&
                                        request.reason!.isNotEmpty)
                                      _buildInfoRow('เหตุผล (ไม่อนุมัติ):',
                                          request.reason!),
                                    if (request.approvedBy != null &&
                                        request.approverFirstname != null &&
                                        request.approverLastname != null)
                                      _buildInfoRow('ผู้อนุมัติ:',
                                          '${request.approverFirstname} ${request.approverLastname}'),
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
                                          onPressed: () async {
                                            await _openFileUrl(
                                                request.filePath);
                                          },
                                          icon:
                                              const Icon(Icons.image, size: 18),
                                          label: Text('ดูไฟล์แนบ',
                                              style: GoogleFonts.kanit()),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                    // No edit button for history requests
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
