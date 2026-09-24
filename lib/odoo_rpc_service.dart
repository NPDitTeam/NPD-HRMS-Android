import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Odoo JSON-RPC Service
/// ใช้ /web/session/authenticate + /web/dataset/call_kw
class OdooRpcService {
  static final OdooRpcService _instance = OdooRpcService._internal();
  factory OdooRpcService() => _instance;
  OdooRpcService._internal();

  // ✅ ตั้งค่า URL ที่นี่จุดเดียว
  static const String baseUrl = 'https://npderp.com';
  static const String db = 'HRMS';
  static const String login = 'Npd_admin';
  static const String password = '1234';

  String? _sessionId;
  int? _uid;

  /// Authenticate กับ Odoo
  Future<bool> authenticate() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/web/session/authenticate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'db': db,
            'login': login,
            'password': password,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] != null && data['result']['uid'] != null) {
          _uid = data['result']['uid'];
          // ดึง session_id จาก cookie
          final cookies = response.headers['set-cookie'];
          if (cookies != null) {
            final match = RegExp(r'session_id=([^;]+)').firstMatch(cookies);
            if (match != null) {
              _sessionId = match.group(1);
            }
          }
          debugPrint('✅ Odoo authenticated: uid=$_uid');
          return true;
        }
      }
      debugPrint('❌ Odoo authentication failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('❌ Odoo authentication error: $e');
      return false;
    }
  }

  /// เรียก Odoo model ผ่าน JSON-RPC
  Future<dynamic> callKw({
    required String model,
    required String method,
    List<dynamic> args = const [],
    Map<String, dynamic> kwargs = const {},
  }) async {
    // authenticate ถ้ายังไม่ได้
    if (_sessionId == null) {
      final ok = await authenticate();
      if (!ok) throw Exception('ไม่สามารถเชื่อมต่อ Odoo ได้');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/web/dataset/call_kw'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'session_id=$_sessionId',
      },
      body: json.encode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': model,
          'method': method,
          'args': args,
          'kwargs': kwargs,
        },
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['error'] != null) {
        // session หมดอายุ - authenticate ใหม่แล้วลองอีกครั้ง
        if (data['error']['message']?.toString().contains('Session') == true ||
            data['error']['code'] == 100) {
          debugPrint('⚠️ Session expired, re-authenticating...');
          _sessionId = null;
          final ok = await authenticate();
          if (!ok) throw Exception('Session หมดอายุ ไม่สามารถ login ใหม่ได้');
          return callKw(model: model, method: method, args: args, kwargs: kwargs);
        }
        throw Exception(data['error']['data']?['message'] ?? data['error']['message'] ?? 'Odoo error');
      }
      return data['result'];
    } else {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  /// search_read ข้อมูลจาก model
  Future<List<dynamic>> searchRead({
    required String model,
    List<dynamic> domain = const [],
    List<String> fields = const [],
    int limit = 0,
    int offset = 0,
    String order = '',
  }) async {
    if (_sessionId == null) {
      final ok = await authenticate();
      if (!ok) throw Exception('ไม่สามารถเชื่อมต่อ Odoo ได้');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/web/dataset/call_kw'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'session_id=$_sessionId',
      },
      body: json.encode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'model': model,
          'method': 'search_read',
          'args': [domain],
          'kwargs': {
            'fields': fields,
            if (limit > 0) 'limit': limit,
            if (offset > 0) 'offset': offset,
            if (order.isNotEmpty) 'order': order,
          },
        },
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['error'] != null) {
        if (data['error']['code'] == 100) {
          _sessionId = null;
          final ok = await authenticate();
          if (!ok) throw Exception('Session หมดอายุ');
          return searchRead(model: model, domain: domain, fields: fields, limit: limit, offset: offset, order: order);
        }
        throw Exception(data['error']['data']?['message'] ?? 'Odoo error');
      }
      return data['result'] ?? [];
    } else {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  // ===== API Methods สำหรับแอป =====

  /// ดึงข้อมูลพนักงานจาก employee.salary
  /// สถานะพักงาน ณ วันนี้ — คืน null ถ้าไม่ได้ถูกพักงาน
  ///
  /// อ่านจาก employee.suspension ใน Odoo ซึ่งเป็นที่เดียวที่ HR บันทึกคำสั่ง
  /// ใช้ตอนเข้าหน้าลงเวลาเพื่อกันไม่ให้คนที่ถูกพักงานตอกบัตร
  Future<Map<String, dynamic>?> getSuspensionStatus(String employeeCode) async {
    if (employeeCode.isEmpty) return null;
    try {
      final today = DateTime.now();
      final todayStr = '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final rows = await searchRead(
        model: 'employee.suspension',
        domain: [
          ['employee_code', '=', employeeCode],
          ['active', '=', true],
          ['date_start', '<=', todayStr],
          ['date_end', '>=', todayStr],
        ],
        fields: const ['date_start', 'date_end', 'reason', 'note', 'day_count'],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first as Map);
    } catch (e) {
      // ถามไม่ได้ก็ให้ลงเวลาได้ตามปกติ ดีกว่าบล็อกคนทั้งบริษัทเพราะเน็ตสะดุด
      debugPrint('เช็คสถานะพักงานไม่สำเร็จ: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getEmployeeInfo(String employeeCode) async {
    final results = await searchRead(
      model: 'employee.salary',
      domain: [['employee_code', '=', employeeCode]],
      fields: [
        'firstname', 'lastname', 'nickname', 'firstname_eng', 'lastname_eng',
        'employee_code', 'department_id', 'position_id', 'branch_id',
        'company', 'salary', 'experience_allowance',
        'position_allowance', 'cost_of_living', 'professional_allowance',
        'employee_type', 'advance_payment_type', 'advance_payment_limit',
        'status', 'gender', 'nationality', 'marital_status',
        'birthdate', 'age', 'phone_number', 'email',
        'id_card_number', 'passport_number', 'social_security_number',
        'address', 'start_date',
      ],
      limit: 1,
    );
    if (results.isEmpty) return null;
    final emp = results[0];
    return {
      'name': '${emp['firstname'] ?? ''} ${emp['lastname'] ?? ''}'.trim(),
      'firstname': emp['firstname'] ?? '',
      'lastname': emp['lastname'] ?? '',
      'nickname': emp['nickname'] is String ? emp['nickname'] : '',
      'firstname_eng': emp['firstname_eng'] is String ? emp['firstname_eng'] : '',
      'lastname_eng': emp['lastname_eng'] is String ? emp['lastname_eng'] : '',
      'employee_code': emp['employee_code'] ?? '',
      'department': emp['department_id'] is List ? (emp['department_id'] as List).last : (emp['department_id'] ?? ''),
      'position': emp['position_id'] is List ? (emp['position_id'] as List).last : (emp['position_id'] ?? ''),
      'branch': emp['branch_id'] is List ? (emp['branch_id'] as List).last : (emp['branch_id'] ?? ''),
      'company': emp['company'] ?? '',
      'salary': emp['salary'] ?? 0,
      'experience_allowance': emp['experience_allowance'] ?? 0,
      'position_allowance': emp['position_allowance'] ?? 0,
      'cost_of_living': emp['cost_of_living'] ?? 0,
      'professional_fee': emp['professional_allowance'] ?? 0,
      'employee_type': emp['employee_type'] ?? '',
      'advance_amount': emp['advance_payment_type'] is String ? emp['advance_payment_type'] : '-',
      'advance_limit': emp['advance_payment_limit'] ?? 0,
      'status': emp['status'] ?? 'active',
      'gender': emp['gender'] is String ? emp['gender'] : '',
      'nationality': emp['nationality'] is String ? emp['nationality'] : '',
      'marital_status': emp['marital_status'] is String ? emp['marital_status'] : '',
      'birthdate': emp['birthdate'] is String ? emp['birthdate'] : '',
      'age': emp['age'] ?? 0,
      'phone_number': emp['phone_number'] is String ? emp['phone_number'] : '',
      'email': emp['email'] is String ? emp['email'] : '',
      'id_card_number': emp['id_card_number'] is String ? emp['id_card_number'] : '',
      'passport_number': emp['passport_number'] is String ? emp['passport_number'] : '',
      'social_security_number': emp['social_security_number'] is String ? emp['social_security_number'] : '',
      'address': emp['address'] is String ? emp['address'] : '',
      'start_date': emp['start_date'] is String ? emp['start_date'] : '',
    };
  }

  /// ดึงรายการทวิ50 ทุกปี
  Future<List<Map<String, dynamic>>> getWtCertList(String employeeCode) async {
    // 1. หา employee.salary id
    final empResults = await searchRead(
      model: 'employee.salary',
      domain: [['employee_code', '=', employeeCode]],
      fields: ['id'],
      limit: 1,
    );
    if (empResults.isEmpty) return [];
    final empId = empResults[0]['id'];

    // 2. หา hr.withholding.tax.cert ที่ state = done
    final certs = await searchRead(
      model: 'hr.withholding.tax.cert',
      domain: [
        ['employee_id', '=', empId],
        ['state', '=', 'done'],
      ],
      fields: [
        'id', 'name', 'report_year', 'state',
        'company_id', 'employee_taxid',
        'wt_line', 'total_net_salary', 'total_tax',
        // ยอดกองทุนทั้งปี — อยู่บนหนังสือรับรองฯ ต้องแสดงในแอปด้วย
        'sso_amount', 'provident_fund_amount',
      ],
      // ไม่ใส่ limit เพื่อให้ได้ทุกปีที่เคยออกเอกสาร (เรียงปีใหม่สุดขึ้นก่อน)
      order: 'report_year desc',
    );

    List<Map<String, dynamic>> result = [];
    for (final cert in certs) {
      // 3. ดึง wt_line detail
      List<dynamic> lineIds = cert['wt_line'] ?? [];
      List<Map<String, dynamic>> lines = [];
      if (lineIds.isNotEmpty) {
        final lineData = await searchRead(
          model: 'hr.withholding.tax.cert.line',
          domain: [['id', 'in', lineIds]],
          fields: ['wt_cert_income_type', 'wt_cert_income_desc', 'base', 'wt_percent', 'amount'],
        );
        lines = lineData.map<Map<String, dynamic>>((l) => {
          'description': l['wt_cert_income_desc'] ?? l['wt_cert_income_type'] ?? '',
          'base': l['base'] ?? 0,
          'amount': l['amount'] ?? 0,
        }).toList();
      }

      result.add({
        'id': cert['id'],
        'name': cert['name'] ?? '',
        'report_year': cert['report_year'] ?? '',
        'state': cert['state'] ?? '',
        'company_name': cert['company_id'] is List ? (cert['company_id'] as List).last : '',
        'employee_taxid': cert['employee_taxid'] ?? '',
        'total_net_salary': cert['total_net_salary'] ?? 0,
        'total_tax': cert['total_tax'] ?? 0,
        'sso_amount': cert['sso_amount'] ?? 0,
        'provident_fund_amount': cert['provident_fund_amount'] ?? 0,
        'lines': lines,
      });
    }
    return result;
  }

  /// ดึงตารางงาน hr.work.schedule
  Future<Map<String, dynamic>?> getWorkSchedule(String employeeCode) async {
    final results = await searchRead(
      model: 'hr.work.schedule',
      domain: [['employee_code', '=', employeeCode]],
      fields: [
        'category',
        'work_mon', 'work_tue', 'work_wed', 'work_thu', 'work_fri', 'work_sat',
        'mon_shift_start', 'mon_shift_end',
        'tue_shift_start', 'tue_shift_end',
        'wed_shift_start', 'wed_shift_end',
        'thu_shift_start', 'thu_shift_end',
        'fri_shift_start', 'fri_shift_end',
        'sat_shift_start', 'sat_shift_end',
      ],
      limit: 1,
    );
    if (results.isEmpty) return null;

    final s = results[0];
    final dayMap = {
      'monday': {'enabled': s['work_mon'] ?? false, 'start': s['mon_shift_start'] ?? 0, 'end': s['mon_shift_end'] ?? 0},
      'tuesday': {'enabled': s['work_tue'] ?? false, 'start': s['tue_shift_start'] ?? 0, 'end': s['tue_shift_end'] ?? 0},
      'wednesday': {'enabled': s['work_wed'] ?? false, 'start': s['wed_shift_start'] ?? 0, 'end': s['wed_shift_end'] ?? 0},
      'thursday': {'enabled': s['work_thu'] ?? false, 'start': s['thu_shift_start'] ?? 0, 'end': s['thu_shift_end'] ?? 0},
      'friday': {'enabled': s['work_fri'] ?? false, 'start': s['fri_shift_start'] ?? 0, 'end': s['fri_shift_end'] ?? 0},
      'saturday': {'enabled': s['work_sat'] ?? false, 'start': s['sat_shift_start'] ?? 0, 'end': s['sat_shift_end'] ?? 0},
    };

    List<Map<String, dynamic>> days = [];
    dayMap.forEach((day, val) {
      if (val['enabled'] == true) {
        days.add({
          'day': day,
          'start_hour': val['start'],
          'end_hour': val['end'],
        });
      }
    });

    return {
      'category': s['category'] ?? '',
      'days': days,
    };
  }

  /// ดึงวันหยุดบริษัทจาก payroll.holiday + payroll.holiday.line
  /// คืนค่าเป็น List<DateTime> เรียงจากน้อยไปมาก
  Future<List<DateTime>> getCompanyHolidays({int? year}) async {
    final targetYear = year ?? DateTime.now().year;

    // 1) หา template ของปี
    final templates = await searchRead(
      model: 'payroll.holiday',
      domain: [['year', '=', targetYear]],
      fields: ['id', 'line_ids'],
      limit: 1,
    );
    if (templates.isEmpty) return [];

    final List<dynamic> lineIds = templates[0]['line_ids'] ?? [];
    if (lineIds.isEmpty) return [];

    // 2) ดึงรายการวันหยุด
    final lines = await searchRead(
      model: 'payroll.holiday.line',
      domain: [['id', 'in', lineIds]],
      fields: ['date', 'name'],
      order: 'date asc',
    );

    final List<DateTime> result = [];
    for (final l in lines) {
      final d = l['date'];
      if (d is String && d.isNotEmpty) {
        try {
          result.add(DateTime.parse(d));
        } catch (_) {
          // skip invalid date
        }
      }
    }
    return result;
  }

  /// ดึงสิทธิหยุดวันเสาร์/เดือน ตามสาขาของพนักงาน (ตั้งค่าจาก Odoo: saturday.leave.config)
  /// คืนค่าเป็นจำนวนครั้ง/เดือน — คืน null ถ้าดึงไม่ได้ (ให้ฝั่งเรียกใช้กฎ fallback)
  Future<int?> getSaturdayLeaveQuota(String employeeCode) async {
    if (employeeCode.isEmpty) return null;
    try {
      final result = await callKw(
        model: 'saturday.leave.config',
        method: 'api_get_saturday_quota',
        args: [employeeCode],
      );
      if (result is int) return result;
      if (result is num) return result.toInt();
      if (result is String) return int.tryParse(result);
      return null;
    } catch (e) {
      debugPrint('❌ getSaturdayLeaveQuota error: $e');
      return null;
    }
  }

  /// ดึง "นาทีที่สาย" รายวันของเดือนนั้น สำหรับแสดงใต้เวลาเข้างานในประวัติลงเวลา
  ///
  /// อิงสูตรคิดสายที่ตั้งไว้ใน Odoo (เมนู "กำหนดสูตรคิดสาย") ทั้งหมด —
  /// ฝั่งแอปไม่คำนวณเองสักนิด พอ HR เปลี่ยนสูตรหรือวันเริ่มใช้ แอปตามทันที
  /// และตัวเลขที่โชว์เป็นนาทีเดียวกับที่ payroll หักจริง
  ///
  /// คืน map {'YYYY-MM-DD': {'minutes': นาที, 'checkin': 'HH:MM'}}
  /// เฉพาะวันที่สายจริง (ไม่สาย = ไม่มี key)
  ///
  /// ที่มี `checkin` มาด้วยเพราะวันหนึ่งสแกนเข้าได้หลายครั้ง แต่ระบบคิดสาย
  /// จาก "ครั้งแรกของวัน" ครั้งเดียว แอปต้องรู้ว่าจะแปะข้อความที่แถวไหน
  ///
  /// ดึงไม่ได้ (เน็ตล่ม / ยังไม่ตั้งตารางกะ) จะคืน map ว่าง → แค่ไม่แสดงข้อความ
  Future<Map<String, LateInfo>> getLateMinutes(
      String employeeCode, int month, int year) async {
    if (employeeCode.isEmpty) return {};
    try {
      final result = await callKw(
        model: 'payroll.lateness.rule',
        method: 'api_get_late_minutes',
        args: [employeeCode, month, year],
      );
      if (result is Map) {
        final Map<String, LateInfo> parsed = {};
        result.forEach((key, value) {
          if (value is! Map) return;
          final raw = value['minutes'];
          final minutes =
              raw is num ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
          if (minutes > 0) {
            parsed[key.toString()] = LateInfo(
              minutes: minutes,
              checkin: value['checkin']?.toString() ?? '',
            );
          }
        });
        return parsed;
      }
      return {};
    } catch (e) {
      debugPrint('❌ getLateMinutes error: $e');
      return {};
    }
  }

  /// ดึงชื่อ + ที่อยู่บริษัทตาม "สังกัด" ของพนักงาน สำหรับหัวสลิปเงินเดือน
  ///
  /// อ่านจาก Odoo ที่เดียว (`payroll.salary._company_info_by_key`) ซึ่งเป็นตัวเดียว
  /// กับที่สลิป PDF ฝั่ง Odoo ใช้ — ย้ายออฟฟิศเมื่อไหร่แก้ที่ Odoo จุดเดียว
  /// แอปตามทันทีโดยไม่ต้อง build ใหม่
  ///
  /// คืน null ถ้าดึงไม่ได้ (เน็ตล่ม) → ให้ฝั่งเรียกใช้ค่าสำรองในเครื่อง
  Future<Map<String, String>?> getCompanyInfo(String employeeCode) async {
    if (employeeCode.isEmpty) return null;
    try {
      final result = await callKw(
        model: 'payroll.salary',
        method: 'api_get_company_info',
        args: [employeeCode],
      );
      if (result is Map) {
        final name = result['name']?.toString() ?? '';
        final address = result['address']?.toString() ?? '';
        if (name.isNotEmpty) return {'name': name, 'address': address};
      }
      return null;
    } catch (e) {
      debugPrint('❌ getCompanyInfo error: $e');
      return null;
    }
  }

  /// ดึงรายการประเภทค่าเบี้ยเลี้ยงตามรหัสพนักงาน (อิงจากสาขาของพนักงาน)
  /// คืนค่า: List ของ {name, amount (nullable), has_amount, note}
  Future<List<Map<String, dynamic>>> getAllowanceTypesByEmployee(String employeeCode) async {
    if (employeeCode.isEmpty) return [];
    try {
      final result = await callKw(
        model: 'allowance.management',
        method: 'api_get_allowances_by_employee_code',
        args: [employeeCode],
      );
      if (result is List) {
        return result.whereType<Map>().map<Map<String, dynamic>>((e) {
          return {
            'name': (e['name'] ?? '').toString(),
            'amount': e['amount'] is num ? (e['amount'] as num).toDouble() : null,
            'has_amount': e['has_amount'] == true,
            'note': (e['note'] ?? '').toString(),
          };
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ getAllowanceTypesByEmployee error: $e');
      return [];
    }
  }

  // ===== ค่ารักษาพยาบาล =====

  /// ดึงข้อมูลค่ารักษาพยาบาลที่ต้องใช้ตอนกรอกคำขอ:
  /// วงเงินต่อปี / ใช้ไปแล้ว / คงเหลือที่เบิกได้ / รายชื่อธนาคาร /
  /// บัญชีธนาคารที่ผูกไว้กับพนักงาน
  ///
  /// [excludePhpId] = id ของคำขอที่กำลังแก้ไข เพื่อไม่ให้ยอดของใบนั้นถูกหักซ้ำ
  ///
  /// คืน null เมื่อติดต่อ Odoo ไม่ได้ — ผู้เรียกต้องแยกกรณีนี้ออกจาก
  /// "คงเหลือ 0" ไม่งั้นเน็ตหลุดทีเดียวพนักงานจะเบิกอะไรไม่ได้เลย
  Future<Map<String, dynamic>?> getMedicalExpenseInfo(
    String employeeCode, {
    int? excludePhpId,
  }) async {
    if (employeeCode.isEmpty) return null;
    try {
      final result = await callKw(
        model: 'medical.expense',
        method: 'api_get_medical_info',
        args: [employeeCode, excludePhpId],
      );
      if (result is Map) {
        final banks = <Map<String, String>>[];
        final rawBanks = result['banks'];
        if (rawBanks is List) {
          for (final b in rawBanks) {
            if (b is Map) {
              banks.add({
                'code': (b['code'] ?? '').toString(),
                'name': (b['name'] ?? '').toString(),
                'short': (b['short'] ?? '').toString(),
              });
            }
          }
        }
        double toDouble(dynamic v) =>
            v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

        return {
          'ok': result['ok'] == true,
          'message': (result['message'] ?? '').toString(),
          'year': result['year'] is num ? (result['year'] as num).toInt() : null,
          'employee_name': (result['employee_name'] ?? '').toString(),
          'limit': toDouble(result['limit']),
          'used_approved': toDouble(result['used_approved']),
          'used_pending': toDouble(result['used_pending']),
          'remaining': toDouble(result['remaining']),
          'bank_name': (result['bank_name'] ?? '').toString(),
          'bank_account_number': (result['bank_account_number'] ?? '').toString(),
          'banks': banks,
        };
      }
      return null;
    } catch (e) {
      debugPrint('❌ getMedicalExpenseInfo error: $e');
      return null;
    }
  }

  // ===== ใบเตือนพนักงาน =====

  /// ดึงจำนวนใบเตือนของพนักงาน (เร็ว ใช้โชว์ badge)
  /// คืนจำนวนใบเตือน หรือ null ถ้า "ติดต่อเซิร์ฟเวอร์ไม่ได้"
  ///
  /// ต้องแยก 0 (ไม่มีใบเตือนจริง ๆ) ออกจาก null (ไม่รู้ เพราะเน็ตหลุด)
  /// ไม่งั้นเน็ตกระตุกทีเดียว แอปจะเข้าใจว่าใบเตือนหายหมด แล้วไปลบ
  /// สถานะ "อ่านแล้ว" ทิ้ง พอเน็ตกลับมาก็เด้งแจ้งเตือนใบเก่าซ้ำ
  Future<int?> getEmployeeWarningCount(String employeeCode) async {
    if (employeeCode.isEmpty) return 0;
    // ลองเรียก API method ก่อน
    try {
      final result = await callKw(
        model: 'employee.warning',
        method: 'api_get_warning_count',
        args: [employeeCode],
      );
      if (result is int) return result;
      if (result is num) return result.toInt();
    } catch (e) {
      debugPrint('⚠️ api_get_warning_count not available, fallback to search_read: $e');
    }
    // Fallback: ใช้ search_read โดยตรง
    try {
      final warnings = await searchRead(
        model: 'employee.warning',
        domain: [['employee_code', '=', employeeCode]],
        fields: ['warning_line_ids'],
        limit: 1,
      );
      if (warnings.isEmpty) return 0;
      final lineIds = warnings[0]['warning_line_ids'];
      if (lineIds is List) return lineIds.length;
      return 0;
    } catch (e) {
      debugPrint('❌ getEmployeeWarningCount fallback error: $e');
      return null; // ไม่รู้ ≠ ไม่มี
    }
  }

  /// ดึงรายการใบเตือนทั้งหมดของพนักงาน
  Future<Map<String, dynamic>> getEmployeeWarnings(String employeeCode) async {
    if (employeeCode.isEmpty) {
      return {'has_warning': false, 'warning_count': 0,
              'employee': {}, 'lines': []};
    }
    // ลองเรียก API method ก่อน
    try {
      final result = await callKw(
        model: 'employee.warning',
        method: 'api_get_warnings_by_employee_code',
        args: [employeeCode],
      );
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('⚠️ api_get_warnings_by_employee_code not available, fallback: $e');
    }
    // Fallback: ใช้ search_read โดยตรง
    return await _getEmployeeWarningsFallback(employeeCode);
  }

  /// Fallback ผ่าน search_read (ใช้เมื่อ API method ไม่พร้อม)
  Future<Map<String, dynamic>> _getEmployeeWarningsFallback(
      String employeeCode) async {
    try {
      final warnings = await searchRead(
        model: 'employee.warning',
        domain: [['employee_code', '=', employeeCode]],
        fields: [
          'id', 'employee_code', 'firstname', 'lastname',
          'position_id', 'branch_id', 'department_id',
          'warning_line_ids',
        ],
        limit: 1,
      );
      if (warnings.isEmpty) {
        return {'has_warning': false, 'warning_count': 0,
                'employee': {}, 'lines': []};
      }
      final w = warnings[0];
      final List<dynamic> lineIds = w['warning_line_ids'] ?? [];

      List<Map<String, dynamic>> lines = [];
      if (lineIds.isNotEmpty) {
        final lineData = await searchRead(
          model: 'employee.warning.line',
          domain: [['id', 'in', lineIds]],
          fields: [
            'id', 'warning_date', 'subject', 'warning_type',
            'warning_number', 'description',
            'attachment_filename',
          ],
          order: 'warning_number asc, id asc',
        );
        // ดึง attachment ids
        for (final l in lineData) {
          int attId = 0;
          String attFilename = (l['attachment_filename'] ?? '').toString();
          try {
            final atts = await searchRead(
              model: 'ir.attachment',
              domain: [
                ['res_model', '=', 'employee.warning.line'],
                ['res_id', '=', l['id']],
                ['res_field', '=', 'attachment'],
              ],
              fields: ['id', 'name'],
              limit: 1,
            );
            if (atts.isNotEmpty) {
              attId = (atts[0]['id'] as num).toInt();
              if (attFilename.isEmpty) {
                attFilename = (atts[0]['name'] ?? '').toString();
              }
            }
          } catch (_) {}

          final typeMap = {
            'verbal': 'ตักเตือนด้วยวาจา',
            'written': 'ตักเตือนเป็นหนังสือ',
          };
          final wType = (l['warning_type'] ?? '').toString();
          final wNum = (l['warning_number'] as num?)?.toInt() ?? 0;
          lines.add({
            'id': l['id'],
            'warning_date':
                l['warning_date'] is String ? l['warning_date'] : '',
            'subject': l['subject'] ?? '',
            'warning_type': wType,
            'warning_type_display': typeMap[wType] ?? '',
            'warning_number': wNum,
            'warning_number_display': wNum > 0 ? 'ครั้งที่ $wNum' : '',
            'description':
                l['description'] is String ? l['description'] : '',
            'has_attachment': attId > 0,
            'attachment_id': attId,
            'attachment_filename': attFilename,
            'attachment_url': '',
          });
        }
      }

      String valFromField(dynamic v) {
        if (v is List && v.length >= 2) return v[1].toString();
        return '';
      }

      return {
        'has_warning': lines.isNotEmpty,
        'warning_count': lines.length,
        'employee': {
          'code': w['employee_code'] ?? '',
          'firstname': w['firstname'] ?? '',
          'lastname': w['lastname'] ?? '',
          'position': valFromField(w['position_id']),
          'branch': valFromField(w['branch_id']),
          'department': valFromField(w['department_id']),
        },
        'lines': lines,
      };
    } catch (e) {
      debugPrint('❌ _getEmployeeWarningsFallback error: $e');
      return {'has_warning': false, 'warning_count': 0,
              'employee': {}, 'lines': []};
    }
  }

  /// ดาวน์โหลดไฟล์แนบใบเตือน (คืน bytes)
  Future<List<int>?> getWarningAttachmentBytes(int attachmentId) async {
    if (_sessionId == null) {
      final ok = await authenticate();
      if (!ok) return null;
    }
    try {
      final url = '$baseUrl/api/employee_warning/attachment/$attachmentId';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Cookie': 'session_id=$_sessionId'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      debugPrint('❌ Warning attachment download failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ Error downloading warning attachment: $e');
      return null;
    }
  }

  /// ดาวน์โหลดไฟล์แนบใบเตือนผ่าน ir.attachment โดยตรง (fallback)
  Future<List<int>?> getAttachmentDatasById(int attachmentId) async {
    try {
      final result = await searchRead(
        model: 'ir.attachment',
        domain: [['id', '=', attachmentId]],
        fields: ['datas', 'name', 'mimetype'],
        limit: 1,
      );
      if (result.isEmpty) return null;
      final datas = result[0]['datas'];
      if (datas is String && datas.isNotEmpty) {
        return base64.decode(datas);
      }
      return null;
    } catch (e) {
      debugPrint('❌ getAttachmentDatasById error: $e');
      return null;
    }
  }

  /// ดาวน์โหลด PDF ทวิ50 ผ่าน Odoo report URL
  Future<List<int>?> getWtCertPdfBytes(int certId) async {
    // authenticate ถ้ายังไม่ได้
    if (_sessionId == null) {
      final ok = await authenticate();
      if (!ok) return null;
    }

    try {
      final url = '$baseUrl/report/pdf/npd_hr_wt_cert_form.hr_wt_cert_form/$certId';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Cookie': 'session_id=$_sessionId'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        // ตรวจสอบว่าเป็น PDF จริง (เริ่มต้นด้วย %PDF)
        if (response.bodyBytes.length > 4 && response.bodyBytes[0] == 0x25) {
          return response.bodyBytes;
        }
      }
      debugPrint('❌ PDF download failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ Error downloading PDF: $e');
      return null;
    }
  }
}

/// ข้อมูล "สาย" ของหนึ่งวัน
class LateInfo {
  /// นาทีที่ถูกนับเป็นสาย (ตัวเดียวกับที่ payroll หัก)
  final int minutes;

  /// เวลาเข้างานที่ระบบใช้คำนวณ เช่น "09:52" — ใช้จับคู่ว่าจะแสดงที่แถวไหน
  final String checkin;

  const LateInfo({required this.minutes, required this.checkin});
}
