import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'leave_allowance_screen.dart';

import 'main.dart' show User;
import 'models/leave_log.dart';

// --- Global Helper Function ---
String _formatTimeOfDayToString(TimeOfDay tod) {
  final now = DateTime.now();
  final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
  final format = DateFormat.Hm(); // 'HH:mm'
  return format.format(dt);
}
// --- End Global Helper Function ---

class LeaveScreen extends StatefulWidget {
  final User user;
  final LeaveLog? logToEdit;

  const LeaveScreen({super.key, required this.user, this.logToEdit});

  @override
  State<LeaveScreen> createState() => LeaveScreenState();
}

class LeaveScreenState extends State<LeaveScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  String? _errorMessage;
  List<LeaveLog> _leaves = [];

  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  DateTime? _selectedStartDate;
  TimeOfDay? _selectedStartTime;
  DateTime? _selectedEndDate;
  TimeOfDay? _selectedEndTime;
  String? _selectedLeaveType;
  XFile? _pickedFile; // The file chosen by the user for upload
  String? _existingFilePath; // Path to the file already on the server
  int? _editingRequestId;

  // Save initial values when entering edit mode to restore on cancel
  DateTime? _initialSelectedStartDate;
  TimeOfDay? _initialSelectedStartTime;
  DateTime? _initialSelectedEndDate;
  TimeOfDay? _initialSelectedEndTime;
  String? _initialSelectedLeaveType;
  String? _initialNote;
  String? _initialExistingFilePath; // Store initial existing file path

  final List<String> _leaveTypes = [
    "ลากิจได้รับค่าจ้าง",
    "ลากิจไม่ได้รับค่าจ้าง",
    "ลาป่วยมีใบรับรองแพทย์",
    "ลาคลอดได้รับค่าจ้าง",
    "ลาคลอดไม่ได้รับค่าจ้าง",
    "ลาพักร้อน",
    "สิทธิหยุดวันเสาร์",
    "ฉุกเฉิน"
  ];

  Map<String, dynamic>?
      _leaveAllowance; // เพิ่มตัวแปรสำหรับเก็บข้อมูลสิทธิ์การลา
  bool _isLeaveDurationExceeded = false; // เพิ่มสถานะการลาเกิน

  final String _baseUploadsUrl = 'https://npdhrms.com/'; // Your domain root URL

  // ✅ Add _needsRefresh flag to control initial data fetch in didChangeDependencies
  bool _needsRefresh = true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('th', null);

    if (widget.logToEdit != null) {
      _editingRequestId = widget.logToEdit!.id;
      _selectedStartDate = widget.logToEdit!.leaveStartDate;
      _selectedStartTime = widget.logToEdit!.leaveStartTime;
      _selectedEndDate = widget.logToEdit!.leaveEndDate;
      _selectedEndTime = widget.logToEdit!.leaveEndTime;
      _selectedLeaveType = widget.logToEdit!.leaveType;
      _noteController.text = widget.logToEdit!.note ?? '';
      _existingFilePath = widget.logToEdit!.filePath; // Path from DB

      _startDateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedStartDate!);
      _startTimeController.text = _formatTimeOfDayToString(_selectedStartTime!);
      _endDateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedEndDate!);
      _endTimeController.text = _formatTimeOfDayToString(_selectedEndTime!);

      // Save initial values for cancel functionality
      _initialSelectedStartDate = _selectedStartDate;
      _initialSelectedStartTime = _selectedStartTime;
      _initialSelectedEndDate = _selectedEndDate;
      _initialSelectedEndTime = _selectedEndTime;
      _initialSelectedLeaveType = _selectedLeaveType;
      _initialNote = _noteController.text;
      _initialExistingFilePath =
          _existingFilePath; // ✅ Save initial existing file path
    } else {
      // Set initial values for a new request form
      _selectedStartDate = DateTime.now();
      _selectedStartTime = const TimeOfDay(hour: 8, minute: 0);
      _selectedEndDate = DateTime.now();
      _selectedEndTime = const TimeOfDay(hour: 17, minute: 0);
      _selectedLeaveType = null; // New requests start with no selected type

      _startDateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedStartDate!);
      _startTimeController.text = _formatTimeOfDayToString(_selectedStartTime!);
      _endDateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedEndDate!);
      _endTimeController.text = _formatTimeOfDayToString(_selectedEndTime!);
    }
  }

  Future<void> refreshData() async {
    debugPrint('LeaveScreen: refreshData() called.');
    if (mounted) {
      setState(() {
        _isLoading = true; // Show loading indicator immediately
        _errorMessage = null; // Clear old error message
        _leaves = []; // Clear existing data
      });
    }
    await _fetchLeaveHistory();
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
    _startDateController.dispose();
    _startTimeController.dispose();
    _endDateController.dispose();
    _endTimeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // === Helper Methods (Within State class) ===

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).primaryColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  // เพิ่มฟังก์ชันสำหรับแสดง Popup
  void _showAllowancePopup(String leaveType, int remainingDays) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("สิทธิ์การลาไม่เพียงพอ",
              style: GoogleFonts.kanit(fontWeight: FontWeight.bold)),
          content: Text(
            "คุณสามารถ $leaveType ได้สูงสุด $remainingDays วัน",
            style: GoogleFonts.kanit(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("ตกลง", style: GoogleFonts.kanit()),
            ),
          ],
        );
      },
    );
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
      case 'ยกเลิก':
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
      case 'ยกเลิก':
        return Colors.blueGrey.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  // Helper to check if a file identifier is an image based on extension
  bool _isImageFile(String? fileIdentifierOrExtension) {
    if (fileIdentifierOrExtension == null) return false;
    final lowerCaseIdentifier = fileIdentifierOrExtension.toLowerCase();

    // If it's a full path, extract the extension first
    String extension;
    if (lowerCaseIdentifier.contains('.')) {
      extension = lowerCaseIdentifier.split('.').last;
    } else {
      extension = lowerCaseIdentifier; // Assume it's already an extension
    }

    return extension == 'jpg' ||
        extension == 'jpeg' ||
        extension == 'png' ||
        extension == 'gif';
  }

  // Function to show image in a dialog (using PhotoView)
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
                height: MediaQuery.of(context).size.height *
                    0.6, // กำหนดความสูงของรูปภาพ
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
                    debugPrint(
                        'PhotoView Error: $error'); // Log the PhotoView error
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

  // Function to open file URL (local or remote), handles image display
  Future<void> _openFileUrl(String? filePath,
      {XFile? pickedFileArgument}) async {
    if (filePath == null && pickedFileArgument == null) {
      _showSnackBar('ไม่มีไฟล์แนบ', isError: true);
      return;
    }

    String? finalPathOrUrl;
    bool isLocal = false;

    // Prioritize pickedFileArgument if provided (for newly selected files)
    if (pickedFileArgument != null) {
      finalPathOrUrl = pickedFileArgument.path;
      isLocal = true;
    } else if (filePath != null) {
      // Fallback to filePath (for existing server files from DB)
      // Check if filePath from DB is ALREADY a full URL
      if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
        finalPathOrUrl = filePath; // It's already a complete URL from the DB
        isLocal = false;
      } else {
        // If it's not a full URL (meaning it's a relative path like 'uploads/filename.jpg' or '../uploads/filename.jpg')
        // Then we need to construct the full URL using _baseUploadsUrl.
        String cleanedPath = filePath;
        // Remove known relative path prefixes from database value if present
        if (cleanedPath.startsWith('../uploads/')) {
          cleanedPath = cleanedPath.substring('../uploads/'.length);
        } else if (cleanedPath.startsWith('uploads/')) {
          cleanedPath = cleanedPath.substring('uploads/'.length);
        }
        // Construct the full URL for remote access
        finalPathOrUrl = _baseUploadsUrl + 'uploads/' + cleanedPath;
        isLocal = false;
      }
    }

    if (finalPathOrUrl == null || finalPathOrUrl.isEmpty) {
      _showSnackBar('ไม่มีไฟล์แนบ', isError: true);
      return;
    }

    final String fileExtension = finalPathOrUrl.split('.').last.toLowerCase();

    // Strictly validate that it IS an image file
    if (!_isImageFile(fileExtension)) {
      _showSnackBar(
          'ไม่รองรับไฟล์ประเภท .$fileExtension กรุณาเลือก JPG, JPEG, PNG, GIF เท่านั้น',
          isError: true);
      debugPrint(
          'Attempted to open non-image file type: .$fileExtension for path: $finalPathOrUrl');
      return;
    }

    debugPrint(
        'Attempting to open file: $finalPathOrUrl (isLocal: $isLocal, extension: .$fileExtension)');

    if (isLocal) {
      try {
        if (await File(finalPathOrUrl).exists()) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop())),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: PhotoView(
                        imageProvider: FileImage(File(finalPathOrUrl!)),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                  ],
                ),
              );
            },
          );
        } else {
          _showSnackBar('ไฟล์รูปภาพไม่พบในเครื่อง', isError: true);
          debugPrint('Local image file not found at path: $finalPathOrUrl');
        }
      } catch (e) {
        _showSnackBar('เกิดข้อผิดพลาดในการแสดงไฟล์รูปภาพในเครื่อง: $e',
            isError: true);
        debugPrint('Error displaying local image: $e');
      }
    } else {
      _showImageDialog(finalPathOrUrl); // For remote images
    }
  }

  // Function to pick files (strictly from gallery, only images)
  Future<void> _pickFile() async {
    final ImagePicker _picker = ImagePicker();
    XFile? imageFile;
    try {
      imageFile = await _picker.pickImage(source: ImageSource.gallery);
    } catch (e) {
      debugPrint('Error picking image from gallery: $e');
      if (e.toString().contains('no_image_picker_found') ||
          e.toString().contains('Not implemented')) {
        _showSnackBar('ไม่พบแอปเลือกรูปภาพ หรือไม่สามารถเข้าถึงได้.',
            isError: true);
      } else {
        _showSnackBar('เกิดข้อผิดพลาดในการเปิดแกลเลอรี: $e', isError: true);
      }
      return; // Exit here if there's an error during picking
    }

    if (imageFile != null) {
      final String? fileExtension =
          imageFile.path.split('.').last.toLowerCase();
      debugPrint('Picked file path: ${imageFile.path}');
      debugPrint('Detected extension from picked file: .$fileExtension');

      // Strict validation for allowed image types only
      if (!_isImageFile(fileExtension)) {
        _showSnackBar(
            'ไม่รองรับไฟล์รูปภาพประเภท .$fileExtension กรุณาเลือก JPG, JPEG, PNG, GIF เท่านั้น',
            isError: true);
        return;
      }

      setState(() {
        _pickedFile = imageFile;
        _existingFilePath = null; // Clear existing path if a new file is picked
      });
      _showSnackBar('เลือกไฟล์รูปภาพ: ${imageFile.name}', isError: false);
    } else {
      // User cancelled picker
      debugPrint('Image picker cancelled.');
    }
  }

  Future<void> _fetchLeaveHistory() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _leaves = []; // Clear existing data before fetching
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse(
                'https://npdhrms.com/api/leave_requests.php?user_id=${widget.user.id}'),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      debugPrint(
          'LeaveScreen Fetch API Response Status: ${response.statusCode}');
      debugPrint('LeaveScreen Fetch API Response Body: ${response.body}');

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
          List<dynamic> leavesJson = responseData['data'];
          _leaves = leavesJson.map((json) => LeaveLog.fromJson(json)).toList();
        } else {
          _errorMessage =
              responseData['message'] ?? 'Failed to load leave history.';
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
          debugPrint('Failed to parse error body for leave history fetch: $e');
        }
      }
    } on TimeoutException {
      _errorMessage = 'การเชื่อมต่อล่าช้าเกินกำหนด';
    } on FormatException catch (e) {
      _errorMessage = 'รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์. ($e)';
      debugPrint('FormatException during _fetchLeaveHistory: $e');
    } catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e';
      debugPrint('Exception during _fetchLeaveHistory: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- New function to check leave allowance ---
  Future<void> _checkLeaveAllowance() async {
    // Check if all required fields are selected
    if (_selectedLeaveType == null ||
        _selectedStartDate == null ||
        _selectedEndDate == null) {
      setState(() {
        _isLeaveDurationExceeded = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String employeeCode = widget.user.employeeCode ?? '';
      final String leaveTypeKey = _getLeaveTypeKey(_selectedLeaveType!);
      final String apiUrl =
          'https://npdhrms.com/api/check_leave_allowance.php?employee_code=$employeeCode&leave_type=$leaveTypeKey';

      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['status'] == 'success') {
          _leaveAllowance = data['data'];
          int remainingDays = _leaveAllowance!['remaining'] as int;

          // Calculate leave duration (assuming full days)
          int leaveDuration =
              _selectedEndDate!.difference(_selectedStartDate!).inDays + 1;

          if (leaveDuration > remainingDays) {
            _showAllowancePopup(_selectedLeaveType!, remainingDays);
            setState(() {
              _isLeaveDurationExceeded = true;
            });
          } else {
            setState(() {
              _isLeaveDurationExceeded = false;
            });
          }
        } else {
          _showSnackBar(data['message'] ?? 'ไม่สามารถตรวจสอบสิทธิ์การลาได้',
              isError: true);
          setState(() {
            _isLeaveDurationExceeded = true; // Block submission if check fails
          });
        }
      } else {
        _showSnackBar(
            'เกิดข้อผิดพลาดในการตรวจสอบสิทธิ์การลา: ${response.statusCode}',
            isError: true);
        setState(() {
          _isLeaveDurationExceeded = true; // Block submission if API call fails
        });
      }
    } on TimeoutException {
      _showSnackBar('การเชื่อมต่อล่าช้าเกินกำหนด', isError: true);
      setState(() {
        _isLeaveDurationExceeded = true;
      });
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาดในการตรวจสอบสิทธิ์: $e', isError: true);
      setState(() {
        _isLeaveDurationExceeded = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Helper to map Thai leave type to API key
  String _getLeaveTypeKey(String leaveType) {
    switch (leaveType) {
      case "ลากิจได้รับค่าจ้าง":
        return "leave_personal_paid";
      case "ลากิจไม่ได้รับค่าจ้าง":
        return "leave_personal_unpaid";
      case "ลาป่วยมีใบรับรองแพทย์":
        return "leave_sick";
      case "ลาคลอดได้รับค่าจ้าง":
        return "leave_maternity_paid";
      case "ลาคลอดไม่ได้รับค่าจ้าง":
        return "leave_maternity_unpaid";
      case "ลาพักร้อน":
        return "leave_vacation";
      case "สิทธิหยุดวันเสาร์":
        return "leave_saturday";
      case "ฉุกเฉิน":
        return "leave_emergency";
      default:
        return "";
    }
  }

  // Function to submit leave request form
  Future<void> _submitForm() async {
    // Check if leave duration exceeds before submitting
    if (_isLeaveDurationExceeded) {
      _showSnackBar(
          'ไม่สามารถบันทึกคำขอได้เนื่องจากจำนวนวันลาเกินสิทธิ์ที่เหลือ',
          isError: true);
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedLeaveType == null || _selectedLeaveType!.isEmpty) {
      _showSnackBar('กรุณาเลือกประเภทการลา', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final String apiUrl =
          'https://npdhrms.com/api/submit_leave_request_test.php';

      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.fields['user_id'] = widget.user.id.toString();
      request.fields['username'] = widget.user.username ?? '';
      request.fields['firstname'] = widget.user.firstname;
      request.fields['lastname'] = widget.user.lastname;
      request.fields['department'] = widget.user.department ?? '';
      request.fields['position'] = widget.user.position ?? '';
      request.fields['leave_start_date'] =
          DateFormat('yyyy-MM-dd').format(_selectedStartDate!);
      request.fields['leave_statr_time'] =
          _formatTimeOfDayToString(_selectedStartTime!);
      request.fields['leave_end_date'] =
          DateFormat('yyyy-MM-dd').format(_selectedEndDate!);
      request.fields['leave_end_time'] =
          _formatTimeOfDayToString(_selectedEndTime!);
      request.fields['leave_type'] = _selectedLeaveType!;
      request.fields['note'] = _noteController.text;

      if (_editingRequestId != null) {
        request.fields['request_id'] = _editingRequestId.toString();
        // Only send existing_file_path if no new file is picked
        if (_pickedFile == null) {
          request.fields['existing_file_path'] = _existingFilePath ?? '';
        } else {
          // If a new file is picked, clear existing_file_path on server
          request.fields['existing_file_path'] = '';
        }
      }

      if (_pickedFile != null) {
        final String? fileExtension =
            _pickedFile!.path.split('.').last.toLowerCase();
        // Validate allowed image types only for upload
        if (!_isImageFile(fileExtension)) {
          _showSnackBar(
              'ไม่รองรับไฟล์รูปภาพประเภท .$fileExtension กรุณาเลือก JPG, JPEG, PNG, GIF เท่านั้น',
              isError: true);
          setState(() {
            _isLoading = false;
          });
          return;
        }

        request.files.add(await http.MultipartFile.fromPath(
          'attachment',
          _pickedFile!.path,
          filename: _pickedFile!.name,
        ));
      }

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.body.isEmpty) {
        _showSnackBar('API response body is empty after submit.',
            isError: true);
        debugPrint('Error: API response body is empty after submit.');
        if (mounted)
          setState(() {
            _isLoading = false;
          });
        return;
      }

      final Map<String, dynamic> responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        _showSnackBar(responseData['message'] ?? 'บันทึกข้อมูลสำเร็จ',
            isError: false);
        _resetForm();
        _fetchLeaveHistory();
      } else {
        _showSnackBar(
            responseData['message'] ?? 'เกิดข้อผิดพลาดในการบันทึกข้อมูล',
            isError: true);
      }
    } on TimeoutException {
      _showSnackBar('การเชื่อมต่อล่าช้าเกินกำหนด', isError: true);
    } on FormatException catch (e) {
      _showSnackBar('รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์. ($e)',
          isError: true);
      debugPrint('FormatException during _submitForm: $e');
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาด: $e', isError: true);
      debugPrint('Exception during _submitForm: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Function to cancel a leave request
  Future<void> _cancelLeaveRequest(int leaveId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('https://npdhrms.com/api/cancel_leave_request_test.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'request_id': leaveId}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final Map<String, dynamic> responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        _showSnackBar(responseData['message'] ?? 'ยกเลิกคำขอลาสำเร็จ',
            isError: false);
        _fetchLeaveHistory(); // Refresh logs after cancellation
      } else {
        _showSnackBar(responseData['message'] ?? 'ไม่สามารถยกเลิกคำขอลาได้',
            isError: true);
      }
    } on TimeoutException {
      _showSnackBar('การเชื่อมต่อล่าช้าเกินกำหนด', isError: true);
    } on FormatException catch (e) {
      _showSnackBar('รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์หลังการยกเลิก. ($e)',
          isError: true);
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาดในการยกเลิกคำขอ: $e', isError: true);
      debugPrint('Exception during _cancelLeaveRequest: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Function to show a confirmation dialog before canceling
  Future<void> _showCancelConfirmationDialog(int leaveId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('ยืนยันการยกเลิกคำขอลา', style: GoogleFonts.kanit()),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('คุณต้องการยกเลิกคำขอลาใช่หรือไม่?',
                    style: GoogleFonts.kanit()),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child:
                  Text('ไม่ใช่', style: GoogleFonts.kanit(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('ใช่, ยกเลิกเลย',
                  style: GoogleFonts.kanit(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                _cancelLeaveRequest(leaveId); // Call the cancel function
              },
            ),
          ],
        );
      },
    );
  }

  // Function to reset form fields (for new request)
  void _resetForm() {
    setState(() {
      _editingRequestId = null; // Ensure not in edit mode
      _selectedStartDate = DateTime.now();
      _selectedStartTime = const TimeOfDay(hour: 8, minute: 0);
      _selectedEndDate = DateTime.now();
      _selectedEndTime = const TimeOfDay(hour: 17, minute: 0);
      _selectedLeaveType = null;
      _noteController.clear();
      _pickedFile = null;
      _existingFilePath = null; // Ensure no existing file path
      _startDateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedStartDate!);
      _startTimeController.text = _formatTimeOfDayToString(_selectedStartTime!);
      _endDateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedEndDate!);
      _endTimeController.text = _formatTimeOfDayToString(_selectedEndTime!);
      // Reset initial values as well when starting a fresh form
      _initialSelectedStartDate = null;
      _initialSelectedStartTime = null;
      _initialSelectedEndDate = null;
      _initialSelectedEndTime = null;
      _initialSelectedLeaveType = null;
      _initialNote = null;
      _initialExistingFilePath = null;
    });
  }

  // Function to handle editing an existing leave request
  void _editLeaveRequest(LeaveLog log) {
    if (log.state == 'รออนุมัติ') {
      setState(() {
        _editingRequestId = log.id;
        _selectedStartDate = log.leaveStartDate;
        _selectedStartTime = log.leaveStartTime;
        _selectedEndDate = log.leaveEndDate;
        _selectedEndTime = log.leaveEndTime;
        _selectedLeaveType = log.leaveType;
        _noteController.text = log.note ?? '';
        _existingFilePath = log.filePath;
        _pickedFile = null; // Clear any newly picked file when editing existing

        _startDateController.text =
            DateFormat('d/M/yyyy', 'th').format(_selectedStartDate!);
        _startTimeController.text =
            _formatTimeOfDayToString(_selectedStartTime!);
        _endDateController.text =
            DateFormat('d/M/yyyy', 'th').format(_selectedEndDate!);
        _endTimeController.text = _formatTimeOfDayToString(_selectedEndTime!);

        // Save initial values for cancel functionality
        _initialSelectedStartDate = _selectedStartDate;
        _initialSelectedStartTime = _selectedStartTime;
        _initialSelectedEndDate = _selectedEndDate;
        _initialSelectedEndTime = _selectedEndTime;
        _initialSelectedLeaveType = _selectedLeaveType;
        _initialNote = _noteController.text;
        _initialExistingFilePath =
            _existingFilePath; // Store original attached file path
      });
      Scrollable.ensureVisible(
        _formKey.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.0,
      );
    } else {
      _showSnackBar('ไม่สามารถแก้ไขคำขอที่สถานะไม่ใช่ "รออนุมัติ" ได้',
          isError: true);
    }
  }

  // Function to cancel editing and revert form to initial state
  void _cancelEdit() {
    setState(() {
      _editingRequestId = null; // Exit edit mode
      _pickedFile = null; // Clear any newly picked file

      // Restore initial values
      _selectedStartDate = _initialSelectedStartDate;
      _selectedStartTime = _initialSelectedStartTime;
      _selectedEndDate = _initialSelectedEndDate;
      _selectedEndTime = _initialSelectedEndTime;
      _selectedLeaveType = _initialSelectedLeaveType;
      _noteController.text = _initialNote ?? '';
      _existingFilePath = _initialExistingFilePath;

      // Update text controllers
      if (_selectedStartDate != null) {
        _startDateController.text =
            DateFormat('d/M/yyyy', 'th').format(_selectedStartDate!);
      }
      if (_selectedStartTime != null) {
        _startTimeController.text =
            _formatTimeOfDayToString(_selectedStartTime!);
      }
      if (_selectedEndDate != null) {
        _endDateController.text =
            DateFormat('d/M/yyyy', 'th').format(_selectedEndDate!);
      }
      if (_selectedEndTime != null) {
        _endTimeController.text = _formatTimeOfDayToString(_selectedEndTime!);
      }

      _showSnackBar('ยกเลิกการแก้ไข', isError: false);
    });
  }

  // Functions for date and time selection (Correctly placed within the State class)
  Future<void> _selectDate(BuildContext context,
      {required bool isStartDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (_selectedStartDate ?? DateTime.now())
          : (_selectedEndDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('th', 'TH'),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _selectedStartDate = picked;
          _startDateController.text =
              DateFormat('d/M/yyyy', 'th').format(picked);
          if (_selectedEndDate != null && _selectedEndDate!.isBefore(picked)) {
            _selectedEndDate = picked;
            _endDateController.text =
                DateFormat('d/M/yyyy', 'th').format(picked);
          }
        } else {
          if (_selectedStartDate != null &&
              picked.isBefore(_selectedStartDate!)) {
            _showSnackBar('วันที่สิ้นสุดต้องไม่ก่อนวันที่เริ่มต้น',
                isError: true);
            return;
          }
          _selectedEndDate = picked;
          _endDateController.text = DateFormat('d/M/yyyy', 'th').format(picked);
        }
      });
      _checkLeaveAllowance(); // Call check function after date selection
    }
  }

  Future<void> _selectTime(BuildContext context,
      {required bool isStartTime}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime
          ? (_selectedStartTime ?? TimeOfDay.now())
          : (_selectedEndTime ?? TimeOfDay.now()),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _selectedStartTime = picked;
          _startTimeController.text = _formatTimeOfDayToString(picked);
        } else {
          _selectedEndTime = picked;
          _endTimeController.text = _formatTimeOfDayToString(picked);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('การขอลางาน'),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'ดูสิทธิ์การลา',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        LeaveAllowanceScreen(user: widget.user),
                  ),
                );
              },
            ),
          ],
        ),
        body: _isLoading && _leaves.isEmpty && _errorMessage == null
            ? Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).primaryColor))
            : RefreshIndicator(
                onRefresh: _fetchLeaveHistory,
                color: Theme.of(context).primaryColor,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                  onPressed: _fetchLeaveHistory,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('ลองอีกครั้ง'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Form(
                        key: _formKey,
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _editingRequestId != null
                                          ? '✏️ แก้ไขคำขอลา'
                                          : '📝 บันทึกคำขอลา',
                                      style: GoogleFonts.kanit(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                    if (_editingRequestId != null)
                                      TextButton.icon(
                                        onPressed: _cancelEdit,
                                        icon: const Icon(Icons.cancel_outlined,
                                            size: 18, color: Colors.grey),
                                        label: Text('ยกเลิก',
                                            style: GoogleFonts.kanit(
                                                color: Colors.grey)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _startDateController,
                                  readOnly: true,
                                  onTap: () =>
                                      _selectDate(context, isStartDate: true),
                                  decoration: InputDecoration(
                                    labelText: 'วันที่ลาเริ่มต้น',
                                    labelStyle: GoogleFonts.kanit(),
                                    prefixIcon: const Icon(
                                        Icons.calendar_today_outlined),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกวันที่ลาเริ่มต้น';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _startTimeController,
                                  readOnly: true,
                                  onTap: () =>
                                      _selectTime(context, isStartTime: true),
                                  decoration: InputDecoration(
                                    labelText: 'เวลาที่ลาเริ่มต้น',
                                    labelStyle: GoogleFonts.kanit(),
                                    prefixIcon: const Icon(Icons.access_time),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกเวลาที่ลาเริ่มต้น';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _endDateController,
                                  readOnly: true,
                                  onTap: () =>
                                      _selectDate(context, isStartDate: false),
                                  decoration: InputDecoration(
                                    labelText: 'วันที่ลาสิ้นสุด',
                                    labelStyle: GoogleFonts.kanit(),
                                    prefixIcon: const Icon(
                                        Icons.calendar_today_outlined),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกวันที่ลาสิ้นสุด';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _endTimeController,
                                  readOnly: true,
                                  onTap: () =>
                                      _selectTime(context, isStartTime: false),
                                  decoration: InputDecoration(
                                    labelText: 'เวลาที่ลาสิ้นสุด',
                                    labelStyle: GoogleFonts.kanit(),
                                    prefixIcon: const Icon(Icons.access_time),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกเวลาที่ลาสิ้นสุด';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  value: _selectedLeaveType,
                                  decoration: InputDecoration(
                                    labelText: 'ประเภทการลา',
                                    labelStyle: GoogleFonts.kanit(),
                                    prefixIcon:
                                        const Icon(Icons.category_outlined),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  items: _leaveTypes.map((String type) {
                                    return DropdownMenuItem<String>(
                                      value: type,
                                      child: Text(type,
                                          style: GoogleFonts.kanit()),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedLeaveType = newValue;
                                    });
                                    _checkLeaveAllowance(); // เรียกใช้ check function เมื่อเปลี่ยนประเภทการลา
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกประเภทการลา';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                // แสดงข้อความแจ้งเตือนเมื่อลาเกิน
                                if (_isLeaveDurationExceeded)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 16.0),
                                    child: Text(
                                      'ไม่สามารถบันทึกคำขอได้เนื่องจากจำนวนวันลาเกินสิทธิ์ที่เหลือ',
                                      style:
                                          GoogleFonts.kanit(color: Colors.red),
                                    ),
                                  ),
                                TextFormField(
                                  controller: _noteController,
                                  decoration: InputDecoration(
                                    labelText: 'หมายเหตุ (ถ้ามี)',
                                    labelStyle: GoogleFonts.kanit(),
                                    prefixIcon:
                                        const Icon(Icons.note_alt_outlined),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  maxLines: 2,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    FocusScope.of(context).unfocus();
                                  },
                                ),
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: _pickFile,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.attach_file,
                                            color: Colors.blue),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _pickedFile != null
                                                ? 'ไฟล์ที่เลือก: ${_pickedFile!.name}'
                                                : (_existingFilePath != null &&
                                                        _existingFilePath!
                                                            .isNotEmpty
                                                    ? 'ไฟล์เดิม: ${Uri.parse(_existingFilePath!).pathSegments.last}'
                                                    : '📎 แนบไฟล์ (รูปภาพ)'),
                                            style: GoogleFonts.kanit(
                                                color: Colors.grey.shade700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_existingFilePath != null &&
                                    _existingFilePath!.isNotEmpty &&
                                    _pickedFile == null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () async {
                                          await _openFileUrl(_existingFilePath);
                                        },
                                        icon: const Icon(Icons.image, size: 18),
                                        label: Text('ดูไฟล์เดิม',
                                            style: GoogleFonts.kanit()),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _isLoading || _isLeaveDurationExceeded
                                            ? null
                                            : _submitForm,
                                    icon: _editingRequestId != null
                                        ? const Icon(Icons.edit)
                                        : const Icon(Icons.save),
                                    label: Text(
                                        _editingRequestId != null
                                            ? 'อัปเดตคำขอ'
                                            : 'บันทึกคำขอ',
                                        style: GoogleFonts.kanit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(context).primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_isLoading && _leaves.isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 16.0),
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        '📜 ประวัติการลา 7 (ล่าสุด)',
                        style: GoogleFonts.kanit(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _leaves.isEmpty && !_isLoading
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  'ไม่มีข้อมูลการลา',
                                  style: GoogleFonts.kanit(
                                      fontSize: 16,
                                      color: Colors.grey.shade600),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _leaves.length,
                              itemBuilder: (context, index) {
                                final leave = _leaves[index];
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: _getStateBackgroundColor(
                                            leave.state)),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          _getStateBackgroundColor(leave.state),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '📅 ${_formatThaiDate(leave.leaveStartDate)}' +
                                                    (leave.leaveStartDate !=
                                                            leave.leaveEndDate
                                                        ? '\nถึง ${_formatThaiDate(leave.leaveEndDate)}'
                                                        : ''),
                                                style: GoogleFonts.kanit(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context)
                                                        .primaryColor),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _getStateColor(
                                                      leave.state),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  leave.state,
                                                  style: GoogleFonts.kanit(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '✅ เริ่ม: ${_formatTimeOfDayToString(leave.leaveStartTime)} น. | ⛔ สิ้นสุด: ${_formatTimeOfDayToString(leave.leaveEndTime)} น.',
                                            style: GoogleFonts.kanit(
                                                fontSize: 14,
                                                color: Colors.grey.shade800),
                                          ),
                                          Text(
                                            '🏷️ ${leave.leaveType}',
                                            style: GoogleFonts.kanit(
                                                fontSize: 14,
                                                color: Colors.grey.shade800),
                                          ),
                                          if (leave.note != null &&
                                              leave.note!.isNotEmpty)
                                            Text(
                                              '📝 หมายเหตุ: ${leave.note}',
                                              style: GoogleFonts.kanit(
                                                  fontSize: 14,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.grey.shade700),
                                            ),
                                          if (leave.department != null &&
                                              leave.department!.isNotEmpty)
                                            Text(
                                              'แผนก: ${leave.department}',
                                              style: GoogleFonts.kanit(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade800),
                                            ),
                                          if (leave.position != null &&
                                              leave.position!.isNotEmpty)
                                            Text(
                                              'ตำแหน่ง: ${leave.position}',
                                              style: GoogleFonts.kanit(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade800),
                                            ),
                                          if (leave.reason != null &&
                                              leave.reason!.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 8.0),
                                              child: Text(
                                                'เหตุผล (ไม่อนุมัติ): ${leave.reason}',
                                                style: GoogleFonts.kanit(
                                                    fontSize: 14,
                                                    fontStyle: FontStyle.italic,
                                                    color: Colors.red.shade800),
                                              ),
                                            ),
                                          if (leave.approvedBy != null &&
                                              leave.approverFirstname != null &&
                                              leave.approverLastname != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 8.0),
                                              child: Text(
                                                'อนุมัติโดย: ${leave.approverFirstname} ${leave.approverLastname}',
                                                style: GoogleFonts.kanit(
                                                    fontSize: 14,
                                                    color:
                                                        Colors.grey.shade700),
                                              ),
                                            ),
                                          if (leave.approvedAt != null)
                                            Text(
                                              'เมื่อ: ${DateFormat('d/M/yyyy HH:mm', 'th').format(leave.approvedAt!)}',
                                              style: GoogleFonts.kanit(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade700),
                                            ),
                                          const SizedBox(height: 16),
                                          Wrap(
                                            spacing: 8.0,
                                            runSpacing: 4.0,
                                            alignment: WrapAlignment.end,
                                            children: [
                                              if (leave.filePath != null &&
                                                  leave.filePath!.isNotEmpty &&
                                                  (leave.state == 'รออนุมัติ' ||
                                                      leave.state ==
                                                          'อนุมัติ' ||
                                                      leave.state ==
                                                          'ไม่อนุมัติ'))
                                                TextButton.icon(
                                                  onPressed: () async {
                                                    await _openFileUrl(
                                                        leave.filePath);
                                                  },
                                                  icon: const Icon(Icons.image,
                                                      size: 18),
                                                  label: Text('ดูไฟล์แนบ',
                                                      style:
                                                          GoogleFonts.kanit()),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.blue.shade700,
                                                  ),
                                                ),
                                              if (leave.state == 'รออนุมัติ')
                                                TextButton.icon(
                                                  onPressed: () =>
                                                      _editLeaveRequest(leave),
                                                  icon: const Icon(Icons.edit,
                                                      size: 18),
                                                  label: Text('แก้ไข',
                                                      style:
                                                          GoogleFonts.kanit()),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.orange.shade700,
                                                  ),
                                                ),
                                              if (leave.state != 'ยกเลิก')
                                                TextButton.icon(
                                                  onPressed: () =>
                                                      _showCancelConfirmationDialog(
                                                          leave.id),
                                                  icon: const Icon(Icons.cancel,
                                                      size: 18),
                                                  label: Text('ยกเลิก',
                                                      style:
                                                          GoogleFonts.kanit()),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.red.shade700,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
