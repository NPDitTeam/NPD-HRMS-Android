// Imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';

import 'main.dart'; // Assuming this imports your User model

class PayslipScreen extends StatefulWidget {
  final User user;
  const PayslipScreen({super.key, required this.user});

  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  final String _payslipApiUrl = 'https://npdhrms.com/api/get_payslip_data.php';
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _selectedPayslipData;
  List<Map<String, dynamic>> _payslipHistory = [];

  String? _selectedMonth;
  String? _selectedYear;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('th', null);
    _fetchPayslipData();
  }

  Future<void> _fetchPayslipData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _payslipHistory = [];
      _selectedPayslipData = null;
    });

    final employeeCode = widget.user.employeeCode;
    if (employeeCode == null || employeeCode.isEmpty) {
      setState(() {
        _errorMessage = 'ไม่พบรหัสพนักงาน';
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse(_payslipApiUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'employee_code': employeeCode}),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200 || response.body.isEmpty) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final Map<String, dynamic> responseData =
          json.decode(response.body) as Map<String, dynamic>;

      if (responseData['status'] == 'success') {
        final List<dynamic>? rawPayslips = responseData['data'];

        if (rawPayslips != null) {
          _payslipHistory = List<Map<String, dynamic>>.from(rawPayslips
              .map((item) {
                if (item is Map<dynamic, dynamic>) {
                  return item.map<String, dynamic>(
                      (key, value) => MapEntry(key.toString(), value));
                }
                return <String, dynamic>{};
              })
              .where((item) => item.isNotEmpty)
              .toList());

          _payslipHistory = _payslipHistory.map((item) {
            return {
              ...item,
              'month': item['month']?.toString(),
              'year': item['year']?.toString(),
            };
          }).toList();

          _payslipHistory.sort((a, b) {
            final aDate = DateTime(
                int.parse(a['year'] ?? '0'), int.parse(a['month'] ?? '0'));
            final bDate = DateTime(
                int.parse(b['year'] ?? '0'), int.parse(b['month'] ?? '0'));
            return bDate.compareTo(aDate);
          });

          if (_payslipHistory.isNotEmpty) {
            final latestPayslip = _payslipHistory.first;
            _selectedMonth = latestPayslip['month'].toString();
            _selectedYear = latestPayslip['year'].toString();
            _updateSelectedPayslip();
          } else {
            _errorMessage = 'ไม่พบข้อมูลสลิปเงินเดือนสำหรับพนักงานนี้';
          }
        } else {
          _errorMessage = 'ไม่พบข้อมูลสลิปเงินเดือน';
        }
      } else {
        _errorMessage = responseData['message'] ?? 'ไม่สามารถดึงข้อมูลได้';
      }
    } on TimeoutException {
      _errorMessage = 'การเชื่อมต่อหมดเวลา';
    } on FormatException {
      _errorMessage = 'รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์';
    } on TypeError catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาดในการแปลงข้อมูล: $e';
    } catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาด: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _updateSelectedPayslip() {
    if (_selectedMonth != null && _selectedYear != null) {
      _selectedPayslipData = _payslipHistory.firstWhere(
        (d) =>
            d['month'].toString() == _selectedMonth &&
            d['year'].toString() == _selectedYear,
        orElse: () => {},
      );
    }
    if (_selectedPayslipData != null && _selectedPayslipData!.isEmpty) {
      _selectedPayslipData = null;
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ต้องการสิทธิ์เข้าถึงพื้นที่เก็บข้อมูล'),
          content: const Text(
              'แอปต้องการสิทธิ์เข้าถึงพื้นที่เก็บข้อมูลเพื่อบันทึกและแชร์ไฟล์สลิปเงินเดือน กรุณาไปที่การตั้งค่าเพื่อเปิดใช้งานสิทธิ์นี้'),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('เปิดการตั้งค่า'),
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePayslipToDevice() async {
    if (_selectedPayslipData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีข้อมูลสลิปเงินเดือนให้บันทึก')),
      );
      return;
    }

    try {
      if (Platform.isAndroid) {
        final pluginInfo = await DeviceInfoPlugin().androidInfo;
        if (pluginInfo.version.sdkInt >= 33) {
          // Android 13 or higher
          // No direct storage permission needed for downloads folder
        } else {
          var status = await Permission.storage.request();
          if (!status.isGranted) {
            _showPermissionDeniedDialog();
            return;
          }
        }
      }

      final pdfBytes = await _generatePayslipPdf(_selectedPayslipData!);

      final monthAbbr = DateFormat('MMM').format(DateTime(
          int.parse(_selectedYear ?? '0'), int.parse(_selectedMonth ?? '0')));

      String? filePath;

      if (Platform.isAndroid) {
        final downloads = Directory("/storage/emulated/0/Download/NPD");
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }

        filePath =
            "${downloads.path}/payslip_${monthAbbr}_${_selectedYear}.pdf";

        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);

        await OpenFilex.open(filePath);
      } else if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        filePath = "${dir.path}/payslip_${monthAbbr}_${_selectedYear}.pdf";

        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);

        await Share.shareXFiles([XFile(filePath)], text: "สลิปเงินเดือนของคุณ");
      }

      if (mounted && filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("บันทึกแล้ว: $filePath")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("เกิดข้อผิดพลาด: $e")),
        );
      }
    }
  }

  String _getFormattedNumber(dynamic value) {
    final displayValue = (value is num)
        ? value
        : double.tryParse(value?.toString() ?? '0.0') ?? 0.0;
    return NumberFormat('#,##0.00', 'th_TH').format(displayValue);
  }

// ✅ ฟังก์ชันใหม่ แยกออกมา
  String _formatDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return '-';
    try {
      final date = DateTime.parse(value.toString());
      return DateFormat('dd/MM/yyyy', 'th').format(date);
    } catch (e) {
      return value.toString(); // fallback กรณี parse ไม่ได้
    }
  }

  Widget _buildSummaryUI(Map<String, dynamic> data) {
    // รวมรายได้
    final totalIncome = [
      data['base_salary'],
      data['income_cost_of_living'],
      data['income_position_allowance'],
      data['income_experience_allowance'],
      data['income_professional_allowance'],
      data['ot_total_weekday'],
      data['ot_total_holiday'],
      data['ot_total_sunday'],
      data['income_allowance'],
      data['income_food'],
      data['income_transport'],
      data['income_fuel'],
      data['income_commission'],
      data['income_commission_sale'],
      data['income_other'],
    ]
        .map((e) => double.tryParse(e?.toString() ?? '0') ?? 0)
        .reduce((a, b) => a + b);

    // รวมรายการหัก
    final totalDeduction = [
      data['expense_provident'],
      data['expense_advance'],
      data['expense_loan'],
      data['expense_other'],
      data['expense_ksl'],
      data['expense_insurance'],
      data['deduction_late'],
      data['deduction_leave'],
      data['missed_days_deduction'],
      data['tax_monthly'],
      data['sso_total'],
    ]
        .map((e) => double.tryParse(e?.toString() ?? '0') ?? 0)
        .reduce((a, b) => a + b);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('สรุปรายการเงินเดือน',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(),

            // ✅ รายได้
            Text('รายได้ / Income',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            ..._buildDynamicSection([
              {'label': 'เงินเดือน', 'value': data['base_salary']},
              {
                'label': 'เงินประจำตำแหน่ง',
                'value': data['income_position_allowance']
              },
              {
                'label': 'ค่าประสบการณ์',
                'value': data['income_experience_allowance']
              },
              {
                'label': 'ค่าวิชาชีพ',
                'value': data['income_professional_allowance']
              },
              {'label': 'ค่าครองชีพ', 'value': data['income_cost_of_living']},
              {'label': 'ค่าล่วงเวลา/โอที', 'value': data['ot_total_weekday']},
              {
                'label': 'ค่าล่วงเวลา/วันหยุดนักขัตฤกษ์',
                'value': data['ot_total_holiday']
              },
              {'label': 'ค่าล่วงเวลา', 'value': data['ot_total_sunday']},
              {'label': 'เบี้ยเลี้ยง', 'value': data['income_allowance']},
              {'label': 'ค่าอาหาร', 'value': data['income_food']},
              {
                'label': 'ค่าเดินทาง/ค่าเที่ยว',
                'value': data['income_transport']
              },
              {'label': 'อินเซนทีฟ', 'value': data['income_fuel']},
              {
                'label': 'คอมมิชชั่น',
                'value': (double.tryParse(
                            data['income_commission']?.toString() ?? '0') ??
                        0) +
                    (double.tryParse(
                            data['income_commission_sale']?.toString() ?? '0') ??
                        0)
              },
              {'label': 'รายได้อื่นๆ', 'value': data['income_other']},
            ], isDeduction: false),

            // ✅ รวมรายได้
            _summaryRow('รวมรายได้', totalIncome,
                unit: 'บาท', isBold: true, color: Colors.green),

            const Divider(),

            // ✅ รายการหัก
            Text('รายการหัก / Deduction',
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            ..._buildDynamicSection([
              {'label': 'สาย', 'value': data['deduction_late']},
              {'label': 'ลากิจ', 'value': data['deduction_leave']},
              {'label': 'ขาดงาน', 'value': data['missed_days_deduction']},
              {'label': 'ภาษีหัก ณ ที่จ่าย', 'value': data['tax_monthly']},
              {'label': 'ประกันสังคม', 'value': data['sso_total']},
              {
                'label': 'กองทุนสำรองเลี้ยงชีพ',
                'value': data['expense_provident']
              },
              {'label': 'กยศ.', 'value': data['expense_ksl']},
              {'label': 'เบิกเงินล่วงหน้า', 'value': data['expense_advance']},
              {'label': 'เงินกู้', 'value': data['expense_loan']},
              {'label': 'หักอื่นๆ', 'value': data['expense_other']},
            ], isDeduction: true),

            // ✅ รวมรายการหัก
            _summaryRow('รวมรายการหัก', totalDeduction,
                unit: 'บาท', isBold: true, color: Colors.red),

            const Divider(),

            // ✅ ยอดสุทธิ
            _summaryRow('ยอดสุทธิ', data['net_salary'],
                unit: 'บาท', color: const Color(0xFF1A1A1A), isBold: true),
          ],
        ),
      ),
    );
  }

// ฟังก์ชันช่วย: สร้าง section ที่ซ่อน item ที่ value = 0/null
  List<Widget> _buildDynamicSection(List<Map<String, dynamic>> items,
      {bool isDeduction = false}) {
    return items
        .where((item) {
          final val = double.tryParse(item['value']?.toString() ?? '0') ?? 0;
          return val != 0; // แสดงเฉพาะที่มีค่า
        })
        .map((item) => _summaryRow(
              item['label']!,
              item['value'],
              unit: 'บาท',
              color: isDeduction ? Colors.red : Colors.black,
            ))
        .toList();
  }

  Widget _summaryRow(String label, dynamic value,
      {Color color = Colors.black, bool isBold = false, String unit = ''}) {
    final displayValue = double.tryParse(value?.toString() ?? '0') ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              )),
          Text(
            '${_getFormattedNumber(displayValue)} $unit',
            style: GoogleFonts.ibmPlexSansThai(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('สลิปเงินเดือน', style: GoogleFonts.ibmPlexSansThai()),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _fetchPayslipData),
          IconButton(
              icon: const Icon(Icons.share), onPressed: _sharePayslipPdf),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.ibmPlexSansThai(color: Colors.red),
                  ),
                )
              : SingleChildScrollView(
                  // ✅ เพิ่มตรงนี้
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedMonth,
                                items: _payslipHistory
                                    .map((d) => d['month'].toString())
                                    .toSet()
                                    .map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(
                                          DateFormat('MMMM', 'th').format(
                                            DateTime(2000, int.parse(m ?? '1')),
                                          ),
                                          style: GoogleFonts.ibmPlexSansThai(),
                                        )))
                                    .toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedMonth = val;
                                    _updateSelectedPayslip();
                                  });
                                },
                                decoration: const InputDecoration(
                                    labelText: 'เลือกเดือน',
                                    border: InputBorder.none),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedYear,
                                items: _payslipHistory
                                    .map((d) => d['year'].toString())
                                    .toSet()
                                    .map((y) => DropdownMenuItem(
                                        value: y,
                                        child: Text(y,
                                            style: GoogleFonts.ibmPlexSansThai())))
                                    .toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedYear = val;
                                    _updateSelectedPayslip();
                                  });
                                },
                                decoration: const InputDecoration(
                                    labelText: 'เลือกปี',
                                    border: InputBorder.none),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedPayslipData != null &&
                          _selectedPayslipData!.isNotEmpty)
                        _buildSummaryUI(_selectedPayslipData!),
                      if (_selectedPayslipData != null &&
                          _selectedPayslipData!.isNotEmpty)
                        SizedBox(
                          height: 400, // ✅ จำกัดความสูง
                          child: PdfPreview(
                            build: (format) =>
                                _generatePayslipPdf(_selectedPayslipData!),
                            allowPrinting: false,
                            allowSharing: false,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                            pdfFileName:
                                'payslip_${DateFormat('MMM').format(DateTime(int.parse(_selectedYear!), int.parse(_selectedMonth!)))}_${_selectedYear}.pdf',
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton:
          _selectedPayslipData != null && _selectedPayslipData!.isNotEmpty
              ? FloatingActionButton.extended(
                  heroTag: 'save_button',
                  icon: const Icon(Icons.download),
                  label: Text('บันทึกไฟล์', style: GoogleFonts.ibmPlexSansThai()),
                  onPressed: _savePayslipToDevice,
                )
              : null,
    );
  }

  Future<void> _sharePayslipPdf() async {
    if (_selectedPayslipData == null || _selectedPayslipData!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีข้อมูลสลิปเงินเดือนให้แชร์')),
      );
      return;
    }

    try {
      final pdfBytes = await _generatePayslipPdf(_selectedPayslipData!);

      final monthAbbr = DateFormat('MMM').format(DateTime(
          int.parse(_selectedYear ?? '0'), int.parse(_selectedMonth ?? '0')));

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/payslip_${monthAbbr}_${_selectedYear}.pdf';

      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles([XFile(filePath)], text: "สลิปเงินเดือนของคุณ");
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("เกิดข้อผิดพลาดในการแชร์: $e")),
        );
      }
    }
  }

  Future<Uint8List> _generatePayslipPdf(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    final font = pw.Font.ttf(await rootBundle.load("assets/fonts/angsab.ttf"));
    final fontBold =
        pw.Font.ttf(await rootBundle.load("assets/fonts/angsab.ttf"));

    final logoImage = pw.MemoryImage(
      (await rootBundle.load('assets/npd_192x192_padded.png'))
          .buffer
          .asUint8List(),
    );

    String formatCurrency(dynamic value) {
      final numValue = double.tryParse(value?.toString() ?? '0.0') ?? 0.0;
      return NumberFormat('#,##0.00', 'th_TH').format(numValue);
    }

    Map<String, String> getCompanyInfo(String? company) {
      switch (company) {
        case 'นภดลเอสกรุ๊ปจำกัด':
          return {
            'name': 'บริษัท นภดล เอส กรุ๊ป จำกัด',
            'address':
                'ที่อยู่ 156 แขวงบางยี่ขัน เขตบางพลัด กรุงเทพมหานคร 10700  โทร. / แฟกซ์. 02-433-5556'
          };
        case 'เอ็นพีดีสตีลเทคจำกัด':
          return {
            'name': 'บริษัท เอ็นพีดี สตีลเทค จำกัด',
            'address':
                'ที่อยู่ 47/4 หมู่ 2 ตำบลลาดหลุมแก้ว อำเภอลาดหลุมแก้ว จังหวัดปทุมธานี 12140  โทร. / แฟกซ์. 02-433-5556'
          };
        case 'เอ็นพีดีโลจิสติกส์จำกัด':
          return {
            'name': 'บริษัท เอ็นพีดี โลจิสติกส์ จำกัด',
            'address':
                'ที่อยู่ 47/4 หมู่ 2 ตำบลลาดหลุมแก้ว อำเภอลาดหลุมแก้ว จังหวัดปทุมธานี 12140  โทร. / แฟกซ์. 02-433-5556'
          };
        case 'นภดลอินเตอร์เทรดดิ้งจำกัด':
          return {
            'name': 'บริษัท นภดล อินเตอร์เทรดดิ้ง จำกัด',
            'address':
                'ที่อยู่ 154 แขวงบางยี่ขัน เขตบางพลัด กรุงเทพมหานคร 10700  โทร. / แฟกซ์. 02-433-5556'
          };
        case 'นภดลกรุงเทพจำกัด':
          return {
            'name': 'บริษัท นภดล กรุงเทพ จำกัด',
            'address':
                'ที่อยู่ 36/10 หมู่ 2 ตำบลบางเตย อำเภอสามพราน จังหวัดนครปฐม 73210  โทร. / แฟกซ์. 02-433-5556'
          };
        default:
          return {
            'name': 'บริษัท นภดล เอส กรุ๊ป จำกัด',
            'address':
                'ที่อยู่ 156 แขวงบางยี่ขัน เขตบางพลัด กรุงเทพมหานคร 10700  โทร. / แฟกซ์. 02-433-5556'
          };
      }
    }

    final companyInfo = getCompanyInfo(data['company']?.toString());

    // Calculate these variables here so they can be passed to the next function
    final latenessDeduction =
        double.tryParse(data['lateness_deduction']?.toString() ?? '0') ?? 0;
    final leaveDeduction =
        double.tryParse(data['leave_deduction']?.toString() ?? '0') ?? 0;
    final ssoTotal = double.tryParse(data['sso_total']?.toString() ?? '0') ?? 0;
    final taxMonthly =
        double.tryParse(data['tax_monthly']?.toString() ?? '0') ?? 0;
    final totalDeductionCalculated =
        latenessDeduction + leaveDeduction + ssoTotal + taxMonthly;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Row(children: [
                        pw.Image(logoImage, width: 60, height: 60),
                        pw.SizedBox(width: 8),
                        pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(companyInfo['name']!,
                                  style: pw.TextStyle(
                                      font: fontBold, fontSize: 18)),
                              pw.Text(companyInfo['address']!,
                                  style:
                                      pw.TextStyle(font: font, fontSize: 14)),
                            ]),
                      ]),
                      pw.Text('ใบแจ้งเงินเดือน / PAY SLIP',
                          style: pw.TextStyle(font: fontBold, fontSize: 24)),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    children: [
                      pw.Expanded(
                          child: pw.Text(
                              'รหัสพนักงาน: ${data['employee_code'] ?? '-'}',
                              style: pw.TextStyle(font: font, fontSize: 16))),
                      pw.Expanded(
                          child: pw.Text('ชื่อ: ${data['full_name'] ?? '-'}',
                              style: pw.TextStyle(font: font, fontSize: 16))),
                      pw.Expanded(
                          child: pw.Text('ตำแหน่ง: ${data['position'] ?? '-'}',
                              style: pw.TextStyle(font: font, fontSize: 16))),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                          child: pw.Text(
                              'วันที่จ่ายเงิน: ${_formatDate(data['payment_date'])}',
                              style: pw.TextStyle(font: font, fontSize: 16))),
                      pw.Expanded(
                          child: pw.Text('แผนก: ${data['department'] ?? '-'}',
                              style: pw.TextStyle(font: font, fontSize: 16))),
                      pw.Expanded(
                        child: pw.Text(
                          'ประจำเดือน: ${DateFormat.MMMM('th').format(
                            DateTime(
                              int.tryParse(data['year'] ?? '0') ?? 0,
                              int.tryParse(data['month'] ?? '1') ?? 1,
                            ),
                          )} ${data['year'] ?? '-'}',
                          style: pw.TextStyle(font: font, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  _buildCombinedTable(data, font, fontBold),
                  pw.SizedBox(height: 12),
                  pw.Table(
                    border:
                        pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(1),
                      2: const pw.FlexColumnWidth(1),
                      3: const pw.FlexColumnWidth(1),
                      4: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          _pdfCell('รายรับสะสม', fontBold, isHeader: true),
                          _pdfCell('ภาษีสะสม', fontBold, isHeader: true),
                          _pdfCell('ประกันสังคมสะสม', fontBold, isHeader: true),
                          _pdfCell('เงินได้สุทธิ', fontBold, isHeader: true),
                          _pdfCell('เลขที่บัญชี', fontBold, isHeader: true),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          _pdfCell(
                              formatCurrency(data['accumulated_income'] ?? 0.0),
                              font),
                          _pdfCell(
                              formatCurrency(data['accumulated_vat'] ?? 0.0),
                              font),
                          _pdfCell(
                              formatCurrency(
                                  data['accumulated_social_security'] ?? 0.0),
                              font),
                          _pdfCell(formatCurrency(data['net_salary']), font),
                          _pdfCell(
                              data['bank_account_number']?.toString() ?? '-',
                              font),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: PdfPageFormat.a4.landscape.width / 2 - 5,
                        child: pw.Text(
                            'หมายเหตุ: สลิปเงินเดือนถือเป็นความลับไม่ควรเผยแพร่ เพื่อการใช้ได้เฉพาะพนักงานเท่านั้น หรือข้อมูลและภาระภาษีกำลังดังกล่าวอาจกระทบต่อบริษัท มีบทลงโทษโดยให้ออกจากการเป็นพนักงานของบริษัทฯ ทันที',
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 13,
                                fontStyle: pw.FontStyle.italic),
                            textAlign: pw.TextAlign.left),
                      ),
                      pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                                "Recipient's Signature .............................................",
                                style: pw.TextStyle(font: font, fontSize: 15)),
                            pw.SizedBox(height: 15),
                          ]),
                    ],
                  ),
                ],
              ),
              pw.Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('พิมพ์โดย: ${data['full_name'] ?? '-'}',
                        style: pw.TextStyle(font: font, fontSize: 15)),
                    pw.Text(
                        'ออกเอกสาร: ${DateFormat('dd/MM/yyyy HH:mm', 'th').format(DateTime.now())}',
                        style: pw.TextStyle(font: font, fontSize: 15)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  pw.Widget _buildCombinedTable(
      Map<String, dynamic> data, pw.Font font, pw.Font fontBold) {
    final incomes = List<Map<String, dynamic>>.from(data['incomes'] ?? []);
    final deductions =
        List<Map<String, dynamic>>.from(data['deductions'] ?? []);

    // หาความยาวสูงสุด (ในตัวอย่างคือ 14)
    final maxRows =
        incomes.length > deductions.length ? incomes.length : deductions.length;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // 🔹 ฝั่งรายได้
        pw.Expanded(
          child: pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header รายได้
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.grey200,
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("รายได้ / Income",
                          style: pw.TextStyle(font: fontBold, fontSize: 14)),
                      pw.Text("จำนวนเงิน",
                          style: pw.TextStyle(font: fontBold, fontSize: 14)),
                    ],
                  ),
                ),

                // Loop แสดงรายได้
                ...List.generate(maxRows, (i) {
                  final item = i < incomes.length ? incomes[i] : null;
                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(item?['label'] ?? '',
                          style: pw.TextStyle(font: font, fontSize: 12)),
                      pw.Text(
                          item != null ? formatCurrency(item['amount']) : '',
                          style: pw.TextStyle(font: font, fontSize: 12)),
                    ],
                  );
                }),

                pw.Divider(),

                // รวมรายได้
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("รวมรายได้",
                        style: pw.TextStyle(font: fontBold, fontSize: 13)),
                    pw.Text(formatCurrency(data['total_gross']),
                        style: pw.TextStyle(font: fontBold, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ),

        pw.SizedBox(width: 12),

        // 🔹 ฝั่งรายการหัก
        pw.Expanded(
          child: pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header รายการหัก
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.grey200,
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("รายการหัก / Deduction",
                          style: pw.TextStyle(font: fontBold, fontSize: 14)),
                      pw.Text("จำนวนเงิน",
                          style: pw.TextStyle(font: fontBold, fontSize: 14)),
                    ],
                  ),
                ),

                // Loop แสดงรายการหัก + เติมแถวว่าง
                // 🔹 ฝั่งรายการหัก
                ...List.generate(maxRows, (i) {
                  final item = i < deductions.length ? deductions[i] : null;
                  final label = item?['label']?.toString().trim() ?? '';
                  final amount = item?['amount']?.toString().trim() ?? '';

                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(label,
                          style: pw.TextStyle(font: font, fontSize: 12)),
                      pw.Text(
                        (label.isEmpty && amount.isEmpty)
                            ? '.' // ✅ ถ้า label และ amount ว่าง → แสดง .
                            : formatCurrency(item?['amount']),
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: (label.isEmpty && amount.isEmpty)
                              ? PdfColors.white // ✅ ทำให้ตัวเลขเป็นสีขาว
                              : PdfColors.black,
                        ),
                      ),
                    ],
                  );
                }),

                pw.Divider(),

                // รวมรายการหัก
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("รวมรายการหัก",
                        style: pw.TextStyle(font: fontBold, fontSize: 13)),
                    pw.Text(formatCurrency(data['total_deduction']),
                        style: pw.TextStyle(font: fontBold, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String formatCurrency(dynamic value) {
    final numValue = double.tryParse(value?.toString() ?? '0.0') ?? 0.0;
    return NumberFormat('#,##0.00', 'th_TH').format(numValue);
  }

  pw.Widget _pdfCell(String text, pw.Font font,
      {bool isHeader = false, pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: font,
          fontSize: 13,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _pdfCellCustom(
    String text,
    pw.Font font, {
    PdfColor color = PdfColors.white,
    double width = 1.0,
    double height = 30,
    double fontSize = 16, // เพิ่ม parameter fontSize
    bool isBold = false, // เพิ่ม option สำหรับตัวหนา
  }) {
    return pw.Expanded(
      flex: (width * 10).toInt(),
      child: pw.Container(
        height: height,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.5),
          color: color,
        ),
        alignment: pw.Alignment.center,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: font,
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
