import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Import Your Screens
import 'checkin_screen.dart';
import 'app_bottom_nav_bar.dart';
import 'add_time_screen.dart';
import 'leave_screen.dart';
import 'payslip_screen.dart';
import 'approve_leave_screen.dart';
import 'approve_add_time_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize date formatting for all locales you support
  await initializeDateFormatting('th', null);
  await initializeDateFormatting('en', null);
  await initializeDateFormatting('es', null);
  await initializeDateFormatting('ja', null);
  await initializeDateFormatting('ko', null);
  await initializeDateFormatting('fr', null);
  await initializeDateFormatting('de', null);
  await initializeDateFormatting('it', null);
  await initializeDateFormatting('pt', null);
  await initializeDateFormatting('ru', null);
  await initializeDateFormatting(
    'ar',
    null,
  ); // For RTL support (needs proper handling)
  await initializeDateFormatting('hi', null);
  await initializeDateFormatting('id', null);
  await initializeDateFormatting('ms', null);
  await initializeDateFormatting('vi', null);
  await initializeDateFormatting('tr', null);
  await initializeDateFormatting('pl', null);
  await initializeDateFormatting('nl', null);
  await initializeDateFormatting('sv', null);
  await initializeDateFormatting('da', null);
  await initializeDateFormatting('fi', null);
  await initializeDateFormatting('no', null);
  await initializeDateFormatting('cs', null);
  await initializeDateFormatting('hr', null);
  await initializeDateFormatting('ro', null);
  await initializeDateFormatting('sk', null);
  await initializeDateFormatting('uk', null);
  await initializeDateFormatting(
    'he',
    null,
  ); // For RTL support (needs extra care)
  await initializeDateFormatting('el', null);
  await initializeDateFormatting('hu', null);
  await initializeDateFormatting('fil', null);
  await initializeDateFormatting('bg', null);
  await initializeDateFormatting('sr', null);
  await initializeDateFormatting('sl', null);
  await initializeDateFormatting('sw', null);
  await initializeDateFormatting('et', null);
  await initializeDateFormatting('lv', null);
  await initializeDateFormatting('lt', null);
  await initializeDateFormatting('zu', null);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _getInitialScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    final isDemoUser =
        prefs.getBool('isDemoUser') ?? false; // ดึงค่า isDemoUser
    if (userDataString != null) {
      return MainAppScreen(
        user: User.fromJson(json.decode(userDataString)),
        isDemoUser: isDemoUser,
      ); // ส่ง isDemoUser
    }
    return const PinLoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    const Color npdOrange = Color.fromARGB(255, 13, 96, 204);
    const Color npdBlue = Color(0xFF007FFF);
    const Color npdPink = Color(0xFFFF69B4);

    const Color lightBackground = Color(0xFFF0F2F5);
    const Color darkText = Color(0xFF333333);

    return MaterialApp(
      // ✅ ล็อกขนาด Text ไม่ให้เปลี่ยนตามการตั้งค่าของมือถือ
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child!,
        );
      },
      title: 'NPD HRMS',
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: npdBlue,
          secondary: npdPink,
          surface: Colors.white,
          error: Colors.red.shade700,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: darkText,
          onError: Colors.white,
          primaryContainer: npdOrange,
        ),
        scaffoldBackgroundColor: lightBackground,
        textTheme: GoogleFonts.kanitTextTheme(
          Theme.of(context).textTheme,
        ).apply(bodyColor: darkText),
        appBarTheme: AppBarTheme(
          backgroundColor: npdBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: GoogleFonts.kanit(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(15)),
          ),
          color: Colors.white,
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: npdOrange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: GoogleFonts.kanit(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: npdBlue,
            textStyle: GoogleFonts.kanit(fontSize: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: npdBlue,
            side: const BorderSide(color: npdBlue),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: GoogleFonts.kanit(fontSize: 16),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: Colors.black87,
          contentTextStyle: GoogleFonts.kanit(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: npdBlue, width: 2),
          ),
          labelStyle: GoogleFonts.kanit(color: darkText),
          hintStyle: GoogleFonts.kanit(color: Colors.grey.shade500),
          prefixIconColor: npdBlue,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: npdOrange,
          linearTrackColor: npdOrange.withOpacity(0.3),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        // English variants (most common ones)
        Locale('en', ''), // English (generic)
        Locale('en', 'US'), // English (United States)
        Locale('en', 'GB'), // English (United Kingdom)
        Locale('en', 'AU'), // English (Australia)
        Locale('en', 'CA'), // English (Canada)
        // Thai
        Locale('th', 'TH'), // Thai (Thailand)
        // Spanish variants
        Locale('es', ''), // Spanish (generic)
        Locale('es', 'ES'), // Spanish (Spain)
        Locale('es', 'MX'), // Spanish (Mexico)
        Locale('es', '419'), // Spanish (Latin America)
        // Chinese variants
        Locale('zh', 'Hans'), // Chinese (Simplified)
        Locale('zh', 'Hant'), // Chinese (Traditional)
        Locale('zh', 'CN'), // Chinese (China mainland)
        Locale('zh', 'TW'), // Chinese (Taiwan)
        Locale('zh', 'HK'), // Chinese (Hong Kong)
        // Other major languages (based on common App/Play Store support)
        Locale('ja', 'JP'), // Japanese (Japan)
        Locale('ko', 'KR'), // Korean (South Korea)
        Locale('fr', ''), // French (generic)
        Locale('fr', 'FR'), // French (France)
        Locale('de', ''), // German (generic)
        Locale('de', 'DE'), // German (Germany)
        Locale('it', ''), // Italian (generic)
        Locale('it', 'IT'), // Italian (Italy)
        Locale('pt', ''), // Portuguese (generic)
        Locale('pt', 'BR'), // Portuguese (Brazil)
        Locale('pt', 'PT'), // Portuguese (Portugal)
        Locale('ru', ''), // Russian (generic)
        Locale('ru', 'RU'), // Russian (Russia)
        Locale(
          'ar',
          '',
        ), // Arabic (generic) - Note: RTL languages require extra care
        Locale('hi', ''), // Hindi (generic)
        Locale('id', ''), // Indonesian (generic)
        Locale('ms', ''), // Malay (generic)
        Locale('vi', ''), // Vietnamese (generic)
        Locale('tr', ''), // Turkish (generic)
        Locale('pl', ''), // Polish (generic)
        Locale('nl', ''), // Dutch (generic)
        Locale('sv', ''), // Swedish (generic)
        Locale('da', ''), // Danish (generic)
        Locale('fi', ''), // Finnish (generic)
        Locale('no', ''), // Norwegian (generic)
        Locale('cs', ''), // Czech (generic)
        Locale('hr', ''), // Croatian (generic)
        Locale('ro', ''), // Romanian (generic)
        Locale('sk', ''), // Slovak (generic)
        Locale('uk', ''), // Ukrainian (generic)
        Locale(
          'he',
          '',
        ), // Hebrew (generic) - Note: RTL languages require extra care
        Locale('el', ''), // Greek (generic)
        Locale('hu', ''), // Hungarian (generic)
        Locale('fil', ''), // Filipino (generic)
        Locale('bg', ''), // Bulgarian (generic)
        Locale('sr', ''), // Serbian (generic)
        Locale('sl', ''), // Slovenian (generic)
        Locale('sw', ''), // Swahili (generic)
        Locale('et', ''), // Estonian (generic)
        Locale('lv', ''), // Latvian (generic)
        Locale('lt', ''), // Lithuanian (generic)
        Locale('zu', ''), // Zulu (generic)
      ],
      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return snapshot.data ?? const PinLoginScreen();
          }
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: npdBlue)),
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class User {
  final int id;
  final String username;
  final String firstname;
  final String lastname;
  final String? department;
  final String? position;
  final String? employeeCode;

  User({
    required this.id,
    required this.username,
    required this.firstname,
    required this.lastname,
    this.department,
    this.position,
    this.employeeCode,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      firstname: json['firstname'],
      lastname: json['lastname'],
      department: json['department'],
      position: json['position'],
      employeeCode: json['employee_code'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'firstname': firstname,
        'lastname': lastname,
        'department': department,
        'position': position,
        'employee_code': employeeCode,
      };
}

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});
  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  String _pin = '';
  bool _isLoading = false;
  String _errorMessage = '';

  void _onKeyPressed(String value) {
    if (_isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _errorMessage = '';
      if (value == 'backspace') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 6) {
        _pin += value;
        if (_pin.length == 6) _performPinLogin();
      }
    });
  }

  Future<String> _getDeviceId() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await info.androidInfo;
        return androidInfo.id;
      }
      if (Platform.isIOS) {
        final iosInfo = await info.iosInfo;
        // The identifierForVendor can sometimes be null.
        // We ensure a valid string is always returned.
        return iosInfo.identifierForVendor ?? 'ios_device_id_unavailable';
      }
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      // Always return a non-null, unique-enough string on error.
      // This fallback is crucial for devices that fail to provide a proper ID.
      return 'error_getting_id_${DateTime.now().millisecondsSinceEpoch}';
    }
    return 'unsupported_platform';
  }

  bool _looksLikeJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String body) {
    try {
      final t = body.trimLeft();
      final decoded = json.decode(t);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _performPinLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final deviceId = await _getDeviceId();
    const String apiUrl = 'https://npdhrms.com/api/api_login_pin_test1.php';

    try {
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'pin': _pin, 'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 45));

      if (!mounted) return;

      String raw = utf8.decode(response.bodyBytes);
      raw = raw.replaceFirst(RegExp(r'^\uFEFF'), '').trimLeft();

      debugPrint('API Response Status Code: ${response.statusCode}');
      debugPrint('API Response CT: ${response.headers['content-type']}');
      debugPrint(
        'API Response Body (first 200): ${raw.substring(0, raw.length.clamp(0, 200))}',
      );

      if (raw.isEmpty) {
        setState(() {
          _errorMessage = 'เซิร์ฟเวอร์ตอบกลับข้อมูลว่างเปล่า';
          _pin = '';
        });
        return;
      }

      if (!_looksLikeJson(raw)) {
        setState(() {
          _errorMessage =
              'ข้อมูลที่ได้รับไม่ใช่ JSON (${response.statusCode}). โปรดตรวจ API/endpoint.';
          _pin = '';
        });
        return;
      }

      final data = _tryDecodeJsonObject(raw);
      if (data == null) {
        setState(() {
          _errorMessage = 'ไม่สามารถอ่านข้อมูล JSON ได้';
          _pin = '';
        });
        return;
      }

      if (response.statusCode == 200 && data['status'] == 'success') {
        final user = User.fromJson({
          ...data['user'],
          'department': data['user']['department'],
          'position': data['user']['position'],
        });

        final bool isDemoUser = ['999999', '888888', '777777'].contains(_pin);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userData', json.encode(user.toJson()));
        await prefs.setBool('isDemoUser', isDemoUser);

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MainAppScreen(user: user, isDemoUser: isDemoUser),
          ),
        );
      } else {
        setState(() {
          _errorMessage =
              (data['message'] ?? 'เกิดข้อผิดพลาด (${response.statusCode})')
                  .toString();
          _pin = '';
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'การเชื่อมต่อหมดเวลา กรุณาลองใหม่';
        _pin = '';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้';
        _pin = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดระหว่างเชื่อมต่อเซิร์ฟเวอร์';
        _pin = '';
      });
      debugPrint('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color npdOrange = Theme.of(context).colorScheme.primaryContainer;
    final Color lightBackground = Theme.of(context).colorScheme.surface;
    final Color darkText = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: lightBackground,
      body: Column(
        // ✅ เปลี่ยนจาก SafeArea เป็น Column ได้เลย
        children: [
          Expanded(
            flex: 1,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/npd_180x180_padded.png',
                    width: 120,
                    height: 120,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'ระบุรหัส PIN 6 หลัก',
                    style: GoogleFonts.kanit(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: darkText,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      6,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < _pin.length
                              ? npdOrange
                              : Colors.grey.shade300,
                          border: Border.all(
                            color: Colors.grey.shade400,
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 40,
                    child: _isLoading
                        ? CircularProgressIndicator(color: primaryColor)
                        : Text(
                            _errorMessage,
                            style: GoogleFonts.kanit(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          Numpad(onKeyPressed: _onKeyPressed),
        ],
      ),
    );
  }
}

class Numpad extends StatelessWidget {
  final Function(String) onKeyPressed;
  const Numpad({super.key, required this.onKeyPressed});

  @override
  Widget build(BuildContext context) {
    final buttons = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'forgot',
      '0',
      'backspace',
    ];
    final Color darkTextColor = Theme.of(context).colorScheme.onSurface;

    return Flexible(
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.5,
        ),
        itemCount: buttons.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final value = buttons[index];
          if (value == 'forgot')
            return NumpadButton(
              child: Text(
                'ลืมรหัส',
                style: GoogleFonts.kanit(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                ),
              ),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'กรุณาติดต่อฝ่ายบุคคลเพื่อรีเซ็ตรหัสผ่าน',
                    style: GoogleFonts.kanit(),
                  ),
                ),
              ),
            );
          return NumpadButton(
            onTap: () => onKeyPressed(value),
            child: value == 'backspace'
                ? Icon(Icons.backspace_outlined, color: darkTextColor, size: 28)
                : Text(
                    value,
                    style: GoogleFonts.kanit(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: darkTextColor,
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class NumpadButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const NumpadButton({super.key, required this.child, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Center(child: child),
      );
}

class MainAppScreen extends StatefulWidget {
  final User user;
  final bool isDemoUser; // เพิ่ม isDemoUser เข้ามา
  const MainAppScreen({
    super.key,
    required this.user,
    this.isDemoUser = false,
  }); // กำหนดค่าเริ่มต้น

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  int _selectedIndex = 0;
  late List<Widget> _pages;
  bool _isApprover = false;
  bool _isConsultant = false;

  // ✅ เพิ่ม GlobalKey เพื่อเข้าถึงสถานะของ HomePage และหน้าอนุมัติ
  final GlobalKey<_HomePageState> _homePageKey = GlobalKey<_HomePageState>();
  final GlobalKey<CheckinScreenState> _checkinScreenKey =
      GlobalKey<CheckinScreenState>(); // ✅ เพิ่ม GlobalKey สำหรับ CheckinScreen
  final GlobalKey<AddTimeScreenState> _addTimeScreenKey =
      GlobalKey<AddTimeScreenState>();
  final GlobalKey<LeaveScreenState> _leaveScreenKey =
      GlobalKey<LeaveScreenState>(); // ✅ Add GlobalKey for LeaveScreen
  final GlobalKey<ApproveLeaveScreenState> _approveLeaveScreenKey =
      GlobalKey<ApproveLeaveScreenState>();
  final GlobalKey<ApproveAddTimeScreenState>
      _approveAddTimeScreenKey = // แก้ไข Type
      GlobalKey<ApproveAddTimeScreenState>(); // แก้ไข Type

  // ✅ เพิ่มตัวแปรและค่าคงที่สำหรับเวอร์ชัน
  String _currentVersion = ''; // ✅ กำหนดเวอร์ชันปัจจุบัน
  String _latestVersion = ''; // ✅ กำหนดเวอร์ชันล่าสุดจาก API/เซิร์ฟเวอร์

  // ✅ แยก URL อัปเดตสำหรับแต่ละแพลตฟอร์ม
  String _appUpdateUrlAndroid = '';
  String _appUpdateUrlIos = '';

  @override
  void initState() {
    super.initState();
    _checkConsultantStatus(); // Check consultant status first
    _initializePages(); // เรียกใช้ก่อน _loadInitialData เพื่อให้ _pages มีค่าและ key ถูกสร้าง
    _loadInitialData(); // โหลดข้อมูลเริ่มต้นและกำหนดหน้า
    _checkAppVersion(); // ✅ เรียกฟังก์ชันตรวจสอบเวอร์ชัน
  }

  void _checkConsultantStatus() {
    _isConsultant = widget.user.position == 'ที่ปรึกษา';
    debugPrint('Is Consultant: $_isConsultant');
  }

  Future<void> _loadInitialData() async {
    await _updateApproverStatus(); // โหลดสถานะ approver ก่อน
    _initializePages(); // เรียกอีกครั้งเพื่อสร้าง _pages ใหม่ถ้า _isApprover เปลี่ยน
    if (mounted) {
      setState(() {
        // อัปเดต UI หลังจาก _pages ถูกตั้งค่าแล้ว
      });
    }
    // ✅ เรียก refreshData ของ HomePage ทันทีเมื่อแอปเริ่มทำงานและ HomePage เป็นหน้าแรก
    if (_selectedIndex == 0 && _homePageKey.currentState != null) {
      _homePageKey.currentState!.refreshData();
    }
  }

  // ✅ ฟังก์ชันสำหรับแสดง Popup แจ้งเตือนเวอร์ชัน พร้อม Debug Log
  void _checkAppVersion() async {
    debugPrint('--- Version Check Started ---');

    final packageInfo = await PackageInfo.fromPlatform();
    // ดึงเวอร์ชันจาก pubspec.yaml (เช่น "1.0.0+15")
    final currentVersionRaw = packageInfo.version;
    // แยกเอาเฉพาะเวอร์ชันหลัก (Major.Minor.Patch) ออกมา
    final currentVersionClean = currentVersionRaw.split('+').first;
    _currentVersion = currentVersionClean;

    debugPrint('App version (from pubspec.yaml): $currentVersionRaw');
    debugPrint('Cleaned app version (for comparison): $_currentVersion');

    await _fetchLatestVersion();

    debugPrint('Latest version (from server): $_latestVersion');

    if (_latestVersion.isNotEmpty) {
      final shouldShowPopup = _latestVersion.compareTo(_currentVersion) > 0;
      debugPrint(
          'Comparison result: $_latestVersion > $_currentVersion = $shouldShowPopup');

      if (shouldShowPopup) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title:
                  Text('มีเวอร์ชันใหม่ให้อัปเดต', style: GoogleFonts.kanit()),
              content: Text(
                'ขณะนี้มีเวอร์ชันใหม่ ($_latestVersion) พร้อมใช้งานแล้ว กรุณาอัปเดตเพื่อประสบการณ์ที่ดีที่สุด',
                style: GoogleFonts.kanit(),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('ปิด', style: GoogleFonts.kanit()),
                ),
                ElevatedButton(
                  onPressed: () async {
                    String? updateUrl;
                    if (Platform.isAndroid) {
                      updateUrl = _appUpdateUrlAndroid;
                    } else if (Platform.isIOS) {
                      updateUrl = _appUpdateUrlIos;
                    }

                    if (updateUrl != null) {
                      final Uri url = Uri.parse(updateUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'ไม่สามารถเปิดลิงก์เพื่ออัปเดตได้',
                                style: GoogleFonts.kanit(),
                              ),
                            ),
                          );
                        }
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'ไม่รองรับแพลตฟอร์มนี้สำหรับการอัปเดต',
                              style: GoogleFonts.kanit(),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text('อัปเดตตอนนี้', style: GoogleFonts.kanit()),
                ),
              ],
            ),
          );
        });
      } else {
        debugPrint('No new version available. Pop-up will not be shown.');
      }
    } else {
      debugPrint('Latest version from server is empty. Skipping comparison.');
    }
    debugPrint('--- Version Check Finished ---');
  }

  Future<void> _fetchLatestVersion() async {
    try {
      final response = await http
          .get(Uri.parse('https://npdhrms.com/api/get_latest_version_test.php'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _latestVersion = data['version'];
            _appUpdateUrlAndroid =
                (data['android_url'] as String?)?.trim() ?? '';
            _appUpdateUrlIos = (data['ios_url'] as String?)?.trim() ?? '';
          });
        }
      } else {
        debugPrint('Failed to fetch latest version: ${response.statusCode}');
      }
    } on TimeoutException {
      debugPrint('Timeout fetching latest version.');
    } catch (e) {
      debugPrint('Error fetching latest version: $e');
    }
  }

  Future<void> _updateApproverStatus() async {
    final String apiUrl =
        'https://npdhrms.com/api/menu_data_test.php?user_id=${widget.user.id}';
    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15)); // เพิ่ม timeout
      if (!mounted) return;

      debugPrint(
        'MainAppScreen: Approver status API Response Status: ${response.statusCode}',
      );
      debugPrint(
        'MainAppScreen: Approver status API Response Body: ${response.body}',
      );

      if (response.body.isEmpty) {
        debugPrint('Error: API response body is empty for approver status.');
        return;
      }

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['status'] == 'success') {
        if (mounted) {
          setState(() {
            _isApprover = data['is_approver'] ?? false;
          });
          // ✅ เรียก _initializePages อีกครั้งเพื่อให้ _pages ถูกอัปเดต (ถ้า _isApprover เปลี่ยน)
          // การทำใน setState เดียวกันจะทำให้ rebuild แค่ครั้งเดียว
          _initializePages();
        }
      }
    } on TimeoutException catch (e) {
      debugPrint(
        'MainAppScreen: Connection Timeout fetching approver status: $e',
      );
    } on SocketException catch (e) {
      debugPrint(
        'MainAppScreen: Socket Exception fetching approver status: $e',
      );
    } on FormatException catch (e) {
      debugPrint('MainAppScreen: FormatException fetching approver status: $e');
    } catch (e) {
      debugPrint('MainAppScreen: Error fetching approver status: $e');
    }
  }

  void _initializePages() {
    List<Widget> newPages = [];

    // If the user is a consultant, only show Home and Payslip, and Approver screens if applicable
    if (_isConsultant) {
      newPages.add(
        HomePage(
          key: _homePageKey,
          user: widget.user,
          isDemoUser: widget.isDemoUser,
        ),
      );
      newPages.add(PayslipScreen(user: widget.user)); // Pass user object here
      if (_isApprover) {
        newPages.add(
          ApproveLeaveScreen(key: _approveLeaveScreenKey, user: widget.user),
        );
        newPages.add(
          ApproveAddTimeScreen(
            key: _approveAddTimeScreenKey,
            user: widget.user,
          ),
        );
      }
    } else {
      // Normal user flow
      newPages = [
        HomePage(
          key: _homePageKey,
          user: widget.user,
          isDemoUser: widget.isDemoUser,
        ), // ส่ง isDemoUser ไปยัง HomePage
        CheckinScreen(
          key: _checkinScreenKey, // ✅ เพิ่ม key
          userId: widget.user.id,
          isDemoUser: widget.isDemoUser,
          onCheckinComplete: _handleCheckinComplete,
        ), // ส่ง isDemoUser
        LeaveScreen(key: _leaveScreenKey, user: widget.user), // ✅ กำหนด key
        AddTimeScreen(key: _addTimeScreenKey, user: widget.user),
      ];
      if (_isApprover) {
        newPages.add(
          ApproveLeaveScreen(key: _approveLeaveScreenKey, user: widget.user),
        ); // กำหนด key
        newPages.add(
          ApproveAddTimeScreen(
            // แก้ไข: เรียกใช้ ApproveAddTimeScreen
            key: _approveAddTimeScreenKey,
            user: widget.user,
          ),
        ); // กำหนด key
      }
    }
    _pages = newPages;
  }

  // ✅ Callback เมื่อลงเวลาเสร็จ - เปลี่ยนไปหน้าหลักและแสดง SnackBar
  void _handleCheckinComplete(String message, bool isSuccess) {
    // เปลี่ยนไปหน้าหลัก (index 0)
    setState(() {
      _selectedIndex = 0;
    });
    
    // รีเฟรชข้อมูลหน้าหลัก
    if (_homePageKey.currentState != null) {
      _homePageKey.currentState!.refreshData();
    }
    
    // แสดง SnackBar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.kanit()),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ✅ แก้ไข _onItemTapped เพื่อให้รีเฟรชข้อมูลเมื่อสลับหน้า
  void _onItemTapped(int index) {
    if (index >= 0 && index < _pages.length) {
      // ถ้ากดซ้ำ Tab เดิม หรือสลับไป Tab ใหม่
      setState(() {
        _selectedIndex = index;
      });

      // ✅ เรียก refreshData ของหน้าที่ถูกเลือกใหม่
      _handlePageRefresh(index);
    } else {
      _selectedIndex = 0; // Fallback to home if index is invalid
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'คุณไม่มีสิทธิ์เข้าถึงหน้านี้',
              style: GoogleFonts.kanit(),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // ✅ New helper method to trigger refresh on specific page
  void _handlePageRefresh(int index) {
    // ต้องตรวจสอบประเภทของ Widget ด้วย
    if (index == 0) {
      // Home Page
      if (_homePageKey.currentState != null) {
        _homePageKey.currentState!.refreshData();
      }
    } else if (_pages[index] is CheckinScreen) {
      // ✅ Checkin Screen - รีเฟรชเมื่อเปลี่ยนมาหน้านี้
      if (_checkinScreenKey.currentState != null) {
        _checkinScreenKey.currentState!.refreshData();
      }
    } else if (_pages[index] is LeaveScreen) {
      // Leave Screen
      if (_leaveScreenKey.currentState != null) {
        _leaveScreenKey.currentState!.refreshData();
      }
    } else if (_pages[index] is AddTimeScreen) {
      // AddTime Screen
      if (_addTimeScreenKey.currentState != null) {
        _addTimeScreenKey.currentState!.refreshData();
      }
    } else if (index < _pages.length) {
      // Check to prevent index out of bounds if approver pages not added
      final currentPage = _pages[index];
      if (currentPage is ApproveLeaveScreen &&
          _approveLeaveScreenKey.currentState != null) {
        _approveLeaveScreenKey.currentState!.refreshData();
      } else if (currentPage is ApproveAddTimeScreen &&
          _approveAddTimeScreenKey.currentState != null) {
        _approveAddTimeScreenKey.currentState!.refreshData();
      }
    }
  }

  Future<void> _logout() async {
    final bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'ออกจากระบบ',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w500),
        ),
        content: Text(
          'คุณต้องการออกจากระบบใช่หรือไม่?',
          style: GoogleFonts.kanit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'ยกเลิก',
              style: GoogleFonts.kanit(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'ยืนยัน',
              style: GoogleFonts.kanit(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmLogout ?? false) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const PinLoginScreen()),
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  String _getPageTitle(int index) {
    if (_pages.isEmpty) {
      return 'กำลังโหลด...';
    }
    if (index >= 0 && index < _pages.length) {
      // Consultant specific titles
      if (_isConsultant) {
        if (_pages[index] is HomePage) {
          return 'หน้าแรก (${widget.user.firstname})';
        } else if (_pages[index] is PayslipScreen) {
          return 'สลิปเงินเดือน';
        } else if (_pages[index] is ApproveLeaveScreen) {
          return 'อนุมัติการลา';
        } else if (_pages[index] is ApproveAddTimeScreen) {
          return 'อนุมัติเพิ่มเวลา';
        }
      } else {
        // Normal user titles
        if (_pages[index] is HomePage) {
          return 'หน้าแรก (${widget.user.firstname})';
        } else if (_pages[index] is CheckinScreen) {
          return 'ลงเวลา';
        } else if (_pages[index] is LeaveScreen) {
          return 'การลา';
        } else if (_pages[index] is AddTimeScreen) {
          return 'เพิ่มเวลา';
        } else if (_pages[index] is ApproveLeaveScreen) {
          return 'อนุมัติการลา';
        } else if (_pages[index] is ApproveAddTimeScreen) {
          return 'อนุมัติเพิ่มเวลา';
        }
      }
    }
    return 'NPD HRMS';
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty || _pages[0] is SizedBox) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_getPageTitle(_selectedIndex)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
                Colors.white,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: _logout,
            tooltip: 'ออกจากระบบ',
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        isApprover: _isApprover,
        isConsultant: _isConsultant, // Pass the new consultant status
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final User user;
  final bool isDemoUser; // เพิ่ม isDemoUser เข้ามาใน HomePage
  const HomePage({
    super.key,
    required this.user,
    this.isDemoUser = false,
  }); // กำหนดค่าเริ่มต้น

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _menuData;
  String _errorMessage = '';
  late Timer _historyTimer; // Timer for real-time refresh of history

  // ✅ เพิ่มตัวแปรเพื่อติดตามว่าควรจะ refresh หรือไม่
  bool _needsRefresh = true;

  @override
  void initState() {
    super.initState();
    // initializeDateFormatting('th', null); // ควรถูกเรียกใน main() แล้ว
    _startHistoryTimer(); // เริ่มจับเวลาสำหรับ history
  }

  // ✅ สร้างเมธอด public ที่ MainAppScreen สามารถเรียกได้
  Future<void> refreshData() async {
    debugPrint('HomePage: refreshData() called.');
    // ตรวจสอบว่ากำลังโหลดอยู่หรือไม่ หรือมี error ก่อนหน้านี้หรือไม่
    // เพื่อให้โหลดข้อมูลใหม่เสมอเมื่อถูกสั่งให้ refresh
    if (mounted) {
      setState(() {
        _isLoading = true; // แสดง loading indicator ทันที
        _errorMessage = ''; // เคลียร์ error message เก่า
      });
    }
    await _fetchMenuData();
  }

  void _startHistoryTimer() {
    _historyTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      // ✅ ควรเรียกเฉพาะเมื่อหน้า HomePage ถูกแสดงอยู่
      if (mounted) {
        final mainAppScreenState =
            context.findAncestorStateOfType<_MainAppScreenState>();
        if (mainAppScreenState != null &&
            mainAppScreenState._selectedIndex == 0) {
          _fetchMenuData(); // เรียก fetch data อีกครั้ง
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ นี่คือจุดที่เหมาะสมในการโหลดข้อมูลครั้งแรกและเมื่อ Dependency เปลี่ยน
    if (_needsRefresh) {
      _needsRefresh = false; // ตั้งค่าเป็น false เพื่อไม่ให้โหลดซ้ำซ้อน
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Trigger refresh only if this screen is the currently selected one in MainAppScreen
        final mainAppScreenState =
            context.findAncestorStateOfType<_MainAppScreenState>();
        if (mainAppScreenState != null &&
            mainAppScreenState._selectedIndex == 0) {
          refreshData(); // เรียก refreshData ผ่านเมธอดที่เราสร้างขึ้น
        }
      });
    }
  }

  @override
  void dispose() {
    _historyTimer.cancel();
    super.dispose();
  }

  Future<void> _fetchMenuData() async {
    if (!mounted) return;

    // เราไม่เรียก setState ทันทีที่นี่แล้ว เพราะ refreshData() หรือ initState() ได้เรียกไปแล้ว
    // หรือถ้าเป็นการ pull-to-refresh, _isLoading จะถูกตั้งเป็น true โดย RefreshIndicator เอง

    final String apiUrl =
        'https://npdhrms.com/api/menu_data_test.php?user_id=${widget.user.id}';

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;

      debugPrint('HomePage API Response Status: ${response.statusCode}');
      debugPrint('HomePage API Response Body: ${response.body}');

      if (response.body.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'API response body is empty.';
            _isLoading = false; // Ensure loading is off
          });
        }
        debugPrint('Error: API response body is empty.');
        return;
      }

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (mounted) {
          setState(() {
            _menuData = data;
            _errorMessage = ''; // เคลียร์ error message เมื่อสำเร็จ
          });
        }
        // Update approver status in MainAppScreen state
        final mainAppScreenState =
            context.findAncestorStateOfType<_MainAppScreenState>();
        if (mainAppScreenState != null && mainAppScreenState.mounted) {
          mainAppScreenState.setState(() {
            mainAppScreenState._isApprover = data['is_approver'] ?? false;
            mainAppScreenState
                ._initializePages(); // Re-initialize pages to update bottom nav bar
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to load data';
            _isLoading = false; // Ensure loading is off
          });
        }
        debugPrint('HomePage API Error: ${data['message']}');
      }
    } on TimeoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'การเชื่อมต่อหมดเวลา กรุณาลองใหม่';
      });
      debugPrint('Connection Timeout in HomePage: $e');
    } on SocketException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้';
      });
      debugPrint('Socket Exception (No Internet) in HomePage: $e');
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์. ($e)';
      });
      debugPrint('FormatException in HomePage: $e');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล: $e');
      debugPrint('Error fetching menu data in HomePage: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ✅ ฟังก์ชันเปิดหน้าประวัติลงเวลาทั้งหมด (แบบหน้าใหม่)
  void _showFullCheckinHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullCheckinHistoryScreen(
          user: widget.user,
          initialMonth: DateTime.now().month,
          initialYear: DateTime.now().year,
        ),
      ),
    );
  }

  // Helper function to format date string to "วัน เดือน ปี" (e.g., "24 กรกฎาคม 2025")
  String _formatDateForHistory(String dateString) {
    try {
      if (dateString.isEmpty || dateString == 'N/A') {
        return 'N/A';
      }
      final DateTime date = DateTime.parse(dateString);
      // Use 'd MMMM yyyy' for full month name and year (Thai localization is active)
      final DateFormat formatter = DateFormat('d MMMM yyyy', 'th');
      return formatter.format(date);
    } catch (e) {
      debugPrint('Error formatting date: $e'); // Log parsing errors
      return dateString; // Fallback to original string if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine if the user is a consultant
    final bool isConsultant = widget.user.position == 'ที่ปรึกษา';

    // Show loading indicator if initial data is still being fetched and not yet available
    return _isLoading && _menuData == null
        ? Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          )
        : _errorMessage.isNotEmpty // Show error message if fetch failed
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _errorMessage,
                      style: GoogleFonts.kanit(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _fetchMenuData, // Retry button
                      icon: const Icon(Icons.refresh),
                      label: Text('ลองอีกครั้ง', style: GoogleFonts.kanit()),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                // Allow manual pull-to-refresh
                onRefresh: _fetchMenuData,
                color: Theme.of(context).colorScheme.primary,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary.withOpacity(0.05),
                        Theme.of(context).colorScheme.surface,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      const RealTimeClock(), // Display real-time clock
                      const SizedBox(height: 24),
                      // Conditional rendering of the menu grid
                      if (!isConsultant)
                        _buildMenuGrid(
                          context,
                        ), // Main menu grid for non-consultants
                      if (isConsultant)
                        _buildConsultantMenuGrid(
                          context,
                        ), // Special menu for consultants
                      const SizedBox(height: 24),
                      // Approver section only if user is an approver AND (not a consultant OR consultant but also approver)
                      if (_menuData?['is_approver'] ?? false)
                        _buildApproverSection(), // Approver specific section
                      const SizedBox(height: 24),
                      // Conditionally hide history for consultants
                      if (!isConsultant)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ประวัติการลงเวลา (3 วันล่าสุด)',
                              style: GoogleFonts.kanit(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            InkWell(
                              onTap: _showFullCheckinHistory,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'แสดงทั้งหมด',
                                      style: GoogleFonts.kanit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (!isConsultant) const SizedBox(height: 8),
                      if (!isConsultant)
                        _buildHistoryList(), // Display check-in history list
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
  }

  // Helper widget to build the main menu grid with new card items
  Widget _buildMenuGrid(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _MenuCardItem(
                icon: Icons.check_circle_outline,
                label: 'ลงเวลา',
                onTap: () {
                  final mainAppScreenState =
                      context.findAncestorStateOfType<_MainAppScreenState>();
                  if (mainAppScreenState != null) {
                    mainAppScreenState.setState(() {
                      mainAppScreenState._onItemTapped(1);
                    });
                  } else {
                    // Fallback for direct navigation if not in MainAppScreen context
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CheckinScreen(
                          userId: widget.user.id,
                          isDemoUser: widget.isDemoUser,
                        ), // ส่ง isDemoUser
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 16), // Add spacing between cards
            Expanded(
              child: _MenuCardItem(
                icon: Icons.calendar_today_outlined,
                label: 'การลา',
                onTap: () {
                  final mainAppScreenState =
                      context.findAncestorStateOfType<_MainAppScreenState>();
                  if (mainAppScreenState != null) {
                    mainAppScreenState.setState(() {
                      mainAppScreenState._onItemTapped(2);
                    });
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LeaveScreen(user: widget.user),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16), // Spacing between rows of cards
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _MenuCardItem(
                icon: Icons.history_toggle_off_outlined,
                label: 'เพิ่มเวลา',
                onTap: () {
                  final mainAppScreenState =
                      context.findAncestorStateOfType<_MainAppScreenState>();
                  if (mainAppScreenState != null) {
                    mainAppScreenState.setState(() {
                      mainAppScreenState._onItemTapped(3);
                    });
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddTimeScreen(user: widget.user),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 16), // Add spacing between cards
            Expanded(
              child: _MenuCardItem(
                icon: Icons.receipt_long_outlined,
                label: 'สลิปเงินเดือน',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PayslipScreen(user: widget.user),
                    ), // Pass user object here
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // New helper widget for consultant's specific menu grid
  Widget _buildConsultantMenuGrid(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _MenuCardItem(
                icon: Icons.receipt_long_outlined,
                label: 'สลิปเงินเดือน',
                onTap: () {
                  final mainAppScreenState =
                      context.findAncestorStateOfType<_MainAppScreenState>();
                  if (mainAppScreenState != null) {
                    // Find the index of PayslipScreen for consultants
                    int payslipIndex = mainAppScreenState._pages.indexWhere(
                      (page) => page is PayslipScreen,
                    );
                    if (payslipIndex != -1) {
                      mainAppScreenState.setState(() {
                        mainAppScreenState._onItemTapped(payslipIndex);
                      });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              PayslipScreen(user: widget.user),
                        ), // Pass user object here
                      );
                    }
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PayslipScreen(user: widget.user),
                      ), // Pass user object here
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Helper widget to build the approver section
  Widget _buildApproverSection() {
    final leaveCount = _menuData?['pending_leave_count'] ?? 0;
    final addTimeCount = _menuData?['pending_addtime_count'] ?? 0;

    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color npdOrange = Theme.of(context).colorScheme.primaryContainer;
    final Color onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'สำหรับผู้อนุมัติ',
          style: GoogleFonts.kanit(fontSize: 17, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ApprovalCard(
                label: 'อนุมัติการลา',
                count: leaveCount,
                icon: Icons.playlist_add_check_circle_outlined,
                onTap: () {
                  final mainAppScreenState =
                      context.findAncestorStateOfType<_MainAppScreenState>();
                  if (mainAppScreenState != null) {
                    // Dynamically find index for ApproveLeaveScreen
                    int approveLeaveIndex = mainAppScreenState._pages
                        .indexWhere((page) => page is ApproveLeaveScreen);
                    if (approveLeaveIndex != -1) {
                      mainAppScreenState.setState(() {
                        mainAppScreenState._onItemTapped(approveLeaveIndex);
                      });
                    }
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ApproveLeaveScreen(user: widget.user),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ApprovalCard(
                label: 'อนุมัติเพิ่มเวลา',
                count: addTimeCount,
                icon: Icons.person_add_alt_1_outlined,
                onTap: () {
                  final mainAppScreenState =
                      context.findAncestorStateOfType<_MainAppScreenState>();
                  if (mainAppScreenState != null) {
                    // Dynamically find index for ApproveAddTimeScreen
                    int approveAddTimeIndex = mainAppScreenState._pages
                        .indexWhere((page) => page is ApproveAddTimeScreen);
                    if (approveAddTimeIndex != -1) {
                      mainAppScreenState.setState(() {
                        mainAppScreenState._onItemTapped(approveAddTimeIndex);
                      });
                    }
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ApproveAddTimeScreen(user: widget.user),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // Helper widget to build the check-in history list
  Widget _buildHistoryList() {
    final List history = _menuData?['checkin_history'] ?? [];
    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Center(
          child: Text(
            'ไม่มีข้อมูลการลงเวลา',
            style: GoogleFonts.kanit(fontSize: 15, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    // Group history items by date for display
    Map<String, List<Map<String, dynamic>>> groupedHistory = {};
    for (var item in history) {
      final String workDate = item['work_date'] ?? 'Unknown Date';
      if (!groupedHistory.containsKey(workDate)) {
        groupedHistory[workDate] = [];
      }
      groupedHistory[workDate]!.add(item);
    }

    // Sort dates in descending order to show newest days first
    List<String> sortedDates = groupedHistory.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedDates.length,
      itemBuilder: (context, dateIndex) {
        final String currentDate = sortedDates[dateIndex];
        final List<Map<String, dynamic>> entriesForDate =
            groupedHistory[currentDate]!;

        // Sort entries for the current date by full_datetime to ensure correct pairing
        entriesForDate.sort(
          (a, b) =>
              (a['full_datetime'] ?? '').compareTo(b['full_datetime'] ?? ''),
        );

        // Logic to pair up 'in' and 'out' entries
        List<Map<String, dynamic>> pairedEntries = [];
        List<Map<String, dynamic>> unmatchedEntries = [];

        // Simple pairing: Find an 'in', then the next 'out'
        Map<String, dynamic>? currentIn;
        for (var entry in entriesForDate) {
          if (entry['check_type'] == 'in') {
            if (currentIn != null) {
              // Found another 'in' before an 'out' for the previous 'in'
              pairedEntries.add({'in': currentIn, 'out': null});
            }
            currentIn = entry;
          } else if (entry['check_type'] == 'out') {
            if (currentIn != null) {
              // Found an 'out' after an 'in'
              pairedEntries.add({'in': currentIn, 'out': entry});
              currentIn = null; // Reset for next pair
            } else {
              // Standalone 'out' without preceding 'in'
              unmatchedEntries.add(entry);
            }
          }
        }
        // Add any remaining 'in' entry that didn't get an 'out'
        if (currentIn != null) {
          pairedEntries.add({'in': currentIn, 'out': null});
        }
        // Add any standalone 'out' entries (e.g., if clock-in was missed or on previous day)
        // These will be displayed as an 'out' without a corresponding 'in' bubble
        for (var unmatched in unmatchedEntries) {
          pairedEntries.add({'in': null, 'out': unmatched});
        }

        // Re-sort paired entries by the earliest time in the pair for consistent display
        pairedEntries.sort((a, b) {
          String? timeA =
              a['in']?['full_datetime'] ?? a['out']?['full_datetime'];
          String? timeB =
              b['in']?['full_datetime'] ?? b['out']?['full_datetime'];
          if (timeA == null || timeB == null)
            return 0; // Handle nulls if necessary
          return timeA.compareTo(timeB);
        });

        return Card(
          elevation: 2,
          color: Theme.of(context).colorScheme.surface,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display the date (e.g., "24 กรกฎาคม 2025")
                Text(
                  _formatDateForHistory(currentDate),
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Divider(height: 16, thickness: 1), // Separator for date
                // Display each paired check-in/out entry for this date
                ...pairedEntries.map((pair) {
                  final String? inTime = pair['in']?['work_time'];
                  final String? outTime = pair['out']?['work_time'];

                  return _CheckInOutPairCard(inTime: inTime, outTime: outTime);
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ✅ New widget for rectangular menu items
class _MenuCardItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuCardItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color npdOrange = Theme.of(context).colorScheme.primaryContainer;
    final Color onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15), // Rounded corners for the card
      child: Card(
        elevation: 4, // Add elevation for a card-like appearance
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: npdOrange), // Slightly smaller icon
              const SizedBox(height: 12), // More spacing
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontSize: 16, // Larger font size
                  fontWeight: FontWeight.w500,
                  color: onSurfaceColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget for approval cards
class _ApprovalCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final VoidCallback onTap;

  const _ApprovalCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color npdOrange = Theme.of(context).colorScheme.primaryContainer;
    final Color onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 36, color: npdOrange),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      count.toString(),
                      style: GoogleFonts.kanit(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: GoogleFonts.kanit(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: onSurfaceColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RealTimeClock extends StatefulWidget {
  const RealTimeClock({super.key});

  @override
  State<RealTimeClock> createState() => _RealTimeClockState();
}

class _RealTimeClockState extends State<RealTimeClock> {
  late Timer _timer;
  String _formattedDateTime = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    final formatter = DateFormat("EEEEที่ d MMMM yyyy, HH:mm:ss", "th");
    setState(() {
      _formattedDateTime = formatter.format(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color onSurfaceColor = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.access_time_filled_rounded, color: primaryColor, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _formattedDateTime,
              style: GoogleFonts.kanit(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: onSurfaceColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color onBackground = Theme.of(context).colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 90,
            color: primaryColor.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          Text(
            'หน้า $title',
            style: GoogleFonts.kanit(
              fontSize: 22,
              color: onBackground,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'กำลังอยู่ในระหว่างการพัฒนา',
            style: GoogleFonts.kanit(fontSize: 15, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _CheckInOutPairCard extends StatelessWidget {
  final String? inTime;
  final String? outTime;

  const _CheckInOutPairCard({
    Key? key,
    required this.inTime,
    required this.outTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color cardColor;
    if (inTime != null && outTime != null) {
      cardColor = Colors.blue.shade50.withOpacity(
        0.5,
      );
    } else if (inTime != null) {
      cardColor = Colors.green.shade50.withOpacity(0.5);
    } else if (outTime != null) {
      cardColor = Colors.red.shade50.withOpacity(0.5);
    } else {
      cardColor = Colors.grey.shade50.withOpacity(0.5);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: _TimeEntryBubble(
              label: 'เข้า',
              time: inTime ?? '-',
              isCheckIn: true,
              showIcon: inTime != null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TimeEntryBubble(
              label: 'ออก',
              time: outTime ?? '-',
              isCheckIn: false,
              showIcon: outTime != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeEntryBubble extends StatelessWidget {
  final String label;
  final String time;
  final bool isCheckIn;
  final bool showIcon;

  const _TimeEntryBubble({
    Key? key,
    required this.label,
    required this.time,
    required this.isCheckIn,
    this.showIcon = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color textColor =
        isCheckIn ? Colors.green.shade800 : Colors.red.shade800;
    final IconData icon = isCheckIn ? Icons.login : Icons.logout;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) Icon(icon, size: 17, color: textColor),
        if (showIcon) const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$label: $time น.',
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ✅ หน้าแสดงประวัติลงเวลาทั้งหมด (Full Screen)
class FullCheckinHistoryScreen extends StatefulWidget {
  final User user;
  final int initialMonth;
  final int initialYear;

  const FullCheckinHistoryScreen({
    Key? key,
    required this.user,
    required this.initialMonth,
    required this.initialYear,
  }) : super(key: key);

  @override
  State<FullCheckinHistoryScreen> createState() => _FullCheckinHistoryScreenState();
}

class _FullCheckinHistoryScreenState extends State<FullCheckinHistoryScreen> {
  late int _selectedMonth;
  late int _selectedYear;
  bool _isLoading = true;
  List<dynamic> _checkinHistory = [];
  String _errorMessage = '';

  final List<String> _thaiMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
  ];

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth;
    _selectedYear = widget.initialYear;
    _fetchCheckinHistory();
  }

  Future<void> _fetchCheckinHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final String apiUrl =
        'https://npdhrms.com/api/get_checkin_history.php?user_id=${widget.user.id}&month=$_selectedMonth&year=$_selectedYear';

    try {
      final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _checkinHistory = data['checkin_history'] ?? [];
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'ไม่สามารถดึงข้อมูลได้';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'เกิดข้อผิดพลาด: ${response.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final DateTime date = DateTime.parse(dateString);
      final DateFormat formatter = DateFormat('d MMMM yyyy', 'th');
      return formatter.format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ประวัติการลงเวลาทั้งหมด', style: GoogleFonts.kanit()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchCheckinHistory,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: Column(
        children: [
          // Month/Year Selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Month Dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedMonth,
                        isExpanded: true,
                        style: GoogleFonts.kanit(fontSize: 14, color: Colors.black),
                        items: List.generate(12, (index) {
                          return DropdownMenuItem(
                            value: index + 1,
                            child: Text(_thaiMonths[index]),
                          );
                        }),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedMonth = value);
                            _fetchCheckinHistory();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Year Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedYear,
                      style: GoogleFonts.kanit(fontSize: 14, color: Colors.black),
                      items: List.generate(5, (index) {
                        int year = DateTime.now().year - 2 + index;
                        return DropdownMenuItem(
                          value: year,
                          child: Text('${year + 543}'), // แสดงเป็น พ.ศ.
                        );
                      }),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedYear = value);
                          _fetchCheckinHistory();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'พบ ${_checkinHistory.length} รายการ',
                  style: GoogleFonts.kanit(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // History List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_errorMessage, style: GoogleFonts.kanit(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _fetchCheckinHistory,
                              icon: const Icon(Icons.refresh),
                              label: Text('ลองอีกครั้ง', style: GoogleFonts.kanit()),
                            ),
                          ],
                        ),
                      )
                    : _checkinHistory.isEmpty
                        ? Center(
                            child: Text(
                              'ไม่มีข้อมูลการลงเวลาในเดือนนี้',
                              style: GoogleFonts.kanit(fontSize: 16, color: Colors.grey),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchCheckinHistory,
                            child: _buildGroupedHistoryList(),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedHistoryList() {
    // Group by date
    Map<String, List<dynamic>> grouped = {};
    for (var item in _checkinHistory) {
      String date = item['work_date'] ?? '';
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(item);
    }

    List<String> sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        String date = sortedDates[index];
        List<dynamic> entries = grouped[date]!;
        
        // Sort entries by time
        entries.sort((a, b) => (a['full_datetime'] ?? '').compareTo(b['full_datetime'] ?? ''));

        // จับคู่ in/out เหมือนหน้าหลัก
        List<Map<String, dynamic>> pairedEntries = [];
        Map<String, dynamic>? currentIn;
        
        for (var entry in entries) {
          if (entry['check_type'] == 'in') {
            if (currentIn != null) {
              pairedEntries.add({'in': currentIn, 'out': null});
            }
            currentIn = entry;
          } else if (entry['check_type'] == 'out') {
            if (currentIn != null) {
              pairedEntries.add({'in': currentIn, 'out': entry});
              currentIn = null;
            } else {
              pairedEntries.add({'in': null, 'out': entry});
            }
          }
        }
        if (currentIn != null) {
          pairedEntries.add({'in': currentIn, 'out': null});
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Header
                Text(
                  _formatDate(date),
                  style: GoogleFonts.kanit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Divider(),
                // แสดงคู่ เข้า-ออก แบบเดียวกับหน้าหลัก
                ...pairedEntries.map((pair) {
                  String? inTime = pair['in']?['work_time'];
                  String? outTime = pair['out']?['work_time'];
                  return _CheckInOutPairCard(inTime: inTime, outTime: outTime);
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }
}
