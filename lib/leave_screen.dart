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
import 'odoo_rpc_service.dart';
import 'widgets/expandable_history_card.dart';

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

  // ✅ วันหยุดบริษัท (ดึงจาก Odoo payroll.holiday)
  List<DateTime> _companyHolidays = [];
  // ✅ ช่วงวันหยุดยาว (≥2 วันติดกัน)
  List<List<DateTime>> _longHolidayRanges = [];
  // ✅ ประเภทการลาที่ยกเว้นการตรวจวันหยุดยาว
  static const Set<String> _exemptLeaveTypes = {
    'ลากิจไม่ได้รับค่าจ้าง',
    'ลาป่วยมีใบรับรองแพทย์',
    'สิทธิหยุดวันเสาร์',
  };
  String? _holidayRuleError;

  final String _baseUploadsUrl = 'https://npdhrms.com/'; // Your domain root URL

  // ✅ Add _needsRefresh flag to control initial data fetch in didChangeDependencies
  bool _needsRefresh = true;

  // ✅ วันที่เริ่มงาน (จาก Odoo employee.salary.start_date) ใช้เช็คโปร 3 เดือน
  String? _employeeStartDate;

  // ✅ สาขาของพนักงาน (จาก Odoo employee.salary.branch_id)
  // ใช้กำหนดสิทธิ์ "สิทธิหยุดวันเสาร์": สนง.ใหญ่ = 2 ครั้ง/เดือน, สาขาอื่น = 1 ครั้ง/เดือน
  String? _employeeBranch;

  // ✅ สิทธิหยุดวันเสาร์/เดือน ดึงจาก Odoo (saturday.leave.config) ตามสาขา
  // ถ้า null = ยังโหลดไม่ได้ → ใช้กฎ fallback (สนง.ใหญ่ 2 / สาขา 1)
  int? _saturdayQuota;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('th', null);
    _loadCompanyHolidays(); // ✅ โหลดวันหยุดบริษัทจาก Odoo
    _loadEmployeeStartDate(); // ✅ โหลดวันที่เริ่มงานจาก Odoo (เช็คโปร)

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
    // ✅ โหลดข้อมูลทั้งหมดใหม่พร้อมกัน (history + employee info + วันหยุด)
    // เพื่อให้ pull-to-refresh ดึง start_date / branch ใหม่จาก Odoo ด้วย
    await Future.wait([
      _fetchLeaveHistory(),
      _loadEmployeeStartDate(), // ดึง start_date + branch ใหม่
      _loadCompanyHolidays(), // ดึงวันหยุดบริษัทใหม่
    ]);
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
              style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.bold)),
          content: Text(
            "คุณสามารถ $leaveType ได้สูงสุด $remainingDays วัน",
            style: GoogleFonts.ibmPlexSansThai(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("ตกลง", style: GoogleFonts.ibmPlexSansThai()),
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

  // ✅ โหลดวันหยุดบริษัทจาก Odoo payroll.holiday + จัด group วันหยุดยาว
  Future<void> _loadCompanyHolidays() async {
    try {
      final odoo = OdooRpcService();
      // โหลดปีนี้ + ปีหน้า (เผื่อลาข้ามปี)
      final nowYear = DateTime.now().year;
      debugPrint('🏝️ Loading company holidays for $nowYear, ${nowYear + 1}');
      final thisYear = await odoo.getCompanyHolidays(year: nowYear);
      final nextYear = await odoo.getCompanyHolidays(year: nowYear + 1);
      final all = <DateTime>[...thisYear, ...nextYear];

      if (!mounted) return;
      setState(() {
        _companyHolidays = all;
        _longHolidayRanges = _groupLongHolidays(all);
      });
      debugPrint(
          '✅ Loaded ${all.length} holidays, ${_longHolidayRanges.length} long-holiday ranges');
      for (final r in _longHolidayRanges) {
        debugPrint(
            '   range: ${r.first.toIso8601String().split('T')[0]} ~ ${r.last.toIso8601String().split('T')[0]} (${r.length} days)');
      }
    } catch (e, st) {
      debugPrint('⚠️ Load company holidays failed: $e');
      debugPrint('$st');
      // ถ้าโหลดไม่ได้ ปล่อยให้ลาต่อได้ (fail-open)
    }
  }

  /// จัดกลุ่มวันหยุดที่ติดกันเป็นช่วง แล้วเก็บเฉพาะช่วงที่ยาว ≥ 2 วัน
  List<List<DateTime>> _groupLongHolidays(List<DateTime> holidays) {
    if (holidays.isEmpty) return [];
    final sorted = [...holidays]
      ..sort((a, b) => a.compareTo(b));
    final List<List<DateTime>> ranges = [];
    List<DateTime> current = [_dateOnly(sorted.first)];

    for (int i = 1; i < sorted.length; i++) {
      final d = _dateOnly(sorted[i]);
      final diff = d.difference(current.last).inDays;
      if (diff == 1) {
        current.add(d);
      } else if (diff == 0) {
        // duplicate, skip
      } else {
        if (current.length >= 2) ranges.add(current);
        current = [d];
      }
    }
    if (current.length >= 2) ranges.add(current);
    return ranges;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isHolidayDate(DateTime d) {
    final target = _dateOnly(d);
    return _companyHolidays.any((h) => _dateOnly(h) == target);
  }

  /// หาวันทำงานก่อนวันที่กำหนด (ข้ามอาทิตย์ + ข้ามวันหยุดบริษัท)
  DateTime? _findWorkingDayBefore(DateTime start) {
    DateTime d = start.subtract(const Duration(days: 1));
    for (int i = 0; i < 30; i++) {
      if (d.weekday != DateTime.sunday && !_isHolidayDate(d)) return d;
      d = d.subtract(const Duration(days: 1));
    }
    return null;
  }

  /// หาวันทำงานหลังวันที่กำหนด (ข้ามอาทิตย์ + ข้ามวันหยุดบริษัท)
  DateTime? _findWorkingDayAfter(DateTime end) {
    DateTime d = end.add(const Duration(days: 1));
    for (int i = 0; i < 30; i++) {
      if (d.weekday != DateTime.sunday && !_isHolidayDate(d)) return d;
      d = d.add(const Duration(days: 1));
    }
    return null;
  }

  /// ✅ แสดง dialog แจ้งเงื่อนไขลาฉุกเฉิน
  void _showEmergencyLeaveDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange.shade700, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'เงื่อนไขการลาฉุกเฉิน',
                  style: GoogleFonts.ibmPlexSansThai(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('การลาฉุกเฉินใช้ได้เฉพาะกรณี:',
                  style: GoogleFonts.ibmPlexSansThai(
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('• บิดา (พ่อ) เสียชีวิต',
                  style: GoogleFonts.ibmPlexSansThai(fontSize: 14)),
              Text('• มารดา (แม่) เสียชีวิต',
                  style: GoogleFonts.ibmPlexSansThai(fontSize: 14)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.attach_file,
                        color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'จำเป็นต้องแนบใบมรณะบัตรประกอบ',
                        style: GoogleFonts.ibmPlexSansThai(
                            fontSize: 13,
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('รับทราบ',
                  style: GoogleFonts.ibmPlexSansThai(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// ✅ โหลดข้อมูลพนักงานจาก Odoo (start_date + branch)
  /// - start_date → เช็คโปร 3 เดือน (ลากิจได้รับค่าจ้าง)
  /// - branch → กำหนดสิทธิ์สิทธิหยุดวันเสาร์ (สนง.ใหญ่ 2 ครั้ง / สาขา 1 ครั้ง)
  Future<void> _loadEmployeeStartDate() async {
    debugPrint('🔄 [Odoo] เริ่มโหลดข้อมูลพนักงาน...');
    try {
      final code = widget.user.employeeCode ?? '';
      debugPrint('🆔 [Odoo] employee_code = "$code"');
      if (code.isEmpty) {
        debugPrint('⚠️ [Odoo] ไม่มี employee_code → ข้ามการเช็คโปร/สาขา');
        return;
      }
      final info = await OdooRpcService().getEmployeeInfo(code);
      debugPrint('📦 [Odoo] getEmployeeInfo() result: ${info == null ? "NULL (ไม่พบใน employee.salary)" : info}');

      if (info == null) {
        debugPrint('⚠️ [Odoo] ไม่พบ employee_code "$code" ใน Odoo employee.salary');
        return;
      }
      if (!mounted) return;

      setState(() {
        final sd = info['start_date'];
        if (sd is String && sd.isNotEmpty) _employeeStartDate = sd;
        final br = info['branch'];
        if (br is String) _employeeBranch = br;
      });
      debugPrint(
          '✅ [Odoo] start_date="$_employeeStartDate", branch="$_employeeBranch"');
      debugPrint(
          '🧪 [Probation] _isInProbation() = ${_isInProbation()}');

      // ✅ ดึงสิทธิหยุดวันเสาร์/เดือน ตามสาขา จาก Odoo (saturday.leave.config)
      final quota = await OdooRpcService().getSaturdayLeaveQuota(code);
      if (quota != null && mounted) {
        setState(() => _saturdayQuota = quota);
        debugPrint('✅ [Odoo] สิทธิหยุดวันเสาร์/เดือน = $quota ครั้ง');
      }
    } catch (e, st) {
      debugPrint('❌ [Odoo] โหลดข้อมูลพนักงานไม่สำเร็จ: $e');
      debugPrint('Stack: $st');
    }
  }

  /// ตรวจว่าพนักงานอยู่สำนักงานใหญ่หรือไม่ (รองรับการสะกดหลายแบบ)
  bool _isHeadOffice() {
    final br = (_employeeBranch ?? '').trim();
    if (br.isEmpty) return false;
    return br.contains('สำนักงานใหญ่') ||
        br.contains('สนง.ใหญ่') ||
        br.contains('สนง ใหญ่') ||
        br.toUpperCase() == 'HQ' ||
        br.toUpperCase() == 'HEAD OFFICE';
  }

  /// นับจำนวนสิทธิหยุดวันเสาร์ที่ใช้แล้วในเดือนเดียวกับ targetDate
  /// ไม่นับ state = ไม่อนุมัติ / ยกเลิก และไม่นับตัวเองในกรณีแก้ไข
  int _countSaturdayLeaveInMonth(DateTime targetDate) {
    int count = 0;
    for (final leave in _leaves) {
      if (leave.leaveType != 'สิทธิหยุดวันเสาร์') continue;
      if (leave.state == 'ไม่อนุมัติ' || leave.state == 'ยกเลิก') continue;
      // ไม่นับ record ที่กำลังแก้ไข (กันนับซ้ำตัวเอง)
      if (_editingRequestId != null && leave.id == _editingRequestId) continue;
      if (leave.leaveStartDate.year == targetDate.year &&
          leave.leaveStartDate.month == targetDate.month) {
        count++;
      }
    }
    return count;
  }

  /// ตรวจกฎสิทธิหยุดวันเสาร์ — โควตา/เดือน ดึงจาก Odoo (saturday.leave.config) ตามสาขา
  /// ถ้าโหลดโควตาจาก Odoo ไม่ได้ → ใช้กฎ fallback (สนง.ใหญ่ 2 / สาขา 1)
  /// return null = ผ่าน, return String = มี error
  String? _checkSaturdayLeaveLimitRule() {
    if (_selectedLeaveType != 'สิทธิหยุดวันเสาร์') return null;
    if (_selectedStartDate == null) return null;

    final isHQ = _isHeadOffice();
    // ✅ ใช้โควตาจาก Odoo ก่อน — ถ้ายังไม่ได้ค่อย fallback กฎเดิม
    final limit = _saturdayQuota ?? (isHQ ? 2 : 1);
    final used = _countSaturdayLeaveInMonth(_selectedStartDate!);

    if (used >= limit) {
      final monthLabel =
          DateFormat('MMMM yyyy', 'th').format(_selectedStartDate!);
      return 'พนักงานใช้สิทธิ์หยุดวันเสาร์ได้เดือนละ '
          '$limit ครั้งเท่านั้น '
          '(เดือน$monthLabel ใช้ไปแล้ว $used ครั้ง)';
    }
    return null;
  }

  /// ตรวจว่ายังอยู่ในช่วงทดลองงาน (ยังไม่ผ่าน 3 เดือน) หรือไม่
  /// คืน true ถ้ายังไม่ผ่านโปร, false ถ้าผ่านแล้ว/ไม่มีข้อมูล
  bool _isInProbation() {
    final sd = _employeeStartDate;
    if (sd == null || sd.isEmpty) return false; // ไม่มีข้อมูล → ไม่บล็อก
    try {
      final start = DateTime.parse(sd);
      final now = DateTime.now();
      // พ้นโปรเมื่อ today >= start + 3 เดือน (Dart auto-normalizes month overflow)
      final probationEnd =
          DateTime(start.year, start.month + 3, start.day);
      return now.isBefore(probationEnd);
    } catch (e) {
      debugPrint('⚠️ parse start_date error: $e');
      return false;
    }
  }

  /// ตรวจกฎ: ลากิจได้รับค่าจ้าง ต้องผ่านโปร 3 เดือน
  /// return null = ผ่าน, return String = มี error
  String? _checkProbationRule() {
    if (_selectedLeaveType != 'ลากิจได้รับค่าจ้าง') return null;
    debugPrint(
        '🧪 [Probation Check] start_date=$_employeeStartDate → isInProbation=${_isInProbation()}');
    if (!_isInProbation()) return null;

    // คำนวณวันที่จะพ้นโปรเพื่อแจ้งให้ผู้ใช้ทราบ
    String hint = '';
    try {
      final start = DateTime.parse(_employeeStartDate!);
      final probationEnd =
          DateTime(start.year, start.month + 3, start.day);
      hint =
          ' (พ้นโปรวันที่ ${DateFormat('d/M/yyyy', 'th').format(probationEnd)})';
    } catch (_) {}

    return 'พนักงานที่ยังไม่ผ่านทดลองงาน 3 เดือน '
        'ไม่สามารถใช้สิทธิ์ "ลากิจได้รับค่าจ้าง" ได้$hint';
  }

  /// ตรวจว่าการลาพักร้อนแจ้งล่วงหน้าเพียงพอหรือไม่ (ต้องอย่างน้อย 3 วัน)
  /// ตัวอย่าง: ลาวันศุกร์ ต้องขอตั้งแต่วันจันทร์ (4 วันก่อนวันลา)
  /// return null = ผ่าน, return String = มี error พร้อมข้อความ
  String? _checkVacationLeadTimeRule() {
    if (_selectedLeaveType != 'ลาพักร้อน') return null;
    if (_selectedStartDate == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final leaveStart = _dateOnly(_selectedStartDate!);
    final daysUntilLeave = leaveStart.difference(today).inDays;

    // ต้องห่างอย่างน้อย 4 วัน (เช่น ลาศุกร์ ต้องขอตั้งแต่จันทร์)
    if (daysUntilLeave < 4) {
      return 'ลาพักร้อนต้องแจ้งล่วงหน้าอย่างน้อย 3 วัน '
          '(เช่น ลาวันศุกร์ ต้องขอตั้งแต่วันจันทร์)';
    }
    return null;
  }

  /// ตรวจว่าช่วงลาตรงกับวันทำงานติดวันหยุดยาวหรือไม่
  /// return null = ผ่าน, return String = มี error พร้อมข้อความ
  String? _checkLongHolidayRule() {
    if (_selectedStartDate == null || _selectedEndDate == null) return null;
    if (_selectedLeaveType == null) return null;
    // ยกเว้น: ลากิจไม่ได้รับค่าจ้าง + ลาป่วยมีใบรับรองแพทย์ + สิทธิหยุดวันเสาร์
    if (_exemptLeaveTypes.contains(_selectedLeaveType)) {
      debugPrint('⏭️ Skip holiday check: exempt type "$_selectedLeaveType"');
      return null;
    }
    if (_longHolidayRanges.isEmpty) {
      debugPrint('⚠️ Skip holiday check: no long holiday data loaded');
      return null;
    }
    debugPrint(
        '🔎 Check holiday rule: type=$_selectedLeaveType start=$_selectedStartDate end=$_selectedEndDate, ranges=${_longHolidayRanges.length}');

    final leaveStart = _dateOnly(_selectedStartDate!);
    final leaveEnd = _dateOnly(_selectedEndDate!);

    for (final range in _longHolidayRanges) {
      final holidayStart = range.first;
      final holidayEnd = range.last;

      final workingBefore = _findWorkingDayBefore(holidayStart);
      final workingAfter = _findWorkingDayAfter(holidayEnd);

      for (final target in [workingBefore, workingAfter]) {
        if (target == null) continue;
        // ช่วงลาครอบคลุม target หรือไม่?
        if (!leaveStart.isAfter(target) && !leaveEnd.isBefore(target)) {
          final fmt = DateFormat('d/M/yyyy');
          return 'ห้ามลาหลังวันหยุดยาว (วันหยุด ${fmt.format(holidayStart)} - ${fmt.format(holidayEnd)})';
        }
      }
    }
    return null;
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
        _holidayRuleError = null;
      });
      return;
    }

    // ✅ ตรวจวันหยุดยาวก่อน (ถ้าติดให้บล็อก)
    final holidayErr = _checkLongHolidayRule();
    if (holidayErr != null) {
      setState(() {
        _holidayRuleError = holidayErr;
        _isLeaveDurationExceeded = true;
      });
      return;
    } else {
      setState(() {
        _holidayRuleError = null;
      });
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
    // ✅ ตรวจกฎวันหยุดยาวก่อน (double-guard ก่อนส่ง)
    final holidayErr = _checkLongHolidayRule();
    if (holidayErr != null) {
      _showSnackBar(holidayErr, isError: true);
      return;
    }

    // ✅ ตรวจกฎลาพักร้อนต้องแจ้งล่วงหน้าอย่างน้อย 3 วัน
    final vacationErr = _checkVacationLeadTimeRule();
    if (vacationErr != null) {
      _showSnackBar(vacationErr, isError: true);
      return;
    }

    // ✅ ตรวจกฎลากิจได้รับค่าจ้าง ต้องผ่านโปร 3 เดือน
    // หากยังไม่มีข้อมูล start_date → ลองโหลดจาก Odoo อีกรอบก่อน
    if (_selectedLeaveType == 'ลากิจได้รับค่าจ้าง' &&
        (_employeeStartDate == null || _employeeStartDate!.isEmpty)) {
      await _loadEmployeeStartDate();
    }
    final probationErr = _checkProbationRule();
    if (probationErr != null) {
      _showSnackBar(probationErr, isError: true);
      return;
    }

    // ✅ ตรวจกฎสิทธิหยุดวันเสาร์: สนง.ใหญ่ 2 ครั้ง/เดือน, สาขา 1 ครั้ง/เดือน
    // ถ้ายังไม่มีข้อมูล branch → ลองโหลดจาก Odoo อีกรอบ
    if (_selectedLeaveType == 'สิทธิหยุดวันเสาร์' &&
        (_employeeBranch == null || _employeeBranch!.isEmpty)) {
      await _loadEmployeeStartDate();
    }
    final saturdayErr = _checkSaturdayLeaveLimitRule();
    if (saturdayErr != null) {
      _showSnackBar(saturdayErr, isError: true);
      return;
    }

    // Check if leave duration exceeds before submitting
    if (_isLeaveDurationExceeded) {
      _showSnackBar(
          _holidayRuleError ??
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

    // ✅ บังคับแนบไฟล์เมื่อเลือก "ลาป่วยมีใบรับรองแพทย์"
    if (_selectedLeaveType == 'ลาป่วยมีใบรับรองแพทย์') {
      final hasPicked = _pickedFile != null;
      final hasExisting =
          _existingFilePath != null && _existingFilePath!.isNotEmpty;
      if (!hasPicked && !hasExisting) {
        _showSnackBar(
            'กรุณาแนบไฟล์ใบรับรองแพทย์สำหรับการลาป่วยมีใบรับรองแพทย์',
            isError: true);
        return;
      }
    }

    // ✅ บังคับแนบไฟล์เมื่อเลือก "ฉุกเฉิน" (ใบมรณะบัตรของพ่อ/แม่เท่านั้น)
    if (_selectedLeaveType == 'ฉุกเฉิน') {
      final hasPicked = _pickedFile != null;
      final hasExisting =
          _existingFilePath != null && _existingFilePath!.isNotEmpty;
      if (!hasPicked && !hasExisting) {
        _showSnackBar(
            'กรุณาแนบใบมรณะบัตรของบิดา/มารดา (ลาฉุกเฉินใช้ได้กรณีบิดา-มารดาเสียชีวิตเท่านั้น)',
            isError: true);
        return;
      }
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
          title: Text('ยืนยันการยกเลิกคำขอลา', style: GoogleFonts.ibmPlexSansThai()),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('คุณต้องการยกเลิกคำขอลาใช่หรือไม่?',
                    style: GoogleFonts.ibmPlexSansThai()),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child:
                  Text('ไม่ใช่', style: GoogleFonts.ibmPlexSansThai(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('ใช่, ยกเลิกเลย',
                  style: GoogleFonts.ibmPlexSansThai(color: Colors.white)),
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
    // ✅ ถ้าเลือก "ลาพักร้อน" + เป็นวันเริ่มต้น → บังคับ firstDate ให้เลือกได้แค่ 4 วันข้างหน้าขึ้นไป
    DateTime firstDate = DateTime(2000);
    if (isStartDate && _selectedLeaveType == 'ลาพักร้อน') {
      final now = DateTime.now();
      firstDate = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 4));
    }

    // ปรับ initialDate ให้ไม่ก่อน firstDate
    DateTime initialDate = isStartDate
        ? (_selectedStartDate ?? DateTime.now())
        : (_selectedEndDate ?? DateTime.now());
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('th', 'TH'),
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
      builder: (BuildContext context, Widget? child) {
        // บังคับใช้ Material 2 + คง font/สีของแอปไว้ — เพื่อให้ปุ่ม OK/Cancel แสดงชัดเจน
        final base = ThemeData.light(useMaterial3: false);
        return Theme(
          data: base.copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            textTheme:
                GoogleFonts.ibmPlexSansThaiTextTheme(base.textTheme),
          ),
          child: child!,
        );
      },
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
    final TimeOfDay initial = isStartTime
        ? (_selectedStartTime ?? TimeOfDay.now())
        : (_selectedEndTime ?? TimeOfDay.now());

    final TimeOfDay? picked = await _showSimpleTimePicker(context, initial);

    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      final newText = '$hh:$mm';
      setState(() {
        if (isStartTime) {
          _selectedStartTime = picked;
          _startTimeController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        } else {
          _selectedEndTime = picked;
          _endTimeController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        }
      });
    }
  }

  // Time picker แบบ custom — Dropdown ชั่วโมง+นาที พร้อมปุ่ม OK/Cancel ชัดเจน
  // (แทน showTimePicker ของ Material ที่ปุ่มหายเพราะ theme override)
  Future<TimeOfDay?> _showSimpleTimePicker(
      BuildContext context, TimeOfDay initial) async {
    int hour = initial.hour;
    int minute = initial.minute;
    return showDialog<TimeOfDay>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('เลือกเวลา',
                  style: GoogleFonts.ibmPlexSansThai(
                      fontWeight: FontWeight.bold)),
              content: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: hour,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'ชั่วโมง',
                        labelStyle: GoogleFonts.ibmPlexSansThai(),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: List.generate(24, (i) {
                        return DropdownMenuItem<int>(
                          value: i,
                          child: Text(i.toString().padLeft(2, '0'),
                              style:
                                  GoogleFonts.ibmPlexSansThai(fontSize: 16)),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null) setStateDialog(() => hour = v);
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(':',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: minute,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'นาที',
                        labelStyle: GoogleFonts.ibmPlexSansThai(),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: List.generate(60, (i) {
                        return DropdownMenuItem<int>(
                          value: i,
                          child: Text(i.toString().padLeft(2, '0'),
                              style:
                                  GoogleFonts.ibmPlexSansThai(fontSize: 16)),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null) setStateDialog(() => minute = v);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('ยกเลิก',
                      style: GoogleFonts.ibmPlexSansThai(
                          color: Colors.grey.shade700)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label:
                      Text('ตกลง', style: GoogleFonts.ibmPlexSansThai()),
                  onPressed: () => Navigator.of(ctx)
                      .pop(TimeOfDay(hour: hour, minute: minute)),
                ),
              ],
            );
          },
        );
      },
    );
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
                                      style: GoogleFonts.ibmPlexSansThai(
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
                                            style: GoogleFonts.ibmPlexSansThai(
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
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
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
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
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
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
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
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
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
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
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
                                          style: GoogleFonts.ibmPlexSansThai()),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedLeaveType = newValue;

                                      // ✅ ถ้าเปลี่ยนเป็น "ลาพักร้อน" และวันที่เลือกไว้ไม่ผ่านเงื่อนไข 3 วัน → ล้างวันที่
                                      if (newValue == 'ลาพักร้อน' &&
                                          _selectedStartDate != null) {
                                        final now = DateTime.now();
                                        final today = DateTime(
                                            now.year, now.month, now.day);
                                        final daysUntil = _dateOnly(
                                                _selectedStartDate!)
                                            .difference(today)
                                            .inDays;
                                        if (daysUntil < 4) {
                                          _selectedStartDate = null;
                                          _selectedEndDate = null;
                                          _startDateController.clear();
                                          _endDateController.clear();
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            _showSnackBar(
                                                'ลาพักร้อนต้องแจ้งล่วงหน้าอย่างน้อย 3 วัน — กรุณาเลือกวันที่ใหม่',
                                                isError: true);
                                          });
                                        }
                                      }

                                      // ✅ ถ้าเปลี่ยนเป็น "ลากิจได้รับค่าจ้าง" และยังไม่ผ่านโปร → แจ้งทันที
                                      if (newValue == 'ลากิจได้รับค่าจ้าง' &&
                                          _isInProbation()) {
                                        final probationErr =
                                            _checkProbationRule();
                                        if (probationErr != null) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            _showSnackBar(probationErr,
                                                isError: true);
                                          });
                                        }
                                      }

                                      // ✅ ถ้าเปลี่ยนเป็น "สิทธิหยุดวันเสาร์" และโควตาเดือนนั้นเต็มแล้ว → แจ้งทันที
                                      if (newValue == 'สิทธิหยุดวันเสาร์') {
                                        final saturdayErr =
                                            _checkSaturdayLeaveLimitRule();
                                        if (saturdayErr != null) {
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            _showSnackBar(saturdayErr,
                                                isError: true);
                                          });
                                        }
                                      }

                                      // ✅ ถ้าเปลี่ยนเป็น "ฉุกเฉิน" → แจ้งเงื่อนไข + บังคับแนบใบมรณะบัตร
                                      if (newValue == 'ฉุกเฉิน') {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          _showEmergencyLeaveDialog();
                                        });
                                      }
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
                                // ✅ แสดง warning ถาวรเมื่อเลือก "ฉุกเฉิน"
                                if (_selectedLeaveType == 'ฉุกเฉิน')
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.orange.shade300),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.warning_amber_rounded,
                                            color: Colors.orange.shade800,
                                            size: 22),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ลาฉุกเฉินใช้ได้เฉพาะกรณี บิดา/มารดา เสียชีวิตเท่านั้น',
                                                style: GoogleFonts
                                                    .ibmPlexSansThai(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.orange.shade900,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '⚠️ จำเป็นต้องแนบใบมรณะบัตรประกอบ',
                                                style: GoogleFonts
                                                    .ibmPlexSansThai(
                                                  fontSize: 12,
                                                  color: Colors.red.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                // ✅ แสดงสิทธิหยุดวันเสาร์ที่มี / ใช้ไปแล้ว เมื่อเลือกประเภทนี้
                                if (_selectedLeaveType == 'สิทธิหยุดวันเสาร์')
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: Colors.blue.shade200),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.info_outline,
                                            color: Colors.blue.shade700,
                                            size: 22),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Builder(
                                            builder: (context) {
                                              final limit = _saturdayQuota ??
                                                  (_isHeadOffice() ? 2 : 1);
                                              final used = _selectedStartDate !=
                                                      null
                                                  ? _countSaturdayLeaveInMonth(
                                                      _selectedStartDate!)
                                                  : 0;
                                              final remain = (limit - used) < 0
                                                  ? 0
                                                  : (limit - used);
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'สิทธิหยุดวันเสาร์: $limit ครั้ง/เดือน',
                                                    style: GoogleFonts
                                                        .ibmPlexSansThai(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          Colors.blue.shade900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'ใช้ไปแล้ว $used ครั้ง • คงเหลือ $remain ครั้ง'
                                                    '${_selectedStartDate != null ? ' (เดือน${DateFormat('MMMM yyyy', 'th').format(_selectedStartDate!)})' : ''}',
                                                    style: GoogleFonts
                                                        .ibmPlexSansThai(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                // แสดงข้อความแจ้งเตือนเมื่อลาเกิน / ติดวันหยุดยาว
                                if (_isLeaveDurationExceeded)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 16.0),
                                    child: Text(
                                      _holidayRuleError ??
                                          'ไม่สามารถบันทึกคำขอได้เนื่องจากจำนวนวันลาเกินสิทธิ์ที่เหลือ',
                                      style: GoogleFonts.ibmPlexSansThai(
                                          color: Colors.red),
                                    ),
                                  ),
                                TextFormField(
                                  controller: _noteController,
                                  decoration: InputDecoration(
                                    labelText: 'หมายเหตุ (ถ้ามี)',
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
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
                                          color: _selectedLeaveType ==
                                                      'ลาป่วยมีใบรับรองแพทย์' &&
                                                  _pickedFile == null &&
                                                  (_existingFilePath == null ||
                                                      _existingFilePath!
                                                          .isEmpty)
                                              ? Colors.red.shade400
                                              : Colors.grey.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.attach_file,
                                            color: const Color(0xFF1A1A1A)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _pickedFile != null
                                                ? 'ไฟล์ที่เลือก: ${_pickedFile!.name}'
                                                : (_existingFilePath != null &&
                                                        _existingFilePath!
                                                            .isNotEmpty
                                                    ? 'ไฟล์เดิม: ${Uri.parse(_existingFilePath!).pathSegments.last}'
                                                    : (_selectedLeaveType ==
                                                            'ลาป่วยมีใบรับรองแพทย์'
                                                        ? '📎 แนบใบรับรองแพทย์ *(บังคับ)'
                                                        : '📎 แนบไฟล์ (รูปภาพ)')),
                                            style: GoogleFonts.ibmPlexSansThai(
                                                color: _selectedLeaveType ==
                                                            'ลาป่วยมีใบรับรองแพทย์' &&
                                                        _pickedFile == null &&
                                                        (_existingFilePath ==
                                                                null ||
                                                            _existingFilePath!
                                                                .isEmpty)
                                                    ? Colors.red.shade700
                                                    : Colors.grey.shade700),
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
                                            style: GoogleFonts.ibmPlexSansThai()),
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFF1A1A1A),
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
                                        style: GoogleFonts.ibmPlexSansThai(
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
                        style: GoogleFonts.ibmPlexSansThai(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _leaves.isEmpty && !_isLoading
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  'ไม่มีข้อมูลการลา',
                                  style: GoogleFonts.ibmPlexSansThai(
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
                                final dateLabel = leave.leaveStartDate ==
                                        leave.leaveEndDate
                                    ? _formatThaiDate(leave.leaveStartDate)
                                    : '${_formatThaiDate(leave.leaveStartDate)} - ${_formatThaiDate(leave.leaveEndDate)}';
                                return ExpandableHistoryCard(
                                  leadingIcon:
                                      Icons.event_note_rounded,
                                  accentColor: _getStateColor(leave.state),
                                  dateLabel: dateLabel,
                                  typeLabel: leave.leaveType,
                                  status: leave.state,
                                  statusColor: _getStateColor(leave.state),
                                  details: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'เวลาเริ่ม: ${_formatTimeOfDayToString(leave.leaveStartTime)} น.  |  สิ้นสุด: ${_formatTimeOfDayToString(leave.leaveEndTime)} น.',
                                        style: GoogleFonts.ibmPlexSansThai(
                                            fontSize: 13,
                                            color: Colors.grey.shade800),
                                      ),
                                      if (leave.note != null &&
                                          leave.note!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'หมายเหตุ: ${leave.note}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    fontStyle:
                                                        FontStyle.italic,
                                                    color: Colors
                                                        .grey.shade700),
                                          ),
                                        ),
                                      if (leave.department != null &&
                                          leave.department!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'แผนก: ${leave.department}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    color: Colors
                                                        .grey.shade800),
                                          ),
                                        ),
                                      if (leave.position != null &&
                                          leave.position!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'ตำแหน่ง: ${leave.position}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    color: Colors
                                                        .grey.shade800),
                                          ),
                                        ),
                                      if (leave.reason != null &&
                                          leave.reason!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            'เหตุผล (ไม่อนุมัติ): ${leave.reason}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    fontStyle:
                                                        FontStyle.italic,
                                                    color: Colors
                                                        .red.shade800),
                                          ),
                                        ),
                                      if (leave.approvedBy != null &&
                                          leave.approverFirstname != null &&
                                          leave.approverLastname != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            'อนุมัติโดย: ${leave.approverFirstname} ${leave.approverLastname}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    color: Colors
                                                        .grey.shade700),
                                          ),
                                        ),
                                      if (leave.approvedAt != null)
                                        Text(
                                          'เมื่อ: ${DateFormat('d/M/yyyy HH:mm', 'th').format(leave.approvedAt!)}',
                                          style: GoogleFonts.ibmPlexSansThai(
                                              fontSize: 13,
                                              color: Colors.grey.shade700),
                                        ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8.0,
                                        runSpacing: 4.0,
                                        alignment: WrapAlignment.end,
                                        children: [
                                          if (leave.filePath != null &&
                                              leave.filePath!.isNotEmpty &&
                                              (leave.state == 'รออนุมัติ' ||
                                                  leave.state == 'อนุมัติ' ||
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
                                                  style: GoogleFonts
                                                      .ibmPlexSansThai()),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    const Color(0xFF1A1A1A),
                                              ),
                                            ),
                                          if (leave.state == 'รออนุมัติ')
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _editLeaveRequest(leave),
                                              icon: const Icon(Icons.edit,
                                                  size: 18),
                                              label: Text('แก้ไข',
                                                  style: GoogleFonts
                                                      .ibmPlexSansThai()),
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
                                                  style: GoogleFonts
                                                      .ibmPlexSansThai()),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    Colors.red.shade700,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
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
