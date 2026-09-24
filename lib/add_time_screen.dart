import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

import 'package:open_filex/open_filex.dart';
// Assuming User class is in main.dart or a shared model file
import 'full_add_time_history_screen.dart';
import 'main.dart' show User;
import 'widgets/expandable_history_card.dart';
import 'odoo_rpc_service.dart';
import 'ui/app_theme.dart';

// รายชื่อธนาคาร — ต้องตรงกับ thai_banks.py ฝั่ง Odoo (code คือค่าที่เก็บลง DB)
// ใช้เป็นค่าสำรองเมื่อดึงรายชื่อจาก Odoo ไม่ได้ (เน็ตหลุด/เซิร์ฟเวอร์ล่ม)
const List<Map<String, String>> kThaiBanks = [
  {'code': 'KBANK', 'name': 'ธนาคารกสิกรไทย', 'short': 'ธ.กสิกรไทย'},
  {'code': 'BBL', 'name': 'ธนาคารกรุงเทพ', 'short': 'ธ.กรุงเทพ'},
  {'code': 'KTB', 'name': 'ธนาคารกรุงไทย', 'short': 'ธ.กรุงไทย'},
  {'code': 'SCB', 'name': 'ธนาคารไทยพาณิชย์', 'short': 'ธ.ไทยพาณิชย์'},
  {'code': 'BAY', 'name': 'ธนาคารกรุงศรีอยุธยา', 'short': 'ธ.กรุงศรีอยุธยา'},
  {'code': 'TTB', 'name': 'ธนาคารทหารไทยธนชาต', 'short': 'ธ.ทหารไทยธนชาต'},
  {'code': 'GSB', 'name': 'ธนาคารออมสิน', 'short': 'ธ.ออมสิน'},
  {'code': 'UOB', 'name': 'ธนาคารยูโอบี', 'short': 'ธ.ยูโอบี'},
  {'code': 'CIMBT', 'name': 'ธนาคารซีไอเอ็มบีไทย', 'short': 'ธ.ซีไอเอ็มบีไทย'},
  {'code': 'KKP', 'name': 'ธนาคารเกียรตินาคินภัทร', 'short': 'ธ.เกียรตินาคินภัทร'},
  {'code': 'LHBANK', 'name': 'ธนาคารแลนด์ แอนด์ เฮ้าส์', 'short': 'ธ.แลนด์ แอนด์ เฮ้าส์'},
  {'code': 'TISCO', 'name': 'ธนาคารทิสโก้', 'short': 'ธ.ทิสโก้'},
  {'code': 'BAAC', 'name': 'ธนาคารเพื่อการเกษตรและสหกรณ์การเกษตร', 'short': 'ธ.ก.ส.'},
  {'code': 'GHB', 'name': 'ธนาคารอาคารสงเคราะห์', 'short': 'ธอส.'},
  {'code': 'ISBT', 'name': 'ธนาคารอิสลามแห่งประเทศไทย', 'short': 'ธ.อิสลาม'},
  {'code': 'PROMPTPAY', 'name': 'พร้อมเพย์ (PromptPay)', 'short': 'พร้อมเพย์'},
];

/// ประเภทการเพิ่มเวลาที่ต้องกรอกจำนวนเงิน
const String kMedicalReasonType = 'ค่ารักษาพยาบาล';

/// จำนวนไฟล์แนบสูงสุดของค่ารักษาพยาบาล — ต้องตรงกับ MAX_FILES ฝั่ง PHP
const int kMaxMedicalFiles = 10;

// Helper to format TimeOfDay to HH:mm string (can be used without context)
String _formatTimeOfDayToString(TimeOfDay tod) {
  final now = DateTime.now();
  final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
  final format = DateFormat('HH:mm', 'th'); // 'HH:mm'
  return format.format(dt);
}

// Model for an Add Time Log entry
class AddTimeLog {
  final int id;
  final int userId;
  final String username;
  final DateTime workDate;
  final TimeOfDay checkinTime;
  final TimeOfDay checkoutTime;
  final String state;
  final String? department;
  final String? position;
  final DateTime? createdAt;
  final String? reason; // This is the approver's reason
  final String? userNote; // This is the user's note
  final int? approvedBy;
  final String? approverFirstname;
  final String? approverLastname;
  final DateTime? approvedAt;
  final String? reasonType;
  final String? allowanceType;
  final String? amount;
  final String? filePath;
  // ค่ารักษาพยาบาล: บัญชีที่ให้โอนเข้า + ไฟล์แนบหลายไฟล์
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountName;
  final List<String> filePaths;

  AddTimeLog({
    required this.id,
    required this.userId,
    required this.username,
    required this.workDate,
    required this.checkinTime,
    required this.checkoutTime,
    required this.state,
    this.department,
    this.position,
    this.createdAt,
    this.reason,
    this.userNote,
    this.approvedBy,
    this.approverFirstname,
    this.approverLastname,
    this.approvedAt,
    this.reasonType,
    this.allowanceType,
    this.amount,
    this.filePath,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountName,
    this.filePaths = const [],
  });

  factory AddTimeLog.fromJson(Map<String, dynamic> json) {
    // Parse date and time strings
    DateTime workDate = DateTime.parse(json['work_date']);
    TimeOfDay checkinTime =
        TimeOfDay.fromDateTime(DateFormat('HH:mm').parse(json['checkin_time']));
    TimeOfDay checkoutTime = TimeOfDay.fromDateTime(
        DateFormat('HH:mm').parse(json['checkout_time']));

    return AddTimeLog(
      id: int.parse(json['id'].toString()),
      userId: int.parse(json['user_id'].toString()),
      username: json['username'],
      workDate: workDate,
      checkinTime: checkinTime,
      checkoutTime: checkoutTime,
      state: json['state'],
      department: json['department'],
      position: json['position'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      reason: json['reason'],
      userNote: json['user_note'],
      approvedBy: json['approved_by'] != null
          ? int.parse(json['approved_by'].toString())
          : null,
      approverFirstname: json['approver_firstname'],
      approverLastname: json['approver_lastname'],
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'])
          : null,
      reasonType: json['reason_type'],
      allowanceType: json['allowance_type'] == null || json['allowance_type'] == 'NULL'
          ? null
          : json['allowance_type'].toString(),
      amount: json['amount']?.toString(),
      filePath: json['file_path'],
      bankName: _nullIfEmpty(json['bank_name']),
      bankAccountNumber: _nullIfEmpty(json['bank_account_number']),
      bankAccountName: _nullIfEmpty(json['bank_account_name']),
      filePaths: _parseFilePaths(json['file_paths'], json['file_path']),
    );
  }

  /// API เก่าคืน 'NULL' เป็นสตริง ต้องกันไว้ ไม่งั้นจะเอาไปโชว์บนจอ
  static String? _nullIfEmpty(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'NULL' || text == 'null') return null;
    return text;
  }

  /// file_paths อาจมาเป็น List (API ใหม่) หรือ JSON string (ข้อมูลเก่า)
  /// ถ้าไม่มีเลย ให้ถอยไปใช้ file_path ไฟล์เดียวแบบเดิม
  static List<String> _parseFilePaths(dynamic raw, dynamic legacy) {
    final List<String> paths = [];
    if (raw is List) {
      paths.addAll(raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
    } else if (raw is String && raw.trim().isNotEmpty && raw.trim() != 'NULL') {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          paths.addAll(
              decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
        }
      } catch (_) {
        paths.add(raw.trim());
      }
    }
    if (paths.isEmpty) {
      final single = _nullIfEmpty(legacy);
      if (single != null) paths.add(single);
    }
    return paths;
  }

  // Helper to format TimeOfDay to HH:mm string for API (can stay here)
  String formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    final format = DateFormat('HH:mm', 'th'); // 'HH:mm'
    return format.format(dt);
  }

  // Convert to JSON for sending to API
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'work_date': DateFormat('yyyy-MM-dd').format(workDate),
      'checkin_time': formatTimeOfDay(checkinTime),
      'checkout_time': formatTimeOfDay(checkoutTime),
      'state': state,
      'department': department,
      'position': position,
      'created_at': createdAt?.toIso8601String(),
      'reason': reason,
      'user_note': userNote,
      'approved_by': approvedBy,
      'approver_firstname': approverFirstname,
      'approver_lastname': approverLastname,
      'approved_at': approvedAt?.toIso8601String(),
      'reason_type': reasonType,
      'allowance_type': allowanceType,
      'amount': amount,
      'file_path': filePath,
      'bank_name': bankName,
      'bank_account_number': bankAccountNumber,
      'bank_account_name': bankAccountName,
      'file_paths': filePaths,
    };
  }
}

class AddTimeScreen extends StatefulWidget {
  final User user;

  // Optional: Pass an existing log for editing
  final AddTimeLog? logToEdit;

  const AddTimeScreen({super.key, required this.user, this.logToEdit});

  @override
  State<AddTimeScreen> createState() =>
      AddTimeScreenState(); // Changed to public State
}

class AddTimeScreenState extends State<AddTimeScreen> {
  // Changed to public State
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  String? _errorMessage;
  List<AddTimeLog> _logs = [];

  // Form fields
  TextEditingController _dateController = TextEditingController();
  TextEditingController _checkinTimeController = TextEditingController();
  TextEditingController _checkoutTimeController = TextEditingController();
  TextEditingController _userNoteController =
      TextEditingController(); // New controller for user's note
  TextEditingController _amountController = TextEditingController();

  String? _selectedReasonType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedCheckinTime;
  TimeOfDay? _selectedCheckoutTime;
  int? _editingRequestId;

  // Save initial values when entering edit mode to restore on cancel
  DateTime? _initialSelectedDate;
  TimeOfDay? _initialSelectedCheckinTime;
  TimeOfDay? _initialSelectedCheckoutTime;
  String? _initialUserNote;

  // ✅ Add _needsRefresh flag to control initial data fetch in didChangeDependencies
  bool _needsRefresh = true; //

  // ไฟล์ที่เพิ่งเลือกจากเครื่อง (ยังไม่อัปโหลด) — ค่ารักษาพยาบาลเลือกได้หลายไฟล์
  final List<String> _selectedFilePaths = [];
  // ไฟล์ที่อัปโหลดไว้แล้วบนเซิร์ฟเวอร์ (โหมดแก้ไข) ใช้เช็คว่ามีไฟล์แนบอยู่หรือยัง
  List<String> _existingFilePaths = [];

  // รายการประเภทค่าเบี้ยเลี้ยงจาก Odoo (ดึงเมื่อเลือกประเภท "ค่าเบี้ยเลี้ยงออกนอกสถานที่")
  List<Map<String, dynamic>>? _allowanceTypes;
  bool _isLoadingAllowanceTypes = false;
  String? _selectedAllowanceTypeName;
  bool _amountReadonlyFromAllowance = false;

  // ---- ค่ารักษาพยาบาล: บัญชีที่ให้โอนเข้า + วงเงินคงเหลือจาก Odoo ----
  final TextEditingController _bankAccountController = TextEditingController();
  String? _selectedBankCode;
  List<Map<String, String>> _bankOptions = List<Map<String, String>>.from(kThaiBanks);
  bool _isLoadingMedicalInfo = false;
  // ข้อมูลวงเงินจาก Odoo — null = ยังไม่รู้ (ยังไม่โหลด หรือโหลดไม่สำเร็จ)
  // ต้องแยกจาก "คงเหลือ 0" ไม่งั้นเน็ตหลุดทีเดียวพนักงานจะเบิกไม่ได้เลย
  Map<String, dynamic>? _medicalInfo;
  String? _medicalInfoError;

  double? get _medicalRemaining {
    final info = _medicalInfo;
    if (info == null || info['ok'] != true) return null;
    final value = info['remaining'];
    return value is num ? value.toDouble() : null;
  }

  String get _medicalAccountName {
    final info = _medicalInfo;
    final fromOdoo = (info?['employee_name'] ?? '').toString().trim();
    if (fromOdoo.isNotEmpty) return fromOdoo;
    return '${widget.user.firstname} ${widget.user.lastname}'.trim();
  }

  String _bankShortName(String? code) {
    if (code == null || code.isEmpty) return '';
    for (final bank in _bankOptions) {
      if (bank['code'] == code) return bank['short'] ?? bank['name'] ?? code;
    }
    for (final bank in kThaiBanks) {
      if (bank['code'] == code) return bank['short'] ?? code;
    }
    return code;
  }

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('th', null); // Initialize Thai locale for dates

    if (widget.logToEdit != null) {
      // Pre-fill form if editing an existing log
      _editingRequestId = widget.logToEdit!.id;
      _selectedDate = widget.logToEdit!.workDate;
      _selectedCheckinTime = widget.logToEdit!.checkinTime;
      _selectedCheckoutTime = widget.logToEdit!.checkoutTime;
      _userNoteController.text = widget.logToEdit!.userNote ?? '';

      _dateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedDate!);
      _checkinTimeController.text =
          _formatTimeOfDayToString(widget.logToEdit!.checkinTime);
      _checkoutTimeController.text =
          _formatTimeOfDayToString(widget.logToEdit!.checkoutTime);

      // Save initial values for cancel functionality
      _initialSelectedDate = _selectedDate;
      _initialSelectedCheckinTime = _selectedCheckinTime;
      _initialSelectedCheckoutTime = _selectedCheckoutTime;
      _initialUserNote = _userNoteController.text;
    } else {
      // Default values for new request
      _selectedDate = DateTime.now();
      _selectedCheckinTime = const TimeOfDay(hour: 8, minute: 0);
      _selectedCheckoutTime = const TimeOfDay(hour: 17, minute: 0);
      _userNoteController.text = '';

      _dateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedDate!);
      _checkinTimeController.text =
          _formatTimeOfDayToString(_selectedCheckinTime!);
      _checkoutTimeController.text =
          _formatTimeOfDayToString(_selectedCheckoutTime!);
    }

    // หมายเหตุของค่ารักษาพยาบาลสร้างอัตโนมัติ — ต้องอัปเดตทุกครั้งที่แก้จำนวนเงิน/เลขบัญชี
    _amountController.addListener(_onMedicalFieldChanged);
    _bankAccountController.addListener(_onMedicalFieldChanged);

    // _fetchLogs(); // Removed from initState, will be called by refreshData via didChangeDependencies or MainAppScreen
  }

  // ✅ ฟังก์ชันเปิดไฟล์แนบ

  Future<void> _openAttachment(BuildContext context, String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีไฟล์แนบ')),
      );
      return;
    }

    // **(ปรับปรุง) แสดงสถานะกำลังโหลดเพื่อประสบการณ์ใช้งานที่ดีขึ้น**
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กำลังเปิดไฟล์...')),
    );

    try {
      // **(แก้ไข) สร้าง URL ให้ถูกต้องและยืดหยุ่นมากขึ้น**
      const String baseUrl = 'https://npdhrms.com/api/';
      final String finalUrl;

      if (filePath.startsWith('http')) {
        finalUrl = filePath;
      } else if (filePath.startsWith('../')) {
        finalUrl = baseUrl + filePath.substring(3); // ตัด ../ ออก
      } else {
        finalUrl = baseUrl + filePath;
      }

      final response = await http.get(Uri.parse(finalUrl));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final tempDir = await getTemporaryDirectory();

        // **(แก้ไข) ใช้ชื่อไฟล์เดิมเพื่อป้องกันการเขียนทับ**
        final fileName = finalUrl.split('/').last;
        final tempPath = '${tempDir.path}/$fileName';

        final file = File(tempPath);
        await file.writeAsBytes(bytes);

        // เปิดไฟล์ด้วยแอปของระบบ
        await OpenFilex.open(file.path);
      } else {
        throw Exception('ไม่สามารถดาวน์โหลดไฟล์ได้: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถเปิดไฟล์ได้: $e')),
      );
    } finally {
      // ซ่อน SnackBar ของ "กำลังเปิดไฟล์..."
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  // ✅ Add public refreshData method for parent to call
  Future<void> refreshData() async {
    debugPrint('AddTimeScreen: refreshData() called.'); //
    if (mounted) {
      setState(() {
        _isLoading = true; // แสดง loading indicator ทันที
        _errorMessage = null; // เคลียร์ error message เก่า
        _logs = []; // Clear existing data
      });
    }
    await _fetchLogs(); //
  }

  // ดึงรายการประเภทค่าเบี้ยเลี้ยงจาก Odoo (JSON-RPC) อิงจากสาขาของพนักงาน
  Future<void> _fetchAllowanceTypes() async {
    if (mounted) {
      setState(() {
        _isLoadingAllowanceTypes = true;
        _allowanceTypes = null;
      });
    }
    try {
      final code = widget.user.employeeCode ?? '';
      final list =
          await OdooRpcService().getAllowanceTypesByEmployee(code);
      if (mounted) setState(() => _allowanceTypes = list);
    } catch (e) {
      debugPrint('Failed to fetch allowance types: $e');
      if (mounted) setState(() => _allowanceTypes = []);
    } finally {
      if (mounted) setState(() => _isLoadingAllowanceTypes = false);
    }
  }

  /// เลือกไฟล์แนบ — ค่ารักษาพยาบาลเลือกได้หลายไฟล์ ประเภทอื่นได้ไฟล์เดียว
  Future<void> _pickFiles() async {
    // ใช้ ImagePicker แทน FilePicker เพื่อหลีกเลี่ยง READ_MEDIA_IMAGES permission
    final ImagePicker picker = ImagePicker();
    final bool isMedical = _selectedReasonType == kMedicalReasonType;

    if (!isMedical) {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _selectedFilePaths
            ..clear()
            ..add(image.path);
        });
      }
      return;
    }

    final List<XFile> images = await picker.pickMultiImage();
    if (images.isEmpty) return;

    // นับพื้นที่ว่างก่อนเพิ่ม ไม่งั้นจะเตือนเกินจริงเพราะไฟล์ถูกเพิ่มเข้าไปแล้ว
    final int room = kMaxMedicalFiles - _selectedFilePaths.length;
    final bool overflowed = images.length > room;

    setState(() {
      for (final image in images) {
        if (_selectedFilePaths.length >= kMaxMedicalFiles) break;
        if (!_selectedFilePaths.contains(image.path)) {
          _selectedFilePaths.add(image.path);
        }
      }
    });

    if (overflowed) {
      _showSnackBar('แนบไฟล์ได้สูงสุด $kMaxMedicalFiles ไฟล์', isError: true);
    }
  }

  void _removeSelectedFileAt(int index) {
    setState(() {
      if (index >= 0 && index < _selectedFilePaths.length) {
        _selectedFilePaths.removeAt(index);
      }
    });
  }

  // ============================================================
  // ค่ารักษาพยาบาล
  // ============================================================

  /// ดึงวงเงินคงเหลือ + รายชื่อธนาคาร + บัญชีของพนักงาน จาก Odoo
  Future<void> _fetchMedicalInfo() async {
    if (mounted) {
      setState(() {
        _isLoadingMedicalInfo = true;
        _medicalInfoError = null;
      });
    }
    try {
      final code = widget.user.employeeCode ?? '';
      final info = await OdooRpcService()
          .getMedicalExpenseInfo(code, excludePhpId: _editingRequestId);

      if (!mounted) return;
      setState(() {
        _medicalInfo = info;
        if (info == null) {
          _medicalInfoError = 'ติดต่อระบบไม่ได้ — ยังไม่ทราบวงเงินคงเหลือ';
        } else if (info['ok'] != true) {
          _medicalInfoError = (info['message'] ?? '').toString().isNotEmpty
              ? info['message'].toString()
              : 'ไม่พบข้อมูลวงเงินของพนักงาน';
        } else {
          final banks = info['banks'];
          if (banks is List && banks.isNotEmpty) {
            _bankOptions = banks
                .whereType<Map>()
                .map((b) => {
                      'code': (b['code'] ?? '').toString(),
                      'name': (b['name'] ?? '').toString(),
                      'short': (b['short'] ?? '').toString(),
                    })
                .toList();
          }
          // เติมบัญชีที่ผูกไว้กับพนักงานให้อัตโนมัติ (แก้ไขเองได้)
          final defaultBank = (info['bank_name'] ?? '').toString();
          final defaultAccount = (info['bank_account_number'] ?? '').toString();
          if (_selectedBankCode == null &&
              defaultBank.isNotEmpty &&
              _bankOptions.any((b) => b['code'] == defaultBank)) {
            _selectedBankCode = defaultBank;
          }
          if (_bankAccountController.text.trim().isEmpty &&
              defaultAccount.isNotEmpty) {
            _bankAccountController.text = defaultAccount;
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to fetch medical info: $e');
      if (mounted) {
        setState(() {
          _medicalInfo = null;
          _medicalInfoError = 'ติดต่อระบบไม่ได้ — ยังไม่ทราบวงเงินคงเหลือ';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingMedicalInfo = false);
      _syncMedicalNote();
    }
  }

  /// ข้อความหมายเหตุอัตโนมัติ — ต้องตรงกับที่ Odoo สร้าง (_build_auto_note)
  ///   ค่ารักษาพยาบาล 900.00 บาท
  ///   ธ.ไทยพาณิชย์ เลขบัญชี 709-221-2267 น.ส.ปรียดา ฤทธิ์ดี
  String _buildMedicalNote() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final buffer = StringBuffer();
    buffer.write('ค่ารักษาพยาบาล ');
    buffer.write(NumberFormat('#,##0.00').format(amount));
    buffer.write(' บาท');

    final parts = <String>[];
    final bank = _bankShortName(_selectedBankCode);
    if (bank.isNotEmpty) parts.add(bank);
    final account = _bankAccountController.text.trim();
    if (account.isNotEmpty) parts.add('เลขบัญชี $account');
    final holder = _medicalAccountName;
    if (holder.isNotEmpty) parts.add(holder);

    if (parts.isNotEmpty) {
      buffer.writeln();
      buffer.write(parts.join(' '));
    }
    return buffer.toString();
  }

  /// อัปเดตช่องหมายเหตุให้ตรงกับข้อมูลที่เลือกไว้ (เฉพาะค่ารักษาพยาบาล)
  void _syncMedicalNote() {
    if (!mounted) return;
    if (_selectedReasonType != kMedicalReasonType) return;
    final note = _buildMedicalNote();
    if (_userNoteController.text != note) {
      _userNoteController.text = note;
    }
  }

  void _onMedicalFieldChanged() => _syncMedicalNote();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ Fetch data when the widget first becomes active or when dependencies change
    // This is crucial for IndexedStack children to refresh when tab is switched
    if (_needsRefresh) {
      _needsRefresh = false; // Reset flag to prevent continuous re-fetch
      WidgetsBinding.instance.addPostFrameCallback((_) {
        refreshData(); //
      });
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _checkinTimeController.dispose();
    _checkoutTimeController.dispose();
    _userNoteController.dispose();
    _amountController.removeListener(_onMedicalFieldChanged);
    _amountController.dispose();
    _bankAccountController.removeListener(_onMedicalFieldChanged);
    _bankAccountController.dispose();
    super.dispose();
  }

  // === All Helper Methods and Business Logic Methods are defined here, BEFORE build() ===

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

  String _formatThaiDate(DateTime date) {
    final DateFormat formatter = DateFormat('d MMMM yyyy', 'th');
    return formatter.format(date);
  }

  /// ✅ ปุ่ม "แสดงทั้งหมด" — เปิดหน้าประวัติการเพิ่มเวลาย้อนหลังทั้งหมด (เลือกเดือน/ปีได้)
  Widget _buildShowAllButton() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullAddTimeHistoryScreen(
              user: widget.user,
              initialMonth: DateTime.now().month,
              initialYear: DateTime.now().year,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'แสดงทั้งหมด',
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios,
                size: 12, color: Color(0xFF1A1A1A)),
          ],
        ),
      ),
    );
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

  Future<void> _fetchLogs() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _logs = []; // Clear existing data before fetching
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse(
                'https://npdhrms.com/api/manual_time_logs_test.php?user_id=${widget.user.id}'),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          _errorMessage = 'API response body is empty.';
          debugPrint('Error: API response body is empty in _fetchLogs.');
          if (mounted)
            setState(() {
              _isLoading = false;
            });
          return;
        }

        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData['status'] == 'success') {
          List<dynamic> logsJson = responseData['data'];
          _logs = logsJson.map((json) => AddTimeLog.fromJson(json)).toList();
          _errorMessage = null; // Clear error if successful
        } else {
          _errorMessage = responseData['message'] ?? 'Failed to load logs.';
        }
      } else {
        _errorMessage =
            'Error: ${response.statusCode} - ${response.reasonPhrase}';
        try {
          final Map<String, dynamic> errorData = json.decode(response.body);
          if (errorData.containsKey('message')) {
            _errorMessage =
                'Error: ${response.statusCode} - ${errorData['message']}';
          }
        } catch (e) {
          debugPrint('Failed to parse error body in _fetchLogs: $e');
        }
      }
    } on TimeoutException {
      _errorMessage = 'การเชื่อมต่อล่าช้าเกินกำหนด';
    } on FormatException catch (e) {
      _errorMessage = 'รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์. ($e)';
      debugPrint('FormatException during _fetchLogs: $e');
    } catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e';
      debugPrint('Exception during _fetchLogs: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Dialog เตือนเมื่อเลือกวันที่ที่ไม่ใช่วันหยุด (สำหรับประเภท "ทำงานวันหยุด")
  Future<void> _showHolidayNotMatchDialog() async {
    debugPrint('🔴 _showHolidayNotMatchDialog called, mounted=$mounted');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text('วันที่ไม่ใช่วันหยุด',
                style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'วันที่เลือกไม่ใช่วันอาทิตย์ และไม่ตรงกับวันหยุดบริษัท\n'
          'กรุณาเลือกวันที่ที่เป็นวันหยุด',
          style: GoogleFonts.ibmPlexSansThai(),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('ตกลง', style: GoogleFonts.ibmPlexSansThai()),
          ),
        ],
      ),
    );
  }

  Future<void> _showHolidayCheckErrorDialog(String error) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text('ตรวจสอบวันหยุดไม่ได้',
                style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'ไม่สามารถเชื่อมต่อระบบเพื่อตรวจสอบวันหยุดบริษัทได้\n\n$error',
          style: GoogleFonts.ibmPlexSansThai(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('ปิด', style: GoogleFonts.ibmPlexSansThai()),
          ),
        ],
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDate!.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      _showSnackBar('ไม่สามารถบันทึกคำขอสำหรับวันที่ในอนาคตได้', isError: true);
      return;
    }

    // ✅ ตรวจกฎ "ลืมลงเวลา" — ย้อนหลังได้ไม่เกิน 1 เดือน
    if (_selectedReasonType == 'ลืมลงเวลา') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final selected = DateTime(
          _selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final oneMonthAgo = DateTime(now.year, now.month - 1, now.day);
      if (selected.isBefore(oneMonthAgo)) {
        final daysAgo = today.difference(selected).inDays;
        _showSnackBar(
            'ประเภท "ลืมลงเวลา" สามารถย้อนหลังได้ไม่เกิน 1 เดือน '
            '(เกินมาแล้ว $daysAgo วัน)',
            isError: true);
        return;
      }
    }

    // ✅ ตรวจกฎ "ทำงานวันหยุด" — ต้องเป็นวันอาทิตย์ หรือตรงกับวันหยุดใน Odoo (payroll.holiday)
    if (_selectedReasonType == 'ทำงานวันหยุด') {
      final selected = DateTime(
          _selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final isSunday = selected.weekday == DateTime.sunday;
      if (!isSunday) {
        try {
          final holidays =
              await OdooRpcService().getCompanyHolidays(year: selected.year);
          final isHoliday = holidays.any((h) =>
              h.year == selected.year &&
              h.month == selected.month &&
              h.day == selected.day);
          if (!isHoliday) {
            await _showHolidayNotMatchDialog();
            return;
          }
        } catch (e) {
          await _showHolidayCheckErrorDialog(e.toString());
          return;
        }
      }
    }

    // ✅ ตรวจกฎ "ค่ารักษาพยาบาล"
    if (_selectedReasonType == kMedicalReasonType) {
      // 1) บังคับแนบไฟล์ (ใบเสร็จ/ใบรับรองแพทย์) — แนบได้มากกว่า 1 ไฟล์
      if (_selectedFilePaths.isEmpty && _existingFilePaths.isEmpty) {
        _showSnackBar(
            'ประเภท "ค่ารักษาพยาบาล" ต้องแนบไฟล์ใบเสร็จ/ใบรับรองแพทย์',
            isError: true);
        return;
      }

      // 2) บังคับระบุบัญชีที่ให้โอนเข้า
      if (_selectedBankCode == null || _selectedBankCode!.isEmpty) {
        _showSnackBar('กรุณาเลือกธนาคารที่ต้องการให้โอนเข้า', isError: true);
        return;
      }
      if (_bankAccountController.text.trim().isEmpty) {
        _showSnackBar('กรุณากรอกเลขบัญชีธนาคาร', isError: true);
        return;
      }

      // 3) เบิกได้ไม่เกินวงเงินคงเหลือของปีนี้
      //    ถ้ายังไม่รู้วงเงิน (ติดต่อ Odoo ไม่ได้) ให้ผ่านไปก่อน แล้วไปตรวจซ้ำตอนอนุมัติ
      final remaining = _medicalRemaining;
      final requested = double.tryParse(_amountController.text.trim()) ?? 0.0;
      if (remaining != null && requested > remaining) {
        _showSnackBar(
            'ขอเบิกได้ไม่เกินวงเงินคงเหลือ '
            '${NumberFormat('#,##0.00').format(remaining)} บาท',
            isError: true);
        return;
      }

      // หมายเหตุสร้างอัตโนมัติ — กันกรณีผู้ใช้ยังไม่ได้แตะช่องไหนเลย
      _syncMedicalNote();
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final String apiUrl = 'https://npdhrms.com/api/manual_time_logs_test.php';

      // ✅ ใช้ MultipartRequest
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      request.fields.addAll({
        'user_id': widget.user.id.toString(),
        'username': widget.user.username,
        'work_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'checkin_time': AddTimeLog(
                id: 0,
                userId: 0,
                username: '',
                workDate: DateTime.now(),
                checkinTime: _selectedCheckinTime!,
                checkoutTime: _selectedCheckoutTime!,
                state: '')
            .formatTimeOfDay(_selectedCheckinTime!),
        'checkout_time': AddTimeLog(
                id: 0,
                userId: 0,
                username: '',
                workDate: DateTime.now(),
                checkinTime: _selectedCheckinTime!,
                checkoutTime: _selectedCheckoutTime!,
                state: '')
            .formatTimeOfDay(_selectedCheckoutTime!),
        'department': widget.user.department ?? '',
        'position': widget.user.position ?? '',
        'user_note': _userNoteController.text.trim(),
        'reason_type': _selectedReasonType ?? '',
        'allowance_type': _selectedAllowanceTypeName ?? '',
        'amount': _amountController.text.trim(),
        'bank_name': _selectedReasonType == kMedicalReasonType
            ? (_selectedBankCode ?? '')
            : '',
        'bank_account_number': _selectedReasonType == kMedicalReasonType
            ? _bankAccountController.text.trim()
            : '',
        'bank_account_name': _selectedReasonType == kMedicalReasonType
            ? _medicalAccountName
            : '',
      });

      if (_editingRequestId != null) {
        request.fields['request_id'] = _editingRequestId.toString();
      }

      // ✅ แนบไฟล์ (ถ้ามี)
      // ค่ารักษาพยาบาลส่งเป็น files[] ได้หลายไฟล์ ประเภทอื่นยังใช้ key เดิม (file)
      if (_selectedFilePaths.isNotEmpty) {
        if (_selectedReasonType == kMedicalReasonType) {
          for (final path in _selectedFilePaths) {
            request.files
                .add(await http.MultipartFile.fromPath('files[]', path));
          }
        } else {
          request.files.add(await http.MultipartFile.fromPath(
            'file', // ต้องตรงกับ key ของ API
            _selectedFilePaths.first,
          ));
        }
      }

      // ส่ง request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(responseBody);
        if (responseData['status'] == 'success') {
          _showSnackBar(responseData['message'] ?? 'บันทึกข้อมูลสำเร็จ',
              isError: false);
          _resetForm();
          _fetchLogs();
        } else {
          _showSnackBar(responseData['message'] ?? 'เกิดข้อผิดพลาด',
              isError: true);
        }
      } else {
        _showSnackBar('Error: ${response.statusCode}', isError: true);
      }
    } on TimeoutException {
      _showSnackBar('การเชื่อมต่อล่าช้าเกินกำหนด', isError: true);
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

  /// NEW METHOD: show a confirmation dialog before canceling
  Future<void> _showCancelConfirmationDialog(int logId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('ยืนยันการยกเลิก', style: GoogleFonts.ibmPlexSansThai()),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('คุณต้องการยกเลิกคำขอเพิ่มเวลานี้ใช่หรือไม่?',
                    style: GoogleFonts.ibmPlexSansThai()),
                // Text('การดำเนินการนี้ไม่สามารถยกเลิกได้',
                //     style: GoogleFonts.ibmPlexSansThai(color: Colors.red)),
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
                _cancelLog(logId); // Call the original cancel function
              },
            ),
          ],
        );
      },
    );
  }

  // Original function to cancel a log request
  Future<void> _cancelLog(int logId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('https://npdhrms.com/api/cancel_manual_time_log.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'request_id': logId}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final Map<String, dynamic> responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        _showSnackBar(responseData['message'] ?? 'ยกเลิกคำขอสำเร็จ',
            isError: false);
        _fetchLogs(); // Refresh logs after cancellation
      } else {
        _showSnackBar(responseData['message'] ?? 'ไม่สามารถยกเลิกคำขอได้',
            isError: true);
      }
    } on TimeoutException {
      _showSnackBar('การเชื่อมต่อล่าช้าเกินกำหนด', isError: true);
    } on FormatException catch (e) {
      _showSnackBar('รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์หลังการบันทึก. ($e)',
          isError: true);
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาดในการยกเลิกคำขอ: $e', isError: true);
      debugPrint('Exception during _cancelLog: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Function to reset form to default (new request) state
  void _resetForm() {
    setState(() {
      _editingRequestId = null; // ออกจากโหมดแก้ไข
      _selectedDate = DateTime.now();
      _selectedCheckinTime = const TimeOfDay(hour: 8, minute: 0);
      _selectedCheckoutTime = const TimeOfDay(hour: 17, minute: 0);
      _userNoteController.text = '';

      _dateController.text =
          DateFormat('d/M/yyyy', 'th').format(_selectedDate!);
      _checkinTimeController.text =
          _formatTimeOfDayToString(_selectedCheckinTime!);
      _checkoutTimeController.text =
          _formatTimeOfDayToString(_selectedCheckoutTime!);

      // ✅ Reset เพิ่มเติม
      _selectedReasonType = null;
      _amountController.clear();
      _selectedFilePaths.clear();
      _existingFilePaths = [];
      _selectedAllowanceTypeName = null;
      _amountReadonlyFromAllowance = false;
      _allowanceTypes = null;

      // ค่ารักษาพยาบาล
      _selectedBankCode = null;
      _bankAccountController.clear();
      _medicalInfo = null;
      _medicalInfoError = null;
      _isLoadingMedicalInfo = false;

      // เคลียร์ initial values
      _initialSelectedDate = null;
      _initialSelectedCheckinTime = null;
      _initialSelectedCheckoutTime = null;
      _initialUserNote = null;
    });
  }

  // Function to cancel editing and revert form to initial state
  void _cancelEdit() {
    _resetForm(); // รีเซตกลับเป็นค่า default ของฟอร์มใหม่
    _showSnackBar('ยกเลิกการแก้ไข', isError: false);
  }

  Future<void> _selectDate(BuildContext context) async {
    // ✅ ถ้าประเภทเป็น "ลืมลงเวลา" → ย้อนหลังได้ไม่เกิน 1 เดือน
    final now = DateTime.now();
    DateTime firstDate = DateTime(2000);
    if (_selectedReasonType == 'ลืมลงเวลา') {
      firstDate = DateTime(now.year, now.month - 1, now.day);
    }

    // ปรับ initialDate ให้ไม่ก่อน firstDate
    DateTime initialDate = _selectedDate ?? DateTime.now();
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now(), // Restrict to today and past dates
      locale: const Locale('th', 'TH'), // Set Thai locale for date picker
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
      builder: (BuildContext context, Widget? child) {
        // ใช้ ThemeData.light(useMaterial3: false) ใหม่ทั้งหมด
        // เพื่อตัด custom theme ของแอป ที่ทำให้ปุ่ม OK/Cancel หายไป
        // แต่คง font IBM Plex Sans Thai + primary color ของผู้ใช้ไว้
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

    if (picked != null && picked != _selectedDate) {
      if (picked.isAfter(DateTime.now())) {
        _showSnackBar('ไม่สามารถเลือกวันที่ในอนาคตได้', isError: true);
      } else {
        setState(() {
          _selectedDate = picked;
          _dateController.text = DateFormat('d/M/yyyy', 'th').format(picked);
        });
      }
    }
  }

  Future<void> _selectTime(BuildContext context,
      {required bool isCheckin}) async {
    final TimeOfDay initial = isCheckin
        ? (_selectedCheckinTime ?? TimeOfDay.now())
        : (_selectedCheckoutTime ?? TimeOfDay.now());

    final TimeOfDay? picked = await _showSimpleTimePicker(context, initial);

    if (picked != null) {
      final hh = picked.hour.toString().padLeft(2, '0');
      final mm = picked.minute.toString().padLeft(2, '0');
      final newText = '$hh:$mm';
      setState(() {
        if (isCheckin) {
          _selectedCheckinTime = picked;
          _checkinTimeController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        } else {
          _selectedCheckoutTime = picked;
          _checkoutTimeController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        }
      });
    }
  }

  // Time picker แบบ custom — ใช้ Dropdown ชั่วโมง + นาที พร้อมปุ่ม OK/Cancel ชัดเจน
  // (แทน showTimePicker ที่ปุ่ม OK/Cancel มักหายเพราะ theme override)
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
                  // ชั่วโมง
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
                              style: GoogleFonts.ibmPlexSansThai(fontSize: 16)),
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
                  // นาที
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
                              style: GoogleFonts.ibmPlexSansThai(fontSize: 16)),
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
                  label: Text('ตกลง',
                      style: GoogleFonts.ibmPlexSansThai()),
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

  void _editLog(AddTimeLog log) {
    if (log.state == 'รออนุมัติ') {
      setState(() {
        _editingRequestId = log.id;
        _selectedDate = log.workDate;
        _selectedCheckinTime = log.checkinTime;
        _selectedCheckoutTime = log.checkoutTime;
        _userNoteController.text = log.userNote ?? '';

        _dateController.text =
            DateFormat('d/M/yyyy', 'th').format(_selectedDate!);
        _checkinTimeController.text = _selectedCheckinTime!.format(context);
        _checkoutTimeController.text = _selectedCheckoutTime!.format(context);

        // Save initial values for cancel functionality
        _initialSelectedDate = _selectedDate;
        _initialSelectedCheckinTime = _selectedCheckinTime;
        _initialSelectedCheckoutTime = _selectedCheckoutTime;
        _initialUserNote = _userNoteController.text;
        _selectedReasonType = log.reasonType;
        _amountController.text = log.amount ?? '';
        // คืนค่าประเภทค่าเบี้ยเลี้ยงที่เคยเลือกไว้ (ถ้ามี)
        _selectedAllowanceTypeName = log.allowanceType;
        _amountReadonlyFromAllowance = false;

        // ไฟล์เดิมที่อัปโหลดไว้แล้ว — ถ้าไม่เลือกไฟล์ใหม่ ระบบจะคงไฟล์ชุดนี้ไว้
        _selectedFilePaths.clear();
        _existingFilePaths = List<String>.from(log.filePaths);

        // ค่ารักษาพยาบาล: คืนค่าบัญชีที่เคยกรอกไว้
        _selectedBankCode = log.bankName;
        _bankAccountController.text = log.bankAccountNumber ?? '';
        _medicalInfo = null;
        _medicalInfoError = null;

        if (log.reasonType == 'ค่าเบี้ยเลี้ยงออกนอกสถานที่') {
          _fetchAllowanceTypes();
        } else {
          _allowanceTypes = null;
        }
        if (log.reasonType == kMedicalReasonType) {
          _fetchMedicalInfo();
        }
      });
      // Scroll to the top of the screen to show the form
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

  /// แถบแสดงวงเงินค่ารักษาพยาบาลคงเหลือของปีนี้ (ดึงจาก Odoo)
  Widget _buildMedicalQuotaBanner() {
    if (_isLoadingMedicalInfo) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.frame(Theme.of(context).colorScheme.primary)),
        ),
        child: Row(
          children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text('กำลังตรวจสอบวงเงินคงเหลือ...',
                style: GoogleFonts.ibmPlexSansThai(fontSize: 13)),
          ],
        ),
      );
    }

    // ติดต่อ Odoo ไม่ได้ / ไม่พบพนักงาน — เตือนแต่ยังให้ยื่นคำขอได้ ไปตรวจซ้ำตอนอนุมัติ
    if (_medicalInfoError != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_medicalInfoError!,
                  style: GoogleFonts.ibmPlexSansThai(
                      fontSize: 13, color: Colors.orange.shade900)),
            ),
            TextButton(
              onPressed: _fetchMedicalInfo,
              child: Text('ลองใหม่', style: GoogleFonts.ibmPlexSansThai(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    final info = _medicalInfo;
    if (info == null || info['ok'] != true) return const SizedBox.shrink();

    final formatter = NumberFormat('#,##0.00');
    final double limit = (info['limit'] as num?)?.toDouble() ?? 0.0;
    final double approved = (info['used_approved'] as num?)?.toDouble() ?? 0.0;
    final double pending = (info['used_pending'] as num?)?.toDouble() ?? 0.0;
    final double remaining = (info['remaining'] as num?)?.toDouble() ?? 0.0;
    final int? year = info['year'] as int?;
    final bool isEmpty = remaining <= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isEmpty ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isEmpty ? Colors.red.shade200 : Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEmpty ? Icons.block : Icons.account_balance_wallet,
                size: 18,
                color: isEmpty ? Colors.red.shade700 : Colors.green.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'คงเหลือที่เบิกได้ ${formatter.format(remaining)} บาท',
                  style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isEmpty ? Colors.red.shade800 : Colors.green.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'วงเงินปี ${year ?? DateTime.now().year}: ${formatter.format(limit)} บาท'
            '  •  อนุมัติแล้ว ${formatter.format(approved)} บาท'
            '  •  รออนุมัติ ${formatter.format(pending)} บาท',
            style: GoogleFonts.ibmPlexSansThai(
                fontSize: 12, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  /// ส่วนเลือกไฟล์แนบ — ค่ารักษาพยาบาลแนบได้หลายไฟล์ ประเภทอื่นได้ไฟล์เดียว
  Widget _buildAttachmentPicker() {
    final bool isMedical = _selectedReasonType == kMedicalReasonType;
    final bool canAddMore =
        !isMedical || _selectedFilePaths.length < kMaxMedicalFiles;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.frame(Theme.of(context).colorScheme.primary)),
      ),
      child: Column(
        children: [
          // ไฟล์ที่เพิ่งเลือกจากเครื่อง (ยังไม่อัปโหลด)
          for (int i = 0; i < _selectedFilePaths.length; i++)
            ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file, color: Color(0xFF1A1A1A)),
              title: Text(
                _selectedFilePaths[i].split('/').last,
                style: GoogleFonts.ibmPlexSansThai(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: Icon(Icons.close, size: 20, color: Colors.red.shade700),
                tooltip: 'เอาออก',
                onPressed: () => _removeSelectedFileAt(i),
              ),
            ),

          // ไฟล์เดิมบนเซิร์ฟเวอร์ (โหมดแก้ไข) — แตะเพื่อเปิดดู
          if (_selectedFilePaths.isEmpty)
            for (final path in _existingFilePaths)
              ListTile(
                dense: true,
                leading: Icon(Icons.cloud_done, color: Colors.green.shade700),
                title: Text(
                  path.split('/').last,
                  style: GoogleFonts.ibmPlexSansThai(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('ไฟล์ที่แนบไว้แล้ว',
                    style: GoogleFonts.ibmPlexSansThai(
                        fontSize: 11, color: Colors.grey.shade600)),
                onTap: () => _openAttachment(context, path),
              ),

          if (_selectedFilePaths.isEmpty && _existingFilePaths.isEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file, color: Color(0xFF1A1A1A)),
              title: Text('ยังไม่ได้เลือกไฟล์',
                  style: GoogleFonts.ibmPlexSansThai(fontSize: 14)),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isMedical)
                  Text(
                    'เลือกแล้ว ${_selectedFilePaths.length}/$kMaxMedicalFiles ไฟล์',
                    style: GoogleFonts.ibmPlexSansThai(
                        fontSize: 12, color: Colors.grey.shade700),
                  )
                else
                  const SizedBox.shrink(),
                TextButton.icon(
                  onPressed: canAddMore ? _pickFiles : null,
                  icon: const Icon(Icons.add_photo_alternate, size: 18),
                  label: Text(
                    isMedical
                        ? 'เพิ่มไฟล์'
                        : (_selectedFilePaths.isEmpty ? 'เลือกไฟล์' : 'เปลี่ยนไฟล์'),
                    style: GoogleFonts.ibmPlexSansThai(
                        color: const Color(0xFF1A1A1A)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSaveButtonDisabled() {
    if (_selectedDate == null) {
      return true;
    }
    // Compare the selected date with the current date, ignoring time.
    final today = DateTime.now();
    final selectedDay =
        DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    final todayDay = DateTime(today.year, today.month, today.day);

    return selectedDay.isAfter(todayDay);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Dismiss the keyboard when the user taps outside a text field
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppGradientBar(
          title: const Text('เพิ่มเวลาเข้างาน / ออกงาน'),
          // No leading back button here, as this will be part of IndexedStack
        ),
        body: _isLoading && _logs.isEmpty && _errorMessage == null
            ? Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).primaryColor))
            : RefreshIndicator(
                onRefresh: _fetchLogs,
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
                                  onPressed: _fetchLogs,
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
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: AppColors.frame(Theme.of(context).colorScheme.primary))),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  // Wrap title and cancel button in a Row
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _editingRequestId != null
                                          ? '✏️ แก้ไขคำขอเพิ่มเวลา'
                                          : '🕒 บันทึกคำขอเพิ่มเวลา',
                                      style: GoogleFonts.ibmPlexSansThai(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              Theme.of(context).primaryColor),
                                    ),
                                    if (_editingRequestId !=
                                        null) // Show cancel button only in edit mode
                                      TextButton.icon(
                                        onPressed:
                                            _cancelEdit, // Call the new cancel method
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
                                  controller: _dateController,
                                  readOnly: true,
                                  onTap: () => _selectDate(context),
                                  decoration: InputDecoration(
                                    labelText: 'วันที่',
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
                                      return 'กรุณาเลือกวันที่';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _checkinTimeController,
                                  readOnly: true,
                                  onTap: () =>
                                      _selectTime(context, isCheckin: true),
                                  decoration: InputDecoration(
                                    labelText: 'เวลาเข้างาน',
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
                                    prefixIcon: const Icon(Icons.login),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกเวลาเข้างาน';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _checkoutTimeController,
                                  readOnly: true,
                                  onTap: () =>
                                      _selectTime(context, isCheckin: false),
                                  decoration: InputDecoration(
                                    labelText: 'เวลาออกงาน',
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
                                    prefixIcon: const Icon(Icons.logout),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกเวลาออกงาน';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // 👉 เพิ่ม Dropdown นี้ต่อจาก "เวลาออกงาน"
                                DropdownButtonFormField<String>(
                                  value: _selectedReasonType,
                                  decoration: InputDecoration(
                                    labelText: 'ประเภทการเพิ่มเวลา',
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                  ),
                                  items: [
                                    '', // ค่าว่าง (บังคับเลือกใหม่)
                                    'ทำงานนอกสถานที่',
                                    'ทำงานวันหยุด',
                                    'ระบบมีปัญหา',
                                    'ลืมลงเวลา',
                                    'ขอโอที',
                                    'ค่าเบี้ยเลี้ยงออกนอกสถานที่',
                                    'ค่ารักษาพยาบาล',
                                    'ค่าอาหาร',
                                    'ค่าตัวนักแสดง ถ่าย content',
                                  ].map((value) {
                                    if (value.isEmpty) {
                                      return DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('กรุณาเลือก',
                                            style: GoogleFonts.ibmPlexSansThai(
                                                color: Colors.grey)),
                                      );
                                    }
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value,
                                          style: GoogleFonts.ibmPlexSansThai()),
                                    );
                                  }).toList(),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'กรุณาเลือกประเภทการเพิ่มเวลา';
                                    }
                                    return null;
                                  },
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedReasonType = value;

                                      // ✅ ถ้าเปลี่ยนเป็น "ลืมลงเวลา" และวันที่เลือกไว้เกิน 1 เดือนแล้ว → ล้างวันที่
                                      if (value == 'ลืมลงเวลา' &&
                                          _selectedDate != null) {
                                        final now = DateTime.now();
                                        final sel = DateTime(
                                            _selectedDate!.year,
                                            _selectedDate!.month,
                                            _selectedDate!.day);
                                        final oneMonthAgo = DateTime(
                                            now.year, now.month - 1, now.day);
                                        if (sel.isBefore(oneMonthAgo)) {
                                          _selectedDate = null;
                                          _dateController.clear();
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            _showSnackBar(
                                                '"ลืมลงเวลา" ย้อนหลังได้ไม่เกิน 1 เดือน — กรุณาเลือกวันที่ใหม่',
                                                isError: true);
                                          });
                                        }
                                      }

                                      // เคลียร์จำนวนเงินเมื่อเปลี่ยนประเภทที่ไม่ต้องกรอกเงิน
                                      if (value != 'ค่าเบี้ยเลี้ยงออกนอกสถานที่' &&
                                          value != kMedicalReasonType &&
                                          value != 'ค่าอาหาร' &&
                                          value != 'ค่าตัวนักแสดง ถ่าย content') {
                                        _amountController.clear();
                                      }
                                      // รีเซ็ตการเลือกประเภทค่าเบี้ยเลี้ยงเมื่อเปลี่ยนประเภทหลัก
                                      _selectedAllowanceTypeName = null;
                                      _amountReadonlyFromAllowance = false;
                                      if (value == 'ค่าเบี้ยเลี้ยงออกนอกสถานที่') {
                                        _fetchAllowanceTypes();
                                      } else {
                                        _allowanceTypes = null;
                                      }

                                      // ค่ารักษาพยาบาล: ดึงวงเงินคงเหลือ + บัญชีของพนักงาน
                                      if (value == kMedicalReasonType) {
                                        _fetchMedicalInfo();
                                      } else {
                                        _selectedBankCode = null;
                                        _bankAccountController.clear();
                                        _medicalInfo = null;
                                        _medicalInfoError = null;
                                        _isLoadingMedicalInfo = false;
                                        // หมายเหตุกลับมาแก้ไขเองได้ตามปกติ
                                        _userNoteController.clear();
                                        // ประเภทอื่นแนบได้ไฟล์เดียว
                                        if (_selectedFilePaths.length > 1) {
                                          final first = _selectedFilePaths.first;
                                          _selectedFilePaths
                                            ..clear()
                                            ..add(first);
                                        }
                                      }
                                    });
                                  },
                                ),

                                // 👉 ถ้าเลือก "ค่าเบี้ยเลี้ยงออกนอกสถานที่" และมีรายการจาก Odoo — แสดง dropdown ให้เลือก
                                if (_selectedReasonType == 'ค่าเบี้ยเลี้ยงออกนอกสถานที่') ...[
                                  if (_isLoadingAllowanceTypes) ...[
                                    const SizedBox(height: 16),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          SizedBox(width: 12),
                                          Text('กำลังโหลดประเภทค่าเบี้ยเลี้ยง...'),
                                        ],
                                      ),
                                    ),
                                  ] else if (_allowanceTypes != null && _allowanceTypes!.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<String>(
                                      value: _selectedAllowanceTypeName,
                                      isExpanded: true,
                                      autovalidateMode: AutovalidateMode.onUserInteraction,
                                      decoration: InputDecoration(
                                        labelText: 'รายการประเภทค่าเบี้ยเลี้ยง',
                                        labelStyle: GoogleFonts.ibmPlexSansThai(),
                                        border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8)),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                      ),
                                      items: _allowanceTypes!.map((item) {
                                        final name = (item['name'] ?? '').toString();
                                        final amount = item['amount'];
                                        final hasAmount = item['has_amount'] == true;
                                        final label = (hasAmount && amount != null)
                                            ? '$name  (${amount.toString()} บาท)'
                                            : name;
                                        return DropdownMenuItem<String>(
                                          value: name,
                                          child: Text(label,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.ibmPlexSansThai(fontSize: 13)),
                                        );
                                      }).toList(),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'กรุณาเลือกรายการประเภทค่าเบี้ยเลี้ยง';
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedAllowanceTypeName = value;
                                          final selected = _allowanceTypes!.firstWhere(
                                            (e) => e['name'] == value,
                                            orElse: () => <String, dynamic>{},
                                          );
                                          final hasAmount = selected['has_amount'] == true;
                                          if (hasAmount && selected['amount'] != null) {
                                            _amountController.text =
                                                selected['amount'].toString();
                                            _amountReadonlyFromAllowance = true;
                                          } else {
                                            _amountController.clear();
                                            _amountReadonlyFromAllowance = false;
                                          }
                                        });
                                        // เคลียร์ error สีแดงของช่องจำนวนเงินทันทีหลัง auto-fill
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          _formKey.currentState?.validate();
                                        });
                                      },
                                    ),
                                  ],
                                ],

                                // 👉 ค่ารักษาพยาบาล — แสดงวงเงินคงเหลือที่เบิกได้ในปีนี้
                                if (_selectedReasonType == kMedicalReasonType) ...[
                                  const SizedBox(height: 16),
                                  _buildMedicalQuotaBanner(),
                                ],

                                // 👉 แสดงฟิลด์จำนวนเงินเมื่อเลือก ค่าเบี๊ยเลี้ยงฯ หรือ ค่ารักษาพยาบาล
                                if (_selectedReasonType == 'ค่าเบี้ยเลี้ยงออกนอกสถานที่' ||
                                    _selectedReasonType == kMedicalReasonType ||
                                    _selectedReasonType == 'ค่าอาหาร' ||
                                    _selectedReasonType == 'ค่าตัวนักแสดง ถ่าย content') ...[
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _amountController,
                                    readOnly: _amountReadonlyFromAllowance,
                                    autovalidateMode: AutovalidateMode.onUserInteraction,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'จำนวนเงิน (บาท)',
                                      labelStyle: GoogleFonts.ibmPlexSansThai(),
                                      prefixIcon: const Icon(Icons.attach_money),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8)),
                                      filled: true,
                                      fillColor: _amountReadonlyFromAllowance
                                          ? Colors.grey.shade200
                                          : Colors.grey.shade50,
                                      hintText: 'กรอกจำนวนเงิน',
                                      hintStyle: GoogleFonts.ibmPlexSansThai(
                                          color: Colors.grey),
                                      helperText: _selectedReasonType == kMedicalReasonType &&
                                              _medicalRemaining != null
                                          ? 'เบิกได้ไม่เกิน ${NumberFormat('#,##0.00').format(_medicalRemaining)} บาท'
                                          : null,
                                      helperStyle: GoogleFonts.ibmPlexSansThai(
                                          color: Colors.grey.shade700),
                                    ),
                                    validator: (value) {
                                      if (_selectedReasonType == 'ค่าเบี้ยเลี้ยงออกนอกสถานที่' ||
                                          _selectedReasonType == kMedicalReasonType ||
                                          _selectedReasonType == 'ค่าอาหาร' ||
                                          _selectedReasonType == 'ค่าตัวนักแสดง ถ่าย content') {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'กรุณากรอกจำนวนเงิน';
                                        }
                                        final amount = double.tryParse(value.trim());
                                        if (amount == null || amount <= 0) {
                                          return 'กรุณากรอกจำนวนเงินที่ถูกต้อง';
                                        }
                                        // ค่ารักษาพยาบาลเบิกได้ไม่เกินวงเงินคงเหลือของปีนี้
                                        if (_selectedReasonType == kMedicalReasonType) {
                                          final remaining = _medicalRemaining;
                                          if (remaining != null && amount > remaining) {
                                            return 'เกินวงเงินคงเหลือ '
                                                '(${NumberFormat('#,##0.00').format(remaining)} บาท)';
                                          }
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                ],

                                // 👉 ค่ารักษาพยาบาล — บัญชีที่ต้องการให้โอนเข้า
                                if (_selectedReasonType == kMedicalReasonType) ...[
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    value: _bankOptions.any((b) => b['code'] == _selectedBankCode)
                                        ? _selectedBankCode
                                        : null,
                                    isExpanded: true,
                                    autovalidateMode: AutovalidateMode.onUserInteraction,
                                    decoration: InputDecoration(
                                      labelText: 'ธนาคารที่ต้องการให้โอนเข้า',
                                      labelStyle: GoogleFonts.ibmPlexSansThai(),
                                      prefixIcon: const Icon(Icons.account_balance),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8)),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                    ),
                                    items: _bankOptions.map((bank) {
                                      final code = bank['code'] ?? '';
                                      final name = bank['name'] ?? code;
                                      return DropdownMenuItem<String>(
                                        value: code,
                                        child: Text(name,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.ibmPlexSansThai(fontSize: 14)),
                                      );
                                    }).toList(),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'กรุณาเลือกธนาคารที่ต้องการให้โอนเข้า';
                                      }
                                      return null;
                                    },
                                    onChanged: (value) {
                                      setState(() => _selectedBankCode = value);
                                      _syncMedicalNote();
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _bankAccountController,
                                    autovalidateMode: AutovalidateMode.onUserInteraction,
                                    keyboardType: TextInputType.text,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) =>
                                        FocusScope.of(context).unfocus(),
                                    decoration: InputDecoration(
                                      labelText: 'เลขบัญชีธนาคาร',
                                      labelStyle: GoogleFonts.ibmPlexSansThai(),
                                      prefixIcon: const Icon(Icons.credit_card),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8)),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      hintText: 'เช่น 709-221-2267',
                                      hintStyle: GoogleFonts.ibmPlexSansThai(
                                          color: Colors.grey),
                                      helperText: 'ชื่อบัญชี: $_medicalAccountName',
                                      helperStyle: GoogleFonts.ibmPlexSansThai(
                                          color: Colors.grey.shade700),
                                    ),
                                    validator: (value) {
                                      if (_selectedReasonType != kMedicalReasonType) {
                                        return null;
                                      }
                                      if (value == null || value.trim().isEmpty) {
                                        return 'กรุณากรอกเลขบัญชีธนาคาร';
                                      }
                                      final digits =
                                          value.replaceAll(RegExp(r'[^0-9]'), '');
                                      if (digits.length < 10) {
                                        return 'เลขบัญชีต้องมีอย่างน้อย 10 หลัก';
                                      }
                                      return null;
                                    },
                                  ),
                                ],

                                const SizedBox(height: 16),
                                RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.ibmPlexSansThai(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black),
                                    children: [
                                      TextSpan(
                                        text: _selectedReasonType == kMedicalReasonType
                                            ? 'ไฟล์แนบ (ใบเสร็จ/ใบรับรองแพทย์) '
                                            : 'ไฟล์แนบ ',
                                      ),
                                      if (_selectedReasonType == kMedicalReasonType)
                                        const TextSpan(
                                          text: '*',
                                          style: TextStyle(color: Colors.red),
                                        )
                                      else
                                        const TextSpan(
                                          text: '(ถ้ามี)',
                                          style: TextStyle(
                                              fontWeight: FontWeight.normal),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_selectedReasonType == kMedicalReasonType)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'แนบได้มากกว่า 1 ไฟล์ (สูงสุด $kMaxMedicalFiles ไฟล์)',
                                      style: GoogleFonts.ibmPlexSansThai(
                                          fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                _buildAttachmentPicker(),

                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: _userNoteController,
                                  // หมายเหตุอัตโนมัติยาวกว่า 3 บรรทัดได้ (ชื่อ-นามสกุลยาว)
                                  // ตรึงไว้ 3 บรรทัดแล้วข้อความจะโดนตัดกลางคำ
                                  minLines: 3,
                                  maxLines:
                                      _selectedReasonType == kMedicalReasonType ? null : 3,
                                  readOnly: _selectedReasonType == kMedicalReasonType,
                                  // ค่ารักษาพยาบาลใช้ฟอนต์เล็กลง ข้อความยาวจะได้แสดงครบในกรอบ
                                  style: _selectedReasonType == kMedicalReasonType
                                      ? GoogleFonts.ibmPlexSansThai(
                                          fontSize: 13, height: 1.35)
                                      : GoogleFonts.ibmPlexSansThai(),
                                  textInputAction:
                                      TextInputAction.done, // เพิ่มตรงนี้
                                  onFieldSubmitted: (_) {
                                    // ปิดคีย์บอร์ดเมื่อกด "เสร็จสิ้น"
                                    FocusScope.of(context).unfocus();
                                  },
                                  decoration: InputDecoration(
                                    labelText: _selectedReasonType == kMedicalReasonType
                                        ? 'หมายเหตุ (ระบบสร้างให้อัตโนมัติ)'
                                        : 'หมายเหตุของผู้ใช้งาน (ถ้ามี)',
                                    labelStyle: GoogleFonts.ibmPlexSansThai(),
                                    prefixIcon: const Icon(Icons.notes),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: _selectedReasonType == kMedicalReasonType
                                        ? Colors.grey.shade200
                                        : Colors.grey.shade50,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _isLoading || _isSaveButtonDisabled()
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
                                if (_isLoading &&
                                    _logs
                                        .isNotEmpty) // Show progress indicator if submitting form
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              'ประวัติการเพิ่มเวลา (ล่าสุด 7 วัน)',
                              style: GoogleFonts.ibmPlexSansThai(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          _buildShowAllButton(),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _logs.isEmpty && !_isLoading
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  'ไม่มีข้อมูลการเพิ่มเวลา',
                                  style: GoogleFonts.ibmPlexSansThai(
                                      fontSize: 16,
                                      color: Colors.grey.shade600),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                final log = _logs[index];
                                final typeLabel = (log.reasonType != null &&
                                        log.reasonType!.isNotEmpty)
                                    ? log.reasonType!
                                    : 'เพิ่มเวลาทำงาน';
                                return ExpandableHistoryCard(
                                  leadingIcon: Icons.more_time_rounded,
                                  accentColor: _getStateColor(log.state),
                                  dateLabel: _formatThaiDate(log.workDate),
                                  typeLabel: typeLabel,
                                  status: log.state,
                                  statusColor: _getStateColor(log.state),
                                  details: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'เข้า: ${_formatTimeOfDayToString(log.checkinTime)} น.  |  ออก: ${_formatTimeOfDayToString(log.checkoutTime)} น.',
                                        style: GoogleFonts.ibmPlexSansThai(
                                            fontSize: 13,
                                            color: Colors.grey.shade800),
                                      ),
                                      if (log.department != null &&
                                          log.department!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text('แผนก: ${log.department}',
                                              style: GoogleFonts
                                                  .ibmPlexSansThai(
                                                      fontSize: 13,
                                                      color: Colors
                                                          .grey.shade800)),
                                        ),
                                      if (log.position != null &&
                                          log.position!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                              'ตำแหน่ง: ${log.position}',
                                              style: GoogleFonts
                                                  .ibmPlexSansThai(
                                                      fontSize: 13,
                                                      color: Colors
                                                          .grey.shade800)),
                                        ),
                                      if (log.allowanceType != null &&
                                          log.allowanceType!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'รายการประเภทค่าเบี้ยเลี้ยง: ${log.allowanceType}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                              fontSize: 13,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                        ),
                                      if (log.amount != null &&
                                          log.amount!.isNotEmpty &&
                                          log.amount != '0' &&
                                          log.amount != '0.00')
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'จำนวนเงิน: ${log.amount} บาท',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                              fontSize: 13,
                                              color: Colors.green.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      if (log.bankName != null ||
                                          log.bankAccountNumber != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'โอนเข้า: ${_bankShortName(log.bankName)} '
                                            '${log.bankAccountNumber ?? ''}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                              fontSize: 13,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                        ),
                                      if (log.userNote != null &&
                                          log.userNote!.isNotEmpty &&
                                          log.userNote != 'NULL')
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            'หมายเหตุ: ${log.userNote}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    fontStyle:
                                                        FontStyle.italic,
                                                    color: Colors
                                                        .grey.shade700),
                                          ),
                                        ),
                                      if (log.reason != null &&
                                          log.reason!.isNotEmpty &&
                                          log.reason != 'NULL')
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            'เหตุผลจากผู้อนุมัติ: ${log.reason}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    fontStyle:
                                                        FontStyle.italic,
                                                    color:
                                                        Colors.red.shade700),
                                          ),
                                        ),
                                      if (log.approvedBy != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            'อนุมัติโดย: ${log.approverFirstname ?? ''} ${log.approverLastname ?? ''}',
                                            style:
                                                GoogleFonts.ibmPlexSansThai(
                                                    fontSize: 13,
                                                    color: Colors
                                                        .grey.shade700),
                                          ),
                                        ),
                                      if (log.approvedAt != null)
                                        Text(
                                          'เมื่อ: ${DateFormat('d/M/yyyy HH:mm', 'th').format(log.approvedAt!)}',
                                          style: GoogleFonts.ibmPlexSansThai(
                                              fontSize: 13,
                                              color: Colors.grey.shade700),
                                        ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        alignment: WrapAlignment.end,
                                        children: [
                                          // ค่ารักษาพยาบาลแนบได้หลายไฟล์ — ทำปุ่มแยกทีละไฟล์
                                          for (int i = 0;
                                              i < log.filePaths.length;
                                              i++)
                                            TextButton.icon(
                                              onPressed: () {
                                                _openAttachment(context,
                                                    log.filePaths[i]);
                                              },
                                              icon: const Icon(
                                                  Icons.attach_file,
                                                  size: 18),
                                              label: Text(
                                                  log.filePaths.length > 1
                                                      ? 'ไฟล์แนบ ${i + 1}'
                                                      : 'ดูไฟล์แนบ',
                                                  style: GoogleFonts
                                                      .ibmPlexSansThai()),
                                            ),
                                          if (log.state == 'รออนุมัติ')
                                            TextButton.icon(
                                              onPressed: () => _editLog(log),
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
                                          if (log.state != 'ยกเลิก')
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _showCancelConfirmationDialog(
                                                      log.id),
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
