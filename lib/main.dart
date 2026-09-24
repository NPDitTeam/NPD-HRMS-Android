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
import 'package:image_picker/image_picker.dart';

// Import Your Screens
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'odoo_rpc_service.dart';
import 'checkin_screen.dart';
import 'notification_service.dart';
import 'app_bottom_nav_bar.dart';
import 'approvals_hub_screen.dart';
import 'profile_photo_service.dart';
import 'ui/app_theme.dart';
import 'add_time_screen.dart';
import 'leave_screen.dart';
import 'payslip_screen.dart';
import 'approve_leave_screen.dart';
import 'approve_add_time_screen.dart';
import 'employee_warning_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 🔔 เริ่มต้น Notification Service
  await NotificationService().init();
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

/// ล้าง SharedPreferences แบบปลอดภัย
/// เก็บ keys ที่เกี่ยวกับ "อ่านแล้ว"/สถานะคำขอ ไว้ เพื่อไม่ให้แจ้งเตือนซ้ำหลัง logout/login
/// ✅ เก็บ theme_color_<userId> ด้วย เพื่อให้สีธีมที่ user ตั้งไว้คงอยู่หลัง logout/login
Future<void> _safeClearPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final Map<String, Object> keepKeys = {};
  for (final key in prefs.getKeys()) {
    if (key.startsWith('warning_read_count_') ||
        key.startsWith('warning_notified_count_') ||
        key.startsWith('approver_seen_leave_') ||
        key.startsWith('approver_seen_addtime_') ||
        key.startsWith('req_leave_state_') ||
        key.startsWith('req_addtime_state_') ||
        key.startsWith('theme_color_')) {
      final v = prefs.get(key);
      if (v != null) keepKeys[key] = v;
    }
  }
  await prefs.clear();
  for (final entry in keepKeys.entries) {
    final k = entry.key;
    final v = entry.value;
    if (v is int) {
      await prefs.setInt(k, v);
    } else if (v is String) {
      await prefs.setString(k, v);
    } else if (v is bool) {
      await prefs.setBool(k, v);
    } else if (v is double) {
      await prefs.setDouble(k, v);
    }
  }
}

// ✅ Theme Controller — จัดการสีธีมต่อ user
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  // ✅ สีเริ่มต้น = เหลือง NPD
  static const Color defaultColor = Color(0xFFFFE144);

  /// สีเหลืองเดิมก่อนเปลี่ยนเป็น #FFE144 — เครื่องที่เคยใช้ค่าเริ่มต้นเดิมจะถูก
  /// ย้ายมาใช้สีใหม่ให้เอง (ค่าที่บันทึกไว้เท่ากับสีเริ่มต้นเดิม = ยังไม่เคยเลือกสีเอง)
  static const Color legacyDefaultColor = Color(0xFFFFD600);

  Color _primaryColor = defaultColor;
  Color get primaryColor => _primaryColor;

  bool get isDefault => _primaryColor.value == defaultColor.value;

  /// โหลดสีที่ user คนนี้บันทึกไว้
  Future<void> loadForUser(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('theme_color_$userId');
    Color newColor = saved != null ? Color(saved) : defaultColor;
    if (newColor.value == legacyDefaultColor.value) newColor = defaultColor;
    // ป้องกัน notify ซ้ำเมื่อค่าไม่เปลี่ยน (กัน infinite rebuild)
    if (newColor.value == _primaryColor.value) return;
    _primaryColor = newColor;
    notifyListeners();
  }

  /// ตั้งสีใหม่ + บันทึก
  Future<void> setColor(int userId, Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color_$userId', color.value);
    if (color.value == _primaryColor.value) return; // ไม่เปลี่ยน → ไม่ notify
    _primaryColor = color;
    notifyListeners();
  }

  /// รีเซ็ตกลับสีเดิม
  Future<void> reset(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('theme_color_$userId');
    if (_primaryColor.value == defaultColor.value) return;
    _primaryColor = defaultColor;
    notifyListeners();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ✅ Cache Future ไว้ใน state — สร้างครั้งเดียวตอน initState
  // ป้องกัน FutureBuilder รัน Future ใหม่ทุกครั้งที่ MaterialApp rebuild
  late final Future<Widget> _initialScreenFuture;

  @override
  void initState() {
    super.initState();
    _initialScreenFuture = _getInitialScreen();
    // โหลดสีที่บันทึกไว้ (ถ้ามี user login อยู่)
    _loadSavedThemeIfLoggedIn();
    ThemeController.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedThemeIfLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('userData');
      if (userDataString != null) {
        final user = User.fromJson(json.decode(userDataString));
        await ThemeController.instance.loadForUser(user.id);
      }
    } catch (_) {}
  }

  Future<Widget> _getInitialScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');
    if (userDataString != null) {
      // ✅ เช็คว่าต้อง force logout ไหม (ค่า config เปลี่ยน)
      final forceLogout = prefs.getBool('forceLogout') ?? false;
      if (forceLogout) {
        await _safeClearPrefs();
        return const PinLoginScreen();
      }
      return MainAppScreen(
        user: User.fromJson(json.decode(userDataString)),
      );
    }
    return const PinLoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ สีหลักของแอป (อ่านจาก ThemeController — เปลี่ยนได้รายผู้ใช้)
    final Color npdYellow = ThemeController.instance.primaryColor;

    return MaterialApp(
      // ✅ ล็อกขนาด Text ไม่ให้เปลี่ยนตามการตั้งค่าของมือถือ
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child!,
        );
      },
      title: 'NPD HRMS',
      // กฎสีทั้งหมดอยู่ใน AppTheme (ชุดเดียวกับแอป Odoo 18) ที่นี่แค่ส่งสีองค์กรเข้าไป
      theme: AppTheme.light(npdYellow),
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
        future: _initialScreenFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return snapshot.data ?? const PinLoginScreen();
          }
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: npdYellow)),
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

        final bool isDemoUser = false; // ยึดจาก allow_offsite_time ใน Odoo แทน

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userData', json.encode(user.toJson()));

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MainAppScreen(user: user),
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

  /// โลโก้ที่ติดมากับแอป — ใช้เมื่อองค์กรยังไม่ได้ตั้งโลโก้ หรือโหลดโลโก้ไม่ได้
  Widget get _bundledLogo =>
      Image.asset('assets/npd_180x180_padded.png', fit: BoxFit.contain);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // จุด PIN ใช้ ink ไม่ใช่สีองค์กรตรง ๆ — เหลือง NPD บนพื้นขาวมองแทบไม่เห็น
    final Color ink = AppColors.ink(scheme.primary);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.tint(scheme.primary, 0.16),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: _bundledLogo,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'NPD HRMS',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansThai(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'กรอกรหัส PIN 6 หลักเพื่อเข้าสู่ระบบ',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansThai(
                            fontSize: 14.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            final bool filled = index < _pin.length;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOut,
                              margin: const EdgeInsets.symmetric(horizontal: 7),
                              width: filled ? 16 : 14,
                              height: filled ? 16 : 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: filled ? ink : Colors.transparent,
                                border: Border.all(
                                  color: filled ? ink : const Color(0xFFCBD0D6),
                                  width: 1.6,
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 18),
                        _isLoading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: ink,
                                  strokeWidth: 2.5,
                                ),
                              )
                            // ข้อความผิดพลาดอาจยาวหลายบรรทัด (เช่นสัญญาองค์กรหมดอายุ)
                            // จึงกำหนดแค่ความสูงขั้นต่ำ ไม่ล็อกความสูงตายตัว
                            : ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 24),
                                child: Text(
                                  _errorMessage,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.ibmPlexSansThai(
                                    color: AppColors.danger,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
              Numpad(onKeyPressed: _onKeyPressed),
              const SizedBox(height: 4),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class Numpad extends StatelessWidget {
  final Function(String) onKeyPressed;
  const Numpad({super.key, required this.onKeyPressed});

  static const List<List<String>> _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['forgot', '0', 'backspace'],
  ];

  @override
  Widget build(BuildContext context) {
    // มือถือจอเตี้ยย่อปุ่มลง ไม่งั้นส่วนโลโก้ด้านบนต้องเลื่อนดู
    final double keySize = MediaQuery.sizeOf(context).height < 700 ? 60 : 70;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final value in row) _buildKey(context, value, keySize),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKey(BuildContext context, String value, double size) {
    if (value == 'forgot') {
      return NumpadButton(
        size: size,
        isSpecial: true,
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'กรุณาติดต่อฝ่ายบุคคลเพื่อรีเซ็ตรหัสผ่าน',
              style: GoogleFonts.ibmPlexSansThai(),
            ),
          ),
        ),
        child: Text(
          'ลืมรหัส',
          style: GoogleFonts.ibmPlexSansThai(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
      );
    }
    if (value == 'backspace') {
      return NumpadButton(
        size: size,
        isSpecial: true,
        onTap: () => onKeyPressed(value),
        child: const Icon(
          Icons.backspace_outlined,
          color: AppColors.text,
          size: 24,
        ),
      );
    }
    return NumpadButton(
      size: size,
      onTap: () => onKeyPressed(value),
      child: Text(
        value,
        style: GoogleFonts.ibmPlexSansThai(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
    );
  }
}

class NumpadButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isSpecial;
  final double size;
  const NumpadButton({
    super.key,
    required this.child,
    required this.onTap,
    this.isSpecial = false,
    this.size = 70,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // ปุ่มตัวเลขเป็นวงกลมพื้นเทาอ่อน ปุ่มพิเศษ (ลืมรหัส/ลบ) โปร่งใสให้ดูเป็นปุ่มรอง
      color: isSpecial ? Colors.transparent : const Color(0xFFF2F4F7),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
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
  final GlobalKey<ApprovalsHubScreenState> _approvalsHubKey =
      GlobalKey<ApprovalsHubScreenState>();

  // ✅ เพิ่มตัวแปรและค่าคงที่สำหรับเวอร์ชัน
  String _currentVersion = ''; // ✅ กำหนดเวอร์ชันปัจจุบัน
  String _latestVersion = ''; // ✅ กำหนดเวอร์ชันล่าสุดจาก API/เซิร์ฟเวอร์

  // ✅ รายการสิ่งที่ปรับปรุงของ "เวอร์ชันใหม่" — ต้องมาจากเซิร์ฟเวอร์เท่านั้น
  // ถ้า hardcode ไว้ในแอป ข้อความจะช้าไป 1 เวอร์ชันเสมอ เพราะแอปที่ผู้ใช้ติดตั้งอยู่
  // คือเวอร์ชันเก่า จึงมีแต่ข้อความของเวอร์ชันเก่าติดมาด้วย
  List<String> _latestReleaseNotes = [];

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
    _setupWorkNotifications(); // 🔔 ตั้งแจ้งเตือนเข้า-ออกงาน
    _checkConfigChanged(); // 🔄 เช็คว่า config เปลี่ยนไหม ถ้าเปลี่ยน force logout
    // 🎨 โหลดสีธีมที่ user เคยตั้งไว้
    ThemeController.instance.loadForUser(widget.user.id);
  }

  // เช็คว่าข้อมูลพนักงานเปลี่ยนไหม + status ต้องเป็น active
  Future<void> _checkConfigChanged() async {
    try {
      final url = 'https://npdhrms.com/api/api_checkin_status1.php?user_id=${widget.user.id}';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final apiData = data['data'];
          final prefs = await SharedPreferences.getInstance();

          // เช็ค employee status - ถ้า inactive บังคับ logout ทันที
          final employeeStatus = apiData['employeeStatus']?.toString() ?? 'active';
          if (employeeStatus == 'inactive') {
            debugPrint('พนักงานถูกปิดการใช้งาน (inactive) - บังคับ logout');
            await _safeClearPrefs();
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: Text('บัญชีถูกระงับ', style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.w600)),
                  content: Text(
                    'บัญชีของคุณถูกปิดการใช้งาน กรุณาติดต่อฝ่ายบุคคล',
                    style: GoogleFonts.ibmPlexSansThai(),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                          (route) => false,
                        );
                      },
                      child: Text('ตกลง', style: GoogleFonts.ibmPlexSansThai()),
                    ),
                  ],
                ),
              );
              return;
            }
          }

          // เก็บ config hash จาก API (รวม status)
          final newConfigHash = '${apiData['allowOffsiteTime']}_${apiData['firstName']}_${apiData['lastName']}_$employeeStatus';
          final savedConfigHash = prefs.getString('configHash') ?? '';

          if (savedConfigHash.isNotEmpty && savedConfigHash != newConfigHash) {
            // Config เปลี่ยน → บังคับ login ใหม่
            debugPrint('Config เปลี่ยน! ($savedConfigHash -> $newConfigHash) บังคับ login ใหม่');
            await _safeClearPrefs();
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                (route) => false,
              );
              return;
            }
          }

          // บันทึก config hash ล่าสุด
          await prefs.setString('configHash', newConfigHash);
        }
      }
    } catch (e) {
      debugPrint('ไม่สามารถเช็ค config ได้: $e');
    }
  }

  // 🔔 ตั้งแจ้งเตือนเข้า-ออกงาน จากตาราง Odoo
  Future<void> _setupWorkNotifications() async {
    try {
      final employeeCode = widget.user.employeeCode ?? '';
      final employeeName = '${widget.user.firstname} ${widget.user.lastname}';
      const odooBaseUrl = 'https://npderp.com';

      await NotificationService().scheduleWorkNotifications(
        employeeCode: employeeCode,
        employeeName: employeeName,
        odooBaseUrl: odooBaseUrl,
      );
      debugPrint('🔔 ตั้งแจ้งเตือนเข้า-ออกงาน สำหรับ $employeeName');
    } catch (e) {
      debugPrint('❌ Error setting up notifications: $e');
    }
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
        // แจ้งเตือนที่หน้ามือถือ (notification bar) ด้วย
        NotificationService().showUpdateNotification(_latestVersion);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              // รายการสิ่งที่ปรับปรุงอาจยาวหลายบรรทัด — ให้เลื่อนดูได้ ไม่ล้นจอเครื่องเล็ก
              scrollable: true,
              title: Text('มีเวอร์ชันใหม่ v$_latestVersion',
                  style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ข้อความมาจากเซิร์ฟเวอร์ จึงตรงกับเวอร์ชันใหม่เสมอ
                  if (_latestReleaseNotes.isNotEmpty) ...[
                    Text('สิ่งที่ปรับปรุงในเวอร์ชัน $_latestVersion',
                        style: GoogleFonts.ibmPlexSansThai(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    ..._latestReleaseNotes.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('- $note',
                            style:
                                GoogleFonts.ibmPlexSansThai(fontSize: 14)),
                      ),
                    ),
                  ] else
                    // เซิร์ฟเวอร์ยังไม่ได้ส่งรายละเอียดมา — ห้ามแสดงรายการของเวอร์ชันเก่า
                    Text('มีการปรับปรุงการใช้งานและแก้ไขข้อผิดพลาด',
                        style: GoogleFonts.ibmPlexSansThai(fontSize: 14)),
                  const SizedBox(height: 12),
                  Text(
                    'กรุณาอัปเดตเพื่อใช้งานเวอร์ชันล่าสุด',
                    style: GoogleFonts.ibmPlexSansThai(
                        color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('ปิด', style: GoogleFonts.ibmPlexSansThai()),
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
                                style: GoogleFonts.ibmPlexSansThai(),
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
                              style: GoogleFonts.ibmPlexSansThai(),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text('อัปเดตตอนนี้', style: GoogleFonts.ibmPlexSansThai()),
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

  /// รองรับทั้งกรณีเซิร์ฟเวอร์ส่งมาเป็น array และเป็นข้อความยาวคั่นด้วยขึ้นบรรทัดใหม่
  /// ตัด "-" หรือ "•" นำหน้าออก เพราะหน้าจอใส่ "- " ให้เองอยู่แล้ว
  List<String> _parseReleaseNotes(dynamic raw) {
    List<String> lines;
    if (raw is List) {
      lines = raw.map((e) => e.toString()).toList();
    } else if (raw is String) {
      lines = raw.split(RegExp(r'[\r\n]+'));
    } else {
      return [];
    }

    return lines
        .map((e) => e.trim().replaceFirst(RegExp(r'^[-•*]\s*'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
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
            _latestReleaseNotes = _parseReleaseNotes(data['release_notes']);
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
          employeeCode: widget.user.employeeCode,
          isDemoUser: widget.isDemoUser,
          onCheckinComplete: _handleCheckinComplete,
        ), // ส่ง isDemoUser
        LeaveScreen(key: _leaveScreenKey, user: widget.user), // ✅ กำหนด key
        AddTimeScreen(key: _addTimeScreenKey, user: widget.user),
      ];
    }

    // ผู้อนุมัติได้ปุ่ม "อนุมัติ" ปุ่มเดียว (ลา/เพิ่มเวลาแยกเป็นแท็บข้างใน)
    // ต้องเป็นหน้าสุดท้ายเสมอ ให้ตรงกับลำดับปุ่มใน AppBottomNavBar
    if (_isApprover) {
      newPages.add(
        ApprovalsHubScreen(
          key: _approvalsHubKey,
          onTabTapped: _refreshApprovalTab,
          leaveScreen: ApproveLeaveScreen(
            key: _approveLeaveScreenKey,
            user: widget.user,
            embedded: true,
          ),
          addTimeScreen: ApproveAddTimeScreen(
            key: _approveAddTimeScreenKey,
            user: widget.user,
            embedded: true,
          ),
        ),
      );
    }
    _pages = newPages;
  }

  /// รีเฟรชแท็บในหน้าอนุมัติ (0 = การลา, 1 = เพิ่มเวลา)
  void _refreshApprovalTab(int tab) {
    if (tab == 0) {
      _approveLeaveScreenKey.currentState?.refreshData();
    } else {
      _approveAddTimeScreenKey.currentState?.refreshData();
    }
  }

  /// เปิดหน้าอนุมัติตรงแท็บที่ต้องการ — ใช้จากการ์ดบนหน้าแรก
  void _openApprovals(int tab) {
    final index = _pages.indexWhere((page) => page is ApprovalsHubScreen);
    if (index == -1) return;
    _approvalsHubKey.currentState?.showTab(tab);
    _onItemTapped(index);
  }

  // ✅ Callback เมื่อลงเวลาเสร็จ - เปลี่ยนไปหน้าหลักและแสดง SnackBar
  /// เช็คว่าวันนี้เข้างานสายไหม แล้วแจ้งเตือน (ชุดเดียวกับแจ้งเตือนเข้า-ออกงาน)
  ///
  /// อิงสูตรใน Odoo ล้วน ๆ ไม่ได้คำนวณในแอป — เปลี่ยนสูตรเมื่อไหร่ก็ตามทันที
  /// เตือนวันละครั้งพอ (จำไว้ใน SharedPreferences) กันเตือนซ้ำตอนสแกนออก
  /// หรือตอนสแกนเข้ารอบสอง
  Future<void> _notifyIfLateToday() async {
    try {
      final code = widget.user.employeeCode ?? '';
      if (code.isEmpty) return;

      final now = DateTime.now();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('late_notified_date') == todayKey) return;

      final late = await OdooRpcService().getLateMinutes(code, now.month, now.year);
      final info = late[todayKey];
      if (info == null || info.minutes <= 0) return;

      await NotificationService().showLateCheckinNotification(
        minutes: info.minutes,
        checkinTime: info.checkin,
      );
      await prefs.setString('late_notified_date', todayKey);
    } catch (e) {
      // แจ้งเตือนพลาดไม่ควรทำให้การลงเวลาพัง
      debugPrint('⚠️ _notifyIfLateToday error: $e');
    }
  }

  void _handleCheckinComplete(String message, bool isSuccess) {
    // เปลี่ยนไปหน้าหลัก (index 0)
    setState(() {
      _selectedIndex = 0;
    });

    // ✅ ลงเวลาสำเร็จ -> เช็คว่าสายไหม ถ้าสายก็แจ้งเตือน (ไม่ block UI)
    if (isSuccess) {
      _notifyIfLateToday();
    }
    
    // รีเฟรชข้อมูลหน้าหลัก
    if (_homePageKey.currentState != null) {
      _homePageKey.currentState!.refreshData();
    }
    
    // แสดง SnackBar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.ibmPlexSansThai()),
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
              style: GoogleFonts.ibmPlexSansThai(),
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
    } else if (_pages[index] is ApprovalsHubScreen) {
      _refreshApprovalTab(_approvalsHubKey.currentState?.currentTab ?? 0);
    }
  }

  // 🎨 แสดง dialog เลือกสีธีม
  Future<void> _showThemePicker() async {
    final List<Map<String, dynamic>> presets = [
      {'name': 'เหลือง NPD (ค่าเริ่มต้น)', 'color': ThemeController.defaultColor},
      {'name': 'น้ำเงิน', 'color': const Color(0xFF1976D2)},
      {'name': 'ฟ้า', 'color': const Color(0xFF0288D1)},
      {'name': 'เขียว', 'color': const Color(0xFF388E3C)},
      {'name': 'เขียวมิ้นต์', 'color': const Color(0xFF26A69A)},
      {'name': 'ม่วง', 'color': const Color(0xFF7B1FA2)},
      {'name': 'ม่วงอมชมพู', 'color': const Color(0xFFAB47BC)},
      {'name': 'แดง', 'color': const Color(0xFFD32F2F)},
      {'name': 'ส้ม', 'color': const Color(0xFFF57C00)},
      {'name': 'ชมพู', 'color': const Color(0xFFE91E63)},
      {'name': 'น้ำตาล', 'color': const Color(0xFF6D4C41)},
      {'name': 'เทาเข้ม', 'color': const Color(0xFF424242)},
    ];

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.palette_outlined),
              const SizedBox(width: 8),
              Text('เลือกสีธีมแอป',
                  style: GoogleFonts.ibmPlexSansThai(
                      fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'สีปัจจุบันจะถูกบันทึกไว้เฉพาะของคุณ',
                    style: GoogleFonts.ibmPlexSansThai(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ...presets.map((p) {
                        final Color color = p['color'] as Color;
                        final String name = p['name'] as String;
                        final bool selected = ThemeController
                                .instance.primaryColor.value ==
                            color.value;
                        return InkWell(
                          onTap: () async {
                            await ThemeController.instance
                                .setColor(widget.user.id, color);
                            if (mounted && Navigator.canPop(ctx)) {
                              Navigator.of(ctx).pop();
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('เปลี่ยนสีธีมเป็น "$name" แล้ว',
                                      style: GoogleFonts.ibmPlexSansThai()),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: Tooltip(
                            message: name,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Colors.black
                                      : Colors.grey.shade300,
                                  width: selected ? 3 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: selected
                                  ? Icon(Icons.check,
                                      color: ThemeData.estimateBrightnessForColor(
                                                  color) ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.black,
                                      size: 28)
                                  : null,
                            ),
                          ),
                        );
                      }),
                      // ปุ่ม "ปรับเอง" — เปิด dialog เลือกสีอิสระ
                      InkWell(
                        onTap: () async {
                          if (mounted && Navigator.canPop(ctx)) {
                            Navigator.of(ctx).pop();
                          }
                          await _showCustomColorPicker();
                        },
                        child: Tooltip(
                          message: 'ปรับสีเอง',
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const SweepGradient(
                                colors: [
                                  Color(0xFFFF1744),
                                  Color(0xFFFFEA00),
                                  Color(0xFF00E676),
                                  Color(0xFF00B0FF),
                                  Color(0xFFD500F9),
                                  Color(0xFFFF1744),
                                ],
                              ),
                              border: Border.all(
                                  color: Colors.grey.shade300, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: const Icon(Icons.colorize,
                                color: Colors.white, size: 26),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: Icon(Icons.refresh, color: Colors.grey.shade700),
              label: Text('รีเซ็ตสีเดิม',
                  style: GoogleFonts.ibmPlexSansThai(
                      color: Colors.grey.shade700)),
              onPressed: ThemeController.instance.isDefault
                  ? null
                  : () async {
                      await ThemeController.instance
                          .reset(widget.user.id);
                      if (mounted && Navigator.canPop(ctx)) {
                        Navigator.of(ctx).pop();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('รีเซ็ตเป็นสีเริ่มต้นแล้ว',
                                style: GoogleFonts.ibmPlexSansThai()),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('ปิด', style: GoogleFonts.ibmPlexSansThai()),
            ),
          ],
        );
      },
    );
  }

  // 🎨 Dialog เลือกสีเอง (HSV sliders + Hex input + preview)
  Future<void> _showCustomColorPicker() async {
    HSVColor hsv = HSVColor.fromColor(ThemeController.instance.primaryColor);
    final TextEditingController hexController = TextEditingController(
      text: '#${hsv.toColor().value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
    );

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final Color current = hsv.toColor();

            void updateHexFromHsv() {
              // อ่าน hsv ตรงๆ (closure variable ถูก mutate ผ่าน setStateDialog แล้ว)
              // ห้ามอ่านจาก current ที่ build snapshot ไว้ — มันจะเป็นค่าเก่า
              final c = hsv.toColor();
              hexController.text =
                  '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
            }

            void applyHex(String input) {
              String s = input.trim().replaceAll('#', '').toUpperCase();
              if (s.length == 6) {
                final int? v = int.tryParse(s, radix: 16);
                if (v != null) {
                  setStateDialog(() {
                    hsv = HSVColor.fromColor(Color(0xFF000000 | v));
                  });
                }
              }
            }

            Widget hueSliderTrack() {
              return Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.colorize),
                  const SizedBox(width: 8),
                  Text('ปรับสีเอง',
                      style: GoogleFonts.ibmPlexSansThai(
                          fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: current,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.grey.shade300, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Hue (สี)',
                          style: GoogleFonts.ibmPlexSansThai(fontSize: 13)),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: hueSliderTrack(),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.transparent,
                              inactiveTrackColor: Colors.transparent,
                              trackHeight: 12,
                              thumbColor: Colors.white,
                              overlayColor: Colors.black.withOpacity(0.06),
                            ),
                            child: Slider(
                              min: 0,
                              max: 360,
                              value: hsv.hue,
                              onChanged: (v) {
                                setStateDialog(() {
                                  hsv = hsv.withHue(v);
                                  updateHexFromHsv();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      Text('Saturation (ความเข้ม)',
                          style: GoogleFonts.ibmPlexSansThai(fontSize: 13)),
                      Slider(
                        min: 0,
                        max: 1,
                        value: hsv.saturation,
                        activeColor: current,
                        onChanged: (v) {
                          setStateDialog(() {
                            hsv = hsv.withSaturation(v);
                            updateHexFromHsv();
                          });
                        },
                      ),
                      Text('Brightness (ความสว่าง)',
                          style: GoogleFonts.ibmPlexSansThai(fontSize: 13)),
                      Slider(
                        min: 0,
                        max: 1,
                        value: hsv.value,
                        activeColor: current,
                        onChanged: (v) {
                          setStateDialog(() {
                            hsv = hsv.withValue(v);
                            updateHexFromHsv();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: hexController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Hex',
                          labelStyle: GoogleFonts.ibmPlexSansThai(),
                          hintText: '#RRGGBB',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                        onSubmitted: applyHex,
                        onEditingComplete: () => applyHex(hexController.text),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('ยกเลิก', style: GoogleFonts.ibmPlexSansThai()),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text('ใช้สีนี้',
                      style: GoogleFonts.ibmPlexSansThai()),
                  onPressed: () async {
                    final picked = hsv.toColor();
                    await ThemeController.instance
                        .setColor(widget.user.id, picked);
                    if (mounted && Navigator.canPop(ctx)) {
                      Navigator.of(ctx).pop();
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('เปลี่ยนสีธีมแล้ว',
                              style: GoogleFonts.ibmPlexSansThai()),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    final bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'ออกจากระบบ',
          style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.w500),
        ),
        content: Text(
          'คุณต้องการออกจากระบบใช่หรือไม่?',
          style: GoogleFonts.ibmPlexSansThai(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'ยกเลิก',
              style: GoogleFonts.ibmPlexSansThai(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'ยืนยัน',
              style: GoogleFonts.ibmPlexSansThai(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmLogout ?? false) {
      await _safeClearPrefs();
      // เครื่องเดียวใช้หลายคนได้ — ห้ามให้รูปคนเก่าค้างให้คนถัดไปเห็น
      ProfilePhotoService.instance.clear();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const PinLoginScreen()),
          (Route<dynamic> route) => false,
        );
      }
    }
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

    // ทุกหน้ามีแถบหัวของตัวเองแล้ว (หน้าแรกมีส่วนหัวใหม่ หน้าอื่นมีแถบหัวในตัว)
    // จึงไม่มีแถบหัวรวมอีก — ของเดิมซ้อนกันสองชั้นทั้งชื่อหน้าและปุ่ม
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _isLoading = true;
  Map<String, dynamic>? _menuData;

  /// ข้อมูลสายรายวัน — คำนวณจากสูตรใน Odoo ไม่ได้คิดในแอป
  Map<String, LateInfo> _lateMinutes = {};

  /// ข้อความกะของวันนี้ที่แสดงบนการ์ด "วันนี้" (null = ยังไม่รู้/โหลดไม่ได้)
  String? _todayShiftText;

  /// ดึงนาทีสายของ "เดือนที่ปรากฏในประวัติ" (ประวัติ 3 วันอาจคาบ 2 เดือน)
  /// ล้มเหลวก็เงียบ ๆ แค่ไม่แสดงข้อความสาย ไม่ทำให้หน้าหลักพัง
  Future<void> _loadLateMinutesForHistory(dynamic history) async {
    if (history is! List || history.isEmpty) return;
    final code = widget.user.employeeCode ?? '';
    if (code.isEmpty) return;

    final Set<String> months = {};
    for (final item in history) {
      final date = (item is Map ? item['work_date'] : null)?.toString() ?? '';
      if (date.length >= 7) months.add(date.substring(0, 7)); // YYYY-MM
    }

    final Map<String, LateInfo> merged = {};
    final service = OdooRpcService();
    for (final ym in months) {
      final year = int.tryParse(ym.substring(0, 4));
      final month = int.tryParse(ym.substring(5, 7));
      if (year == null || month == null) continue;
      merged.addAll(await service.getLateMinutes(code, month, year));
    }
    if (mounted) setState(() => _lateMinutes = merged);
  }
  String _errorMessage = '';
  late Timer _historyTimer; // Timer for real-time refresh of history

  // ✅ เพิ่มตัวแปรเพื่อติดตามว่าควรจะ refresh หรือไม่
  bool _needsRefresh = true;

  // 🔔 จำนวนใบเตือน
  int _warningCount = 0; // ทั้งหมด (แสดงใน popup ข้อมูลพนักงาน)
  int _unreadWarningCount = 0; // ยังไม่อ่าน (แสดงบน badge)

  @override
  void initState() {
    super.initState();
    // initializeDateFormatting('th', null); // ควรถูกเรียกใน main() แล้ว
    _startHistoryTimer(); // เริ่มจับเวลาสำหรับ history
    _loadWarningCount();
    _loadTodayShift();
    // รูปโปรไฟล์ของคนที่ล็อกอินอยู่ — ดึงจากบัตรพนักงานใน Odoo
    WidgetsBinding.instance.addObserver(this);
    ProfilePhotoService.instance.bind(widget.user.employeeCode);
    ProfilePhotoService.instance.load();
    _resumeLostPhoto();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // กลับเข้าแอปหลังเปิดกล้อง/คลังภาพ — ถ้าตอนนั้นแอปถูกระบบปิดไป
    // ผลการเลือกรูปจะค้างอยู่ฝั่ง Android ต้องมาดึงต่อเอง
    if (state == AppLifecycleState.resumed) _resumeLostPhoto();
  }

  /// อัปโหลดรูปที่เลือกค้างไว้ (ถ้ามี) แล้วแจ้งผลให้ผู้ใช้รู้
  Future<void> _resumeLostPhoto() async {
    final message = await ProfilePhotoService.instance.retrieveLostPhoto();
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.ibmPlexSansThai())),
    );
  }

  Future<void> _loadWarningCount() async {
    try {
      final code = widget.user.employeeCode ?? '';
      if (code.isEmpty) return;
      final count =
          await OdooRpcService().getEmployeeWarningCount(code);
      if (!mounted) return;

      // ⚠️ ติดต่อเซิร์ฟเวอร์ไม่ได้ → ไม่รู้ยอดจริง ห้ามทำอะไรทั้งนั้น
      //    ถ้าปล่อยให้ไหลต่อ ระบบจะเข้าใจว่า "ไม่มีใบเตือน" แล้วไป
      //    ยกเลิกแจ้งเตือน + ลบสถานะอ่านแล้วทิ้ง (ยิ่งเช็คทุก 30 วิ ยิ่งพัง)
      if (count == null) {
        debugPrint('⚠️ ดึงจำนวนใบเตือนไม่ได้ (เน็ต/เซิร์ฟเวอร์) — คงสถานะเดิมไว้');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final prefKey = 'warning_read_count_$code';
      final notifiedKey = 'warning_notified_count_$code';
      final readCount = prefs.getInt(prefKey) ?? 0;
      final notifiedCount = prefs.getInt(notifiedKey) ?? 0;

      // ✅ Badge แสดงเฉพาะใบเตือนที่ยังไม่อ่าน (unread = total - read)
      final unread = count > readCount ? (count - readCount) : 0;

      setState(() {
        _warningCount = count; // ทั้งหมด
        _unreadWarningCount = unread; // ยังไม่อ่าน
      });

      if (unread > 0) {
        // ✅ เด้งเฉพาะตอนที่ "มีใบเพิ่มขึ้นจริง" เท่านั้น
        //    เพราะตัวนี้ถูกเรียกทุก 30 วินาที ถ้าเด้งทุกรอบจะสั่นไม่หยุด
        //    (ใบที่ยังไม่อ่านยังคงค้างอยู่บน badge เหมือนเดิม)
        if (count > notifiedCount) {
          await NotificationService().showWarningNotification(count: unread);
          await prefs.setInt(notifiedKey, count);
        }
      } else {
        // ไม่มีใบเตือนที่ยังไม่อ่าน → ยกเลิกแจ้งเตือน
        await NotificationService().cancelWarningNotification();
        await prefs.setInt(notifiedKey, count);
      }

      if (count == 0) {
        // ไม่มีใบเตือนเลย → reset counter
        await prefs.remove(prefKey);
        await prefs.remove(notifiedKey);
      }
    } catch (e) {
      debugPrint('Error loading warning count: $e');
    }
  }

  /// เรียกเมื่อผู้ใช้เปิดอ่านหน้าใบเตือนแล้ว
  /// → ยกเลิกการแจ้งเตือน + badge และจำไว้ว่าอ่านจำนวนนี้แล้ว
  Future<void> _markWarningsAsRead() async {
    try {
      final code = widget.user.employeeCode ?? '';
      if (code.isEmpty) return;

      // ดึงจำนวนใบเตือนจริงจากเซิร์ฟเวอร์
      // ถ้าเน็ตหลุด ใช้ยอดล่าสุดที่รู้แทน — ผู้ใช้กดอ่านจริง badge ต้องหาย
      final totalCount =
          await OdooRpcService().getEmployeeWarningCount(code) ?? _warningCount;

      // บันทึกว่าอ่านใบเตือนถึงจำนวนนี้แล้ว
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('warning_read_count_$code', totalCount);
      // อ่านแล้ว = ถือว่าแจ้งเตือนถึงใบนี้แล้ว ใบถัดไปถึงจะเด้งใหม่
      await prefs.setInt('warning_notified_count_$code', totalCount);

      // ล้าง badge (unread = 0) แต่ total ยังอยู่
      if (mounted) {
        setState(() {
          _warningCount = totalCount;
          _unreadWarningCount = 0;
        });
      }

      // ยกเลิกแจ้งเตือน
      await NotificationService().cancelWarningNotification();
    } catch (e) {
      debugPrint('Error marking warnings as read: $e');
    }
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
    // 🔔 refresh warning count ด้วย
    _loadWarningCount();
  }

  /// 🔔 เช็คและแจ้งเตือนสำหรับผู้อนุมัติ
  /// เปรียบเทียบ count ปัจจุบันกับที่ "อ่านแล้ว" ครั้งก่อน
  /// ถ้ามีคำขอใหม่เพิ่มขึ้น → แจ้งเตือน
  Future<void> _checkApproverNotifications({
    required int leaveCount,
    required int addTimeCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.user.id;

    // ----- คำขอลา -----
    final seenLeaveKey = 'approver_seen_leave_$userId';
    final seenLeave = prefs.getInt(seenLeaveKey) ?? 0;
    if (leaveCount > seenLeave) {
      await NotificationService()
          .showApproverLeaveNotification(leaveCount);
    } else if (leaveCount == 0) {
      await NotificationService().cancelApproverLeaveNotification();
      await prefs.remove(seenLeaveKey);
    }

    // ----- คำขอเพิ่มเวลา -----
    final seenAddTimeKey = 'approver_seen_addtime_$userId';
    final seenAddTime = prefs.getInt(seenAddTimeKey) ?? 0;
    if (addTimeCount > seenAddTime) {
      await NotificationService()
          .showApproverAddTimeNotification(addTimeCount);
    } else if (addTimeCount == 0) {
      await NotificationService().cancelApproverAddTimeNotification();
      await prefs.remove(seenAddTimeKey);
    }
  }

  /// เรียกเมื่อผู้อนุมัติเข้าหน้าอนุมัติ → mark as seen + cancel notification
  Future<void> markApproverLeaveAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final count = _menuData?['pending_leave_count'] ?? 0;
    await prefs.setInt('approver_seen_leave_${widget.user.id}', count);
    await NotificationService().cancelApproverLeaveNotification();
  }

  Future<void> markApproverAddTimeAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final count = _menuData?['pending_addtime_count'] ?? 0;
    await prefs.setInt('approver_seen_addtime_${widget.user.id}', count);
    await NotificationService().cancelApproverAddTimeNotification();
  }

  /// 🔔 เช็คสถานะคำขอของผู้ใช้เอง (การลา + เพิ่มเวลา + ค่ารักษาพยาบาล)
  /// ถ้า state เปลี่ยนจาก 'รออนุมัติ' → 'อนุมัติ' / 'ไม่อนุมัติ' / 'ยกเลิก' → แจ้งเตือน
  ///
  /// ค่ารักษาพยาบาลอนุมัติที่ Odoo แล้ว Odoo จะ push สถานะกลับมาที่ PHP
  /// รอบ poll นี้จึงเห็นการเปลี่ยนแปลงและแจ้งเตือนได้เหมือนคำขออื่น
  Future<void> _checkRequesterStatusNotifications() async {
    final userId = widget.user.id;
    final prefs = await SharedPreferences.getInstance();

    // รอบแรกของผู้ใช้คนนี้ ให้จำสถานะไว้เฉย ๆ ไม่ต้องแจ้งเตือน
    // ไม่งั้นพอลงแอปใหม่จะเด้งย้อนหลังรวดเดียวหลายใบ
    //
    // หลังจากรอบแรกแล้ว ใบที่ไม่เคยเห็นมาก่อนและสถานะไม่ใช่ "รออนุมัติ"
    // ถือว่าเพิ่งถูกตัดสินตอนแอปปิดอยู่ → ต้องแจ้งเตือน
    // (เดิมเช็คแค่ prevState == 'รออนุมัติ' ใบที่ถูกอนุมัติตอนแอปปิดจึงเงียบหายไป)
    final initKey = 'req_notify_init_$userId';
    final bool isFirstRun = !(prefs.getBool(initKey) ?? false);
    // ปักธง "จำสถานะครบแล้ว" ต่อเมื่อดึงข้อมูลสำเร็จทั้งสองชุด
    // ถ้าเน็ตหลุดกลางทางแล้วปักธงไป รอบหน้าจะเด้งย้อนหลังทั้งกอง
    bool leaveOk = false;
    bool addTimeOk = false;

    // ---- ดึงคำขอลาของผู้ใช้ ----
    try {
      final leaveResp = await http.get(Uri.parse(
          'https://npdhrms.com/api/leave_requests.php?user_id=$userId')).timeout(
        const Duration(seconds: 15),
      );
      if (leaveResp.statusCode == 200) {
        leaveOk = true;
        final body = json.decode(leaveResp.body);
        final List<dynamic> logs = body is List
            ? body
            : (body is Map ? (body['data'] ?? body['logs'] ?? []) : []);
        for (final l in logs) {
          if (l is! Map) continue;
          final id = l['id']?.toString() ?? '';
          final state = (l['state'] ?? '').toString();
          if (id.isEmpty || state.isEmpty) continue;

          final key = 'req_leave_state_${userId}_$id';
          final prevState = prefs.getString(key);

          // แจ้งเตือนเมื่อสถานะเปลี่ยนจากที่เคยเห็น ไม่ใช่เฉพาะขาที่ออกจาก "รออนุมัติ"
          // เพราะใบที่อนุมัติแล้วยังถูกยกเลิกหรือถอยกลับได้อีก
          final bool stateChanged = prevState != null && prevState != state;
          final bool firstSeenDecided = prevState == null && state != 'รออนุมัติ';
          if (!isFirstRun && (stateChanged || firstSeenDecided)) {
            final approverName = [
              (l['approver_firstname'] ?? '').toString(),
              (l['approver_lastname'] ?? '').toString(),
            ].where((s) => s.isNotEmpty && s != 'NULL').join(' ');
            final leaveType = (l['leave_type'] ?? '').toString();
            final reason = (l['reason'] ?? '').toString();
            final bodyBuf = StringBuffer();
            if (leaveType.isNotEmpty) bodyBuf.writeln('ประเภท: $leaveType');
            if (approverName.isNotEmpty) bodyBuf.writeln('โดย: $approverName');
            if (reason.isNotEmpty && reason != 'NULL') {
              bodyBuf.writeln('หมายเหตุ: $reason');
            }
            await NotificationService().showInstantNotification(
              title: 'คำขอลา${state}แล้ว',
              body: bodyBuf.toString().trim().isEmpty
                  ? 'อัปเดตสถานะคำขอลา'
                  : bodyBuf.toString().trim(),
            );
          }
          // บันทึก state ล่าสุดสำหรับคำขอนี้
          await prefs.setString(key, state);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Check leave requests error: $e');
    }

    // ---- ดึงคำขอเพิ่มเวลาของผู้ใช้ ----
    try {
      final addResp = await http.get(Uri.parse(
          'https://npdhrms.com/api/manual_time_logs_test.php?user_id=$userId'))
          .timeout(const Duration(seconds: 15));
      if (addResp.statusCode == 200) {
        addTimeOk = true;
        final body = json.decode(addResp.body);
        final List<dynamic> logs = body is List
            ? body
            : (body is Map ? (body['data'] ?? body['logs'] ?? []) : []);
        for (final l in logs) {
          if (l is! Map) continue;
          final id = l['id']?.toString() ?? '';
          final state = (l['state'] ?? '').toString();
          if (id.isEmpty || state.isEmpty) continue;

          final key = 'req_addtime_state_${userId}_$id';
          final prevState = prefs.getString(key);

          final bool stateChanged = prevState != null && prevState != state;
          final bool firstSeenDecided = prevState == null && state != 'รออนุมัติ';
          if (!isFirstRun && (stateChanged || firstSeenDecided)) {
            // ตารางนี้เก็บทั้งคำขอเพิ่มเวลาและค่ารักษาพยาบาลปนกัน
            // ต้องแยกประเภทก่อน ไม่งั้นค่ารักษาพยาบาลจะเด้งว่า "คำขอเพิ่มเวลา"
            final reasonType = (l['reason_type'] ?? '').toString();
            final isMedical = reasonType == kMedicalReasonType;

            final approverName = [
              (l['approver_firstname'] ?? '').toString(),
              (l['approver_lastname'] ?? '').toString(),
            ].where((s) => s.isNotEmpty && s != 'NULL').join(' ');
            final reason = (l['reason'] ?? '').toString();

            final bodyBuf = StringBuffer();
            if (isMedical) {
              // ค่ารักษาพยาบาลอนุมัติจากฝั่ง Odoo — ยอดเงินคือสิ่งที่พนักงานอยากรู้ที่สุด
              final amount = double.tryParse((l['amount'] ?? '').toString());
              if (amount != null && amount > 0) {
                bodyBuf.writeln(
                    'จำนวนเงิน: ${NumberFormat('#,##0.00').format(amount)} บาท');
              }
            } else if (reasonType.isNotEmpty && reasonType != 'NULL') {
              bodyBuf.writeln('ประเภท: $reasonType');
            }
            if (approverName.isNotEmpty) bodyBuf.writeln('โดย: $approverName');
            if (reason.isNotEmpty && reason != 'NULL') {
              bodyBuf.writeln('หมายเหตุ: $reason');
            }

            final what = isMedical ? 'ค่ารักษาพยาบาล' : 'คำขอเพิ่มเวลา';
            final String title;
            switch (state) {
              case 'อนุมัติ':
                title = '${what}ได้รับการอนุมัติแล้ว';
                break;
              case 'ไม่อนุมัติ':
                title = '${what}ไม่ได้รับการอนุมัติ';
                break;
              case 'ยกเลิก':
                title = '${what}ถูกยกเลิก';
                break;
              case 'รออนุมัติ':
                // เกิดจากผู้อนุมัติกด "ถอยกลับการอนุมัติ" ใน Odoo
                title = '${what}ถูกส่งกลับมารออนุมัติใหม่';
                break;
              default:
                title = '${what}: $state';
            }

            await NotificationService().showInstantNotification(
              title: title,
              body: bodyBuf.toString().trim().isEmpty
                  ? 'อัปเดตสถานะ${what}'
                  : bodyBuf.toString().trim(),
            );
          }
          await prefs.setString(key, state);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Check addtime requests error: $e');
    }

    if (isFirstRun && leaveOk && addTimeOk) {
      await prefs.setBool(initKey, true);
    }
  }

  void _startHistoryTimer() {
    _historyTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) return;

      // 🔔 เช็คใบเตือนใหม่ทุกรอบ ไม่ว่าจะอยู่แท็บไหน
      //    ก่อนหน้านี้เช็คแค่ตอนเปิดแอปกับตอนสลับกลับมาหน้าแรก
      //    ใบเตือนที่ออกตอนแอปเปิดค้างอยู่จึงเงียบไปเลย
      _loadWarningCount();

      // ✅ ข้อมูลหน้าแรก โหลดเฉพาะเมื่อหน้า HomePage ถูกแสดงอยู่
      final mainAppScreenState =
          context.findAncestorStateOfType<_MainAppScreenState>();
      if (mainAppScreenState != null &&
          mainAppScreenState._selectedIndex == 0) {
        _fetchMenuData(); // เรียก fetch data อีกครั้ง
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
    WidgetsBinding.instance.removeObserver(this);
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
        // ✅ ดึงนาทีสายของวันที่อยู่ในประวัติ ตามสูตรที่ตั้งใน Odoo
        _loadLateMinutesForHistory(data['checkin_history']);
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

        // เช็คและแจ้งเตือนเข้า-ออกงาน (เช็คจากประวัติลงเวลาจริง)
        try {
          final checkinHistory = data['checkin_history'] ?? [];
          await NotificationService().checkAndNotify(
            employeeCode: widget.user.employeeCode ?? '',
            employeeName: widget.user.firstname,
            checkinHistory: checkinHistory,
          );
        } catch (e) {
          debugPrint('⚠️ Notification check error: $e');
        }

        // 🔔 แจ้งเตือนสำหรับผู้อนุมัติ
        try {
          final isApprover = data['is_approver'] ?? false;
          if (isApprover) {
            await _checkApproverNotifications(
              leaveCount: data['pending_leave_count'] ?? 0,
              addTimeCount: data['pending_addtime_count'] ?? 0,
            );
          }
        } catch (e) {
          debugPrint('⚠️ Approver notification error: $e');
        }

        // 🔔 เช็คสถานะคำขอของผู้ใช้ (แจ้งเตือนเมื่ออนุมัติ/ปฏิเสธ)
        try {
          await _checkRequesterStatusNotifications();
        } catch (e) {
          debugPrint('⚠️ Requester notification error: $e');
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
      debugPrint('Connection Timeout in HomePage: $e');
      // ✅ ถ้ามีข้อมูลเก่าอยู่แล้ว ไม่ต้องแสดง error (silent fail)
      if (_menuData == null) {
        setState(() {
          _errorMessage = 'การเชื่อมต่อหมดเวลา กรุณาลองใหม่';
        });
      }
    } on SocketException catch (e) {
      if (!mounted) return;
      debugPrint('Socket Exception (No Internet) in HomePage: $e');
      // ✅ ถ้ามีข้อมูลเก่าอยู่แล้ว ไม่ต้องแสดง error
      if (_menuData == null) {
        setState(() {
          _errorMessage = 'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้';
        });
      }
    } on FormatException catch (e) {
      if (!mounted) return;
      debugPrint('FormatException in HomePage: $e');
      if (_menuData == null) {
        setState(() {
          _errorMessage = 'รูปแบบข้อมูลไม่ถูกต้องจากเซิร์ฟเวอร์';
        });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error fetching menu data in HomePage: $e');
      if (_menuData == null) {
        setState(() => _errorMessage = 'เกิดข้อผิดพลาดในการดึงข้อมูล');
      }
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

  /// อ่านกะของวันนี้ไว้แสดงบนการ์ด "วันนี้" — โหลดครั้งเดียวตอนเปิดหน้า
  /// ตารางงานไม่ได้เปลี่ยนบ่อย ไม่ต้องดึงซ้ำทุก 30 วินาทีเหมือนประวัติ
  /// โหลดไม่ได้ก็แค่ไม่แสดงบรรทัดกะ ไม่กระทบส่วนอื่นของหน้า
  Future<void> _loadTodayShift() async {
    if (widget.user.position == 'ที่ปรึกษา') return;
    try {
      final schedule = await OdooRpcService()
          .getWorkSchedule(widget.user.employeeCode ?? '');
      if (!mounted || schedule == null || schedule.isEmpty) return;

      String text;
      if (schedule['category'] == 'no_checkin') {
        text = 'ไม่ต้องลงเวลา';
      } else {
        // getWorkSchedule ส่งเฉพาะวันที่ต้องทำงาน โดยใช้ชื่อวันภาษาอังกฤษ
        const dayNames = [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ];
        final String todayName = dayNames[DateTime.now().weekday - 1];
        Map? today;
        final days = schedule['days'];
        if (days is List) {
          for (final day in days) {
            if (day is Map && day['day'] == todayName) {
              today = day;
              break;
            }
          }
        }
        text = today == null
            ? 'วันหยุด'
            : 'กะวันนี้ ${_shiftTime(today['start_hour'])}'
                ' – ${_shiftTime(today['end_hour'])} น.';
      }
      setState(() => _todayShiftText = text);
    } catch (e) {
      debugPrint('โหลดกะของวันนี้ไม่สำเร็จ: $e');
    }
  }

  /// ชั่วโมงทศนิยมจาก Odoo (8.5) → "08:30"
  static String _shiftTime(dynamic hours) {
    final double value = hours is num ? hours.toDouble() : 0;
    final int h = value.floor();
    final int m = ((value - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// เวลาเข้า-ออกของวันนี้ จากประวัติที่หน้าแรกโหลดมาอยู่แล้ว (ไม่ยิงเพิ่ม)
  _TodayStatus _todayStatus() {
    final List history = _menuData?['checkin_history'] ?? const [];
    final String today = _dateKey(DateTime.now());
    final entries = history
        .whereType<Map>()
        .where((e) => e['work_date'] == today)
        .toList()
      ..sort((a, b) => '${a['full_datetime'] ?? ''}'
          .compareTo('${b['full_datetime'] ?? ''}'));

    String? firstIn;
    String? lastOut;
    String? lastType;
    for (final entry in entries) {
      final type = entry['check_type'];
      if (type == 'in') {
        firstIn ??= entry['work_time']?.toString();
        // เข้างานรอบใหม่หลังออกไปแล้ว (เช่นพักกลางวัน) — ยังไม่ถือว่าออกงาน
        lastOut = null;
        lastType = 'in';
      } else if (type == 'out') {
        lastOut = entry['work_time']?.toString();
        lastType = 'out';
      }
    }
    return _TodayStatus(firstIn: firstIn, lastOut: lastOut, lastType: lastType);
  }

  /// สลับไปแท็บของแถบเมนูล่าง — ถ้าหน้าแรกถูกเปิดเดี่ยว ๆ (ไม่มีแถบเมนู) ค่อยเปิดเป็นหน้าใหม่
  void _openTab(int index, WidgetBuilder fallback) {
    final shell = context.findAncestorStateOfType<_MainAppScreenState>();
    if (shell != null) {
      shell._onItemTapped(index);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: fallback));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isConsultant = widget.user.position == 'ที่ปรึกษา';
    final scheme = Theme.of(context).colorScheme;

    final List<Widget> sections;
    if (_isLoading && _menuData == null) {
      sections = [
        const SizedBox(height: 40),
        Center(child: CircularProgressIndicator(color: scheme.primary)),
      ];
    } else if (_errorMessage.isNotEmpty) {
      sections = [_buildErrorState()];
    } else {
      sections = [
        const AppSectionHeader('เมนูหลัก'),
        if (isConsultant)
          _buildConsultantMenuGrid(context)
        else
          _buildMenuGrid(context),
        if (_menuData?['is_approver'] ?? false) ...[
          const SizedBox(height: 20),
          _buildApproverSection(),
        ],
        if (!isConsultant) ...[
          const SizedBox(height: 20),
          AppSectionHeader(
            'ลงเวลาล่าสุด',
            actionLabel: 'ดูทั้งหมด',
            onAction: _showFullCheckinHistory,
          ),
          _buildHistoryList(),
        ],
        const SizedBox(height: 24),
      ];
    }

    // แถบหัวสีธีมโค้งมน + การ์ด "วันนี้" ลอยทับ (แนวเดียวกับแอปฝั่ง Odoo 18)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.overlayStyleFor(scheme.primary),
      child: RefreshIndicator(
        // Allow manual pull-to-refresh
        onRefresh: _fetchMenuData,
        color: AppColors.ink(scheme.primary),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(),
              // เลื่อนขึ้นทับแถบหัวด้วย Transform ไม่ใช่ Stack — กดการ์ดได้ทั้งใบ
              Transform.translate(
                offset: const Offset(0, -54),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      // ที่ปรึกษาไม่ต้องลงเวลา — เห็นแค่นาฬิกา ไม่มีปุ่มลงเวลา
                      child: isConsultant
                          ? _heroCard(child: const RealTimeClock())
                          : _buildTodayCard(),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: sections,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// กล่องลอยทับแถบหัว — เงาเข้มกว่าการ์ดอื่นเพื่อให้ดูลอยจริง
  Widget _heroCard({required Widget child}) {
    return Material(
      color: AppColors.surface,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppColors.frame(Theme.of(context).colorScheme.primary),
          ),
        ),
        child: child,
      ),
    );
  }

  /// ป้ายสถานะการลงเวลาของวันนี้ บนแถบหัว
  Widget _headerStatusChip(Color onAccent) {
    final today = _todayStatus();
    final IconData icon;
    final String label;
    if (today.lastType == 'in') {
      icon = Icons.check_circle;
      label = 'กำลังทำงาน';
    } else if (today.lastType == 'out') {
      icon = Icons.task_alt_rounded;
      label = 'ออกงานแล้ว';
    } else if (_todayShiftText == 'วันหยุด' ||
        _todayShiftText == 'ไม่ต้องลงเวลา') {
      icon = Icons.beach_access_rounded;
      label = _todayShiftText!;
    } else {
      icon = Icons.schedule_rounded;
      label = 'ยังไม่ลงเวลา';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: onAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onAccent, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.ibmPlexSansThai(
              color: onAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 56, color: AppColors.textFaint),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSansThai(
              fontSize: 15,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchMenuData, // Retry button
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('ลองอีกครั้ง'),
          ),
        ],
      ),
    );
  }

  /// การ์ด "วันนี้" — นาฬิกา กะ เวลาเข้า-ออก และปุ่มลงเวลาใหญ่
  /// ปุ่มพาไปหน้าลงเวลาเดิม (ตรวจพิกัด/บันทึกที่นั่น) การ์ดนี้แค่แสดงผล
  Widget _buildTodayCard() {
    final today = _todayStatus();
    final int lateMinutes =
        _lateMinutes[_dateKey(DateTime.now())]?.minutes ?? 0;

    return _heroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RealTimeClock(),
          if (_todayShiftText != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  _todayShiftText!,
                  style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _TimeStat(
                    icon: Icons.login_rounded,
                    label: 'เข้างาน',
                    time: today.firstIn,
                    color: AppColors.success,
                    note: today.firstIn != null && lateMinutes > 0
                        ? _lateLabel(lateMinutes)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeStat(
                    icon: Icons.logout_rounded,
                    label: 'ออกงาน',
                    time: today.lastOut,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: () => _openTab(
                1,
                (_) => CheckinScreen(
                  userId: widget.user.id,
                  employeeCode: widget.user.employeeCode,
                  isDemoUser: widget.isDemoUser,
                ),
              ),
              icon: Icon(
                today.isWorking
                    ? Icons.logout_rounded
                    : Icons.fingerprint_rounded,
                size: 22,
              ),
              label: Text(today.isWorking ? 'ลงเวลาออกงาน' : 'ลงเวลาเข้างาน'),
              style: ElevatedButton.styleFrom(
                textStyle: GoogleFonts.ibmPlexSansThai(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md + 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ตารางการ์ดเมนู 2 คอลัมน์
  ///
  /// ล็อกความสูงเป็นตัวเลขตายตัวแทนสัดส่วน เพราะสัดส่วนทำให้การ์ดสูงตามความกว้างจอ
  /// (จอใหญ่ = การ์ดยิ่งสูง มีช่องว่างกลางการ์ด)
  Widget _menuGrid(List<Widget> items) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 104,
      ),
      children: items,
    );
  }

  /// ส่วนหัวหน้าแรก — โลโก้ ชื่อผู้ใช้ รูปโปรไฟล์ และปุ่มรีเฟรช/ธีม/ออกจากระบบ
  ///
  /// ปุ่มพวกนี้เดิมอยู่บนแถบหัวรวมของ MainAppScreen ซึ่งซ้อนกับแถบหัวของแต่ละหน้า
  /// ย้ายมาไว้ที่นี่เหมือนแอปฝั่ง Odoo 18
  Widget _buildHeader() {
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color onAccent = AppColors.onAccent(accent);
    final bool isConsultant = widget.user.position == 'ที่ปรึกษา';
    final user = widget.user;
    final String name = '${user.firstname} ${user.lastname}'.trim();
    final String firstname = user.firstname.trim();
    final String initial = firstname.isEmpty ? '?' : firstname.substring(0, 1);
    final String subtitle = [user.position, user.department]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 70),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, AppColors.darken(accent)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.asset(
                    'assets/npd_180x180_padded.png',
                    height: 26,
                    width: 26,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'NPD HRMS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.ibmPlexSansThai(
                      color: onAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _headerIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'รีเฟรชข้อมูล',
                  color: onAccent,
                  loading: _isLoading,
                  onTap: _isLoading ? null : refreshData,
                ),
                _headerIconButton(
                  icon: Icons.palette_outlined,
                  tooltip: 'เปลี่ยนสีธีม',
                  color: onAccent,
                  onTap: () => context
                      .findAncestorStateOfType<_MainAppScreenState>()
                      ?._showThemePicker(),
                ),
                _headerIconButton(
                  icon: Icons.logout_rounded,
                  tooltip: 'ออกจากระบบ',
                  color: onAccent,
                  onTap: () => context
                      .findAncestorStateOfType<_MainAppScreenState>()
                      ?._logout(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildAvatar(onAccent, initial),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()} 👋',
                        style: GoogleFonts.ibmPlexSansThai(
                          color: onAccent.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name.isEmpty ? 'NPD HRMS' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ibmPlexSansThai(
                          color: onAccent,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.ibmPlexSansThai(
                            color: onAccent.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isConsultant) ...[
                  const SizedBox(width: 8),
                  _headerStatusChip(onAccent),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// คำทักทายตามช่วงเวลาของวัน
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'สวัสดีตอนเช้า';
    if (hour < 17) return 'สวัสดีตอนบ่าย';
    return 'สวัสดีตอนเย็น';
  }

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : Icon(icon, color: color),
    );
  }

  /// รูปโปรไฟล์บนส่วนหัว — แตะเพื่อเปลี่ยนรูป
  /// ใช้ช่องรูปเดียวกับบัตรพนักงานใน Odoo ฝ่ายบุคคลเปลี่ยนให้ก็เห็นรูปเดียวกัน
  Widget _buildAvatar(Color onAccent, String initial) {
    return AnimatedBuilder(
      animation: ProfilePhotoService.instance,
      builder: (context, _) {
        final photo = ProfilePhotoService.instance.bytes;
        final bool busy = ProfilePhotoService.instance.busy;

        return InkWell(
          onTap: busy ? null : _showPhotoOptions,
          customBorder: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: onAccent.withOpacity(0.22),
                backgroundImage: photo != null ? MemoryImage(photo) : null,
                child: photo != null
                    ? null
                    : Text(
                        initial,
                        style: GoogleFonts.ibmPlexSansThai(
                          color: onAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              if (busy)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              // ไอคอนกล้องเล็ก ๆ บอกว่าแตะเพื่อเปลี่ยนรูปได้
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_camera_rounded,
                    size: 12,
                    color: AppColors.ink(Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// เมนูเปลี่ยนรูปโปรไฟล์
  Future<void> _showPhotoOptions() async {
    final bool hasPhoto = ProfilePhotoService.instance.bytes != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            _photoOption(ctx, 'camera', Icons.photo_camera_rounded, 'ถ่ายรูปใหม่'),
            _photoOption(
                ctx, 'gallery', Icons.photo_library_rounded, 'เลือกจากคลังภาพ'),
            if (hasPhoto)
              _photoOption(
                  ctx, 'delete', Icons.delete_outline_rounded, 'ลบรูปโปรไฟล์',
                  color: AppColors.danger),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    String? message;
    switch (choice) {
      case 'camera':
        message = await ProfilePhotoService.instance
            .pickAndUpload(ImageSource.camera);
        break;
      case 'gallery':
        message = await ProfilePhotoService.instance
            .pickAndUpload(ImageSource.gallery);
        break;
      case 'delete':
        message = await ProfilePhotoService.instance.remove();
        break;
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.ibmPlexSansThai())),
      );
    }
  }

  Widget _photoOption(
    BuildContext ctx,
    String value,
    IconData icon,
    String label, {
    Color color = AppColors.text,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: GoogleFonts.ibmPlexSansThai(fontSize: 15, color: color),
      ),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  // เมนูหลัก — การ์ด 2 คอลัมน์ มีคำอธิบายใต้ชื่อเมนู
  // ("ลงเวลา" ย้ายไปเป็นปุ่มใหญ่บนการ์ด "วันนี้" แล้ว)
  Widget _buildMenuGrid(BuildContext context) {
    return _menuGrid([
      _ActionCard(
        icon: Icons.event_note_rounded,
        color: const Color(0xFFEF6C00),
        title: 'การลา',
        subtitle: 'ขอลาและดูประวัติ',
        onTap: () => _openTab(2, (_) => LeaveScreen(user: widget.user)),
      ),
      _ActionCard(
        icon: Icons.more_time_rounded,
        color: const Color(0xFF2E7D32),
        title: 'เพิ่มเวลา',
        subtitle: 'ขอเพิ่มหรือแก้เวลา',
        onTap: () => _openTab(3, (_) => AddTimeScreen(user: widget.user)),
      ),
      _ActionCard(
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF1565C0),
        title: 'สลิปเงินเดือน',
        subtitle: 'ดูสลิปย้อนหลัง',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PayslipScreen(user: widget.user)),
        ),
      ),
      _ActionCard(
        icon: Icons.person_search_rounded,
        color: const Color(0xFF7B1FA2),
        title: 'ข้อมูลพนักงาน',
        subtitle: _unreadWarningCount > 0
            ? 'มีใบเตือนใหม่ $_unreadWarningCount ใบ'
            : 'ข้อมูลส่วนตัวและใบเตือน',
        badge: _unreadWarningCount > 0 ? '$_unreadWarningCount' : null,
        onTap: () => _showEmployeeInfoPopup(context),
      ),
      _ActionCard(
        icon: Icons.description_rounded,
        color: const Color(0xFFE65100),
        title: 'เอกสาร ทวิ50',
        subtitle: 'หนังสือรับรองหักภาษี',
        onTap: () => _showWtCertPopup(context),
      ),
      _ActionCard(
        icon: Icons.history_rounded,
        color: const Color(0xFF00796B),
        title: 'ประวัติลงเวลา',
        subtitle: 'ดูย้อนหลังรายเดือน',
        onTap: _showFullCheckinHistory,
      ),
    ]);
  }

  // ✅ ดึงข้อมูลพนักงานจาก Odoo ผ่าน JSON-RPC
  Future<void> _showEmployeeInfoPopup(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
    );

    try {
      final employeeCode = widget.user.employeeCode ?? '';
      final odoo = OdooRpcService();

      // 🔔 โหลดข้อมูลพนักงาน + จำนวนใบเตือนพร้อมกัน
      final results = await Future.wait([
        odoo.getEmployeeInfo(employeeCode),
        odoo.getEmployeeWarningCount(employeeCode),
      ]);
      final data = results[0] as Map<String, dynamic>?;
      // null = ดึงไม่ได้ ใช้ยอดเดิมที่รู้ อย่าให้ badge หายเพราะเน็ตสะดุด
      final warnCount = (results[1] as int?) ?? _warningCount;

      if (!mounted) return;
      Navigator.of(context).pop();

      // อัพเดท count/badge จาก server จริง
      final prefs = await SharedPreferences.getInstance();
      final readCount =
          prefs.getInt('warning_read_count_$employeeCode') ?? 0;
      final unread =
          warnCount > readCount ? (warnCount - readCount) : 0;
      setState(() {
        _warningCount = warnCount;
        _unreadWarningCount = unread;
      });

      if (data != null) {
        _showEmployeeDataDialog(context, data);
      } else {
        _showErrorSnackbar(context, 'ไม่พบข้อมูลพนักงาน');
      }
    } on TimeoutException {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackbar(context, 'การเชื่อมต่อหมดเวลา');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackbar(context, 'เกิดข้อผิดพลาด: $e');
    }
  }

  // ===== ทวิ 50 ผ่าน JSON-RPC =====
  Future<void> _showWtCertPopup(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
    );

    try {
      final employeeCode = widget.user.employeeCode ?? '';
      final odoo = OdooRpcService();
      final certs = await odoo.getWtCertList(employeeCode);

      if (!mounted) return;
      Navigator.of(context).pop();

      if (certs.isEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            icon: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 48),
            title: Text('ไม่พบเอกสาร ทวิ50', style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.w600)),
            content: Text(
              'ยังไม่มีเอกสารหนังสือรับรองภาษีหัก ณ ที่จ่าย (ทวิ50)\nในระบบสำหรับคุณ',
              textAlign: TextAlign.center,
              style: GoogleFonts.ibmPlexSansThai(color: Colors.grey.shade600),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('ตกลง', style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
        return;
      }
      _showWtCertListDialog(context, certs);
    } on TimeoutException {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackbar(context, 'การเชื่อมต่อหมดเวลา');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackbar(context, 'เกิดข้อผิดพลาด: $e');
    }
  }

  void _showWtCertListDialog(BuildContext context, List certs) {
    final Color npdYellow = Theme.of(context).colorScheme.primary;
    const Color npdBlack = Color(0xFF1A1A1A);

    String formatMoney(dynamic value) {
      final num v = (value is num) ? value : double.tryParse(value.toString()) ?? 0;
      return v.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: npdYellow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.description_rounded, size: 28, color: npdBlack),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'เอกสาร ทวิ50',
                                style: GoogleFonts.ibmPlexSansThai(
                                  fontSize: 18, fontWeight: FontWeight.w600, color: npdBlack,
                                ),
                              ),
                              Text(
                                certs.length > 1
                                    ? 'ย้อนหลัง ${certs.length} ปี (ปีใหม่สุดอยู่บนสุด)'
                                    : 'แสดงทุกปีที่ฝ่ายบุคคลออกเอกสารให้แล้ว',
                                style: GoogleFonts.ibmPlexSansThai(
                                  fontSize: 12, color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Cert List
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: certs.length,
                      itemBuilder: (_, index) {
                        final cert = certs[index];
                        final lines = cert['lines'] as List? ?? [];
                        final totalBase = lines.fold<double>(0.0, (sum, l) => sum + ((l['base'] as num?)?.toDouble() ?? 0.0));
                        final totalTax = lines.fold<double>(0.0, (sum, l) => sum + ((l['amount'] as num?)?.toDouble() ?? 0.0));

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: npdYellow.withOpacity(0.5), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8, offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Year header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: npdYellow.withOpacity(0.15),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(15),
                                    topRight: Radius.circular(15),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, size: 18, color: npdBlack),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ปี ${cert['report_year'] ?? '-'}',
                                      style: GoogleFonts.ibmPlexSansThai(
                                        fontSize: 16, fontWeight: FontWeight.w600, color: npdBlack,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        cert['state'] == 'done' ? 'เสร็จสิ้น' : cert['state'] ?? '',
                                        style: GoogleFonts.ibmPlexSansThai(
                                          fontSize: 11, fontWeight: FontWeight.w500, color: Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Detail rows
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    _buildWtInfoRow('เลขที่', cert['name'] ?? '-'),
                                    _buildWtInfoRow('บริษัท', cert['company_name'] ?? '-'),
                                    _buildWtInfoRow('เลขผู้เสียภาษี', cert['employee_taxid'] ?? '-'),
                                    const Divider(),
                                    _buildWtInfoRow('รายได้รวมทั้งปี', '${formatMoney(totalBase)} บาท', bold: true),
                                    _buildWtInfoRow('ภาษีหัก ณ ที่จ่าย', '${formatMoney(totalTax)} บาท', bold: true, isRed: true),
                                    // ยอดกองทุนตามที่ระบุบนหนังสือรับรองฯ (ใช้ยื่นภาษีเพื่อลดหย่อน)
                                    _buildWtInfoRow('กองทุนประกันสังคม (ทั้งปี)',
                                        '${formatMoney(cert['sso_amount'])} บาท'),
                                    _buildWtInfoRow('กองทุนสำรองเลี้ยงชีพ (ทั้งปี)',
                                        '${formatMoney(cert['provident_fund_amount'])} บาท'),
                                    const SizedBox(height: 12),
                                    // Download PDF button
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _downloadWtCertPdf(cert['id'], cert['report_year'] ?? ''),
                                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                                        label: Text('ดาวน์โหลด PDF ทวิ50', style: GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.w600)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: npdYellow,
                                          foregroundColor: npdBlack,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWtInfoRow(String label, String value, {bool bold = false, bool isRed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.ibmPlexSansThai(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: isRed ? Colors.red.shade700 : const Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadWtCertPdf(dynamic certId, String year) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
    );

    try {
      final odoo = OdooRpcService();
      final pdfBytes = await odoo.getWtCertPdfBytes(certId is int ? certId : int.parse(certId.toString()));

      if (!mounted) return;
      Navigator.of(context).pop();

      if (pdfBytes != null) {
        final dir = await getTemporaryDirectory();
        final filename = 'WT_Cert_$year.pdf';
        final filePath = '${dir.path}/$filename';
        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);

        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          if (mounted) _showErrorSnackbar(context, 'ไม่สามารถเปิดไฟล์ PDF ได้: ${result.message}');
        }
      } else {
        if (mounted) _showErrorSnackbar(context, 'ไม่สามารถสร้าง PDF ได้');
      }
    } on TimeoutException {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackbar(context, 'การดาวน์โหลดหมดเวลา');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorSnackbar(context, 'เกิดข้อผิดพลาด: $e');
    }
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.ibmPlexSansThai()),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showEmployeeDataDialog(BuildContext context, Map<String, dynamic> emp) {
    final Color npdYellow = Theme.of(context).colorScheme.primary;
    const Color npdBlack = Color(0xFF1A1A1A);

    String formatMoney(dynamic value) {
      final num v = (value is num) ? value : double.tryParse(value.toString()) ?? 0;
      return v.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: npdYellow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.person_rounded, size: 28, color: npdBlack),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${emp['prefix_th'] ?? ''} ${emp['firstname'] ?? ''} ${emp['lastname'] ?? ''}',
                                style: GoogleFonts.ibmPlexSansThai(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: npdBlack,
                                ),
                              ),
                              Text(
                                'รหัส: ${emp['employee_code'] ?? '-'}',
                                style: GoogleFonts.ibmPlexSansThai(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // 🔔 ใบเตือนพนักงาน (แสดงด้านบนสุด)
                        _buildSectionHeader(
                            'ใบเตือน', Icons.warning_amber_rounded),
                        const SizedBox(height: 12),
                        if (_warningCount > 0)
                          _buildWarningAlertCard(ctx, _warningCount)
                        else
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: Colors.green.shade600),
                                const SizedBox(width: 10),
                                Text('ไม่มีใบเตือน',
                                    style: GoogleFonts.ibmPlexSansThai(
                                        color: Colors.green.shade800,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),

                        // ข้อมูลองค์กร
                        _buildSectionHeader('ข้อมูลองค์กร', Icons.business_rounded),
                        const SizedBox(height: 12),
                        _buildInfoRow('แผนก', emp['department']),
                        _buildInfoRow('ตำแหน่ง', emp['position']),
                        _buildInfoRow('บริษัท', emp['company']),
                        _buildInfoRow('สาขา', emp['branch']),
                        _buildInfoRow('ประเภทพนักงาน', emp['employee_type']),

                        const SizedBox(height: 24),
                        _buildSectionHeader('ข้อมูลค่าตอบแทน', Icons.payments_rounded),
                        const SizedBox(height: 12),
                        _buildInfoRow('ค่าจ้าง', '${formatMoney(emp['salary'])} บาท', highlight: true),
                        _buildInfoRow('เงินค่าครองชีพ', '${formatMoney(emp['cost_of_living'])} บาท'),
                        _buildInfoRow('เงินประจำตำแหน่ง', '${formatMoney(emp['position_allowance'])} บาท'),
                        _buildInfoRow('เงินค่าประสบการณ์', '${formatMoney(emp['experience_allowance'])} บาท'),
                        _buildInfoRow('เงินค่าวิชาชีพ', '${formatMoney(emp['professional_fee'])} บาท'),
                        _buildInfoRow('เงินเบิกล่วงหน้า', emp['advance_amount']),
                        _buildInfoRow('วงเงินเบิกล่วงหน้า', '${formatMoney(emp['advance_limit'])} บาท'),

                        const SizedBox(height: 24),
                        _buildSectionHeader('ข้อมูลส่วนตัว', Icons.badge_rounded),
                        const SizedBox(height: 12),
                        _buildInfoRow('ชื่อเล่น', emp['nickname']),
                        _buildInfoRow('ชื่อ (ENG)', emp['firstname_eng']),
                        _buildInfoRow('นามสกุล (ENG)', emp['lastname_eng']),
                        _buildInfoRow('เพศ', emp['gender']),
                        _buildInfoRow('สัญชาติ', emp['nationality']),
                        _buildInfoRow('สถานะ', emp['marital_status']),
                        _buildInfoRow('วันเกิด', emp['birthdate']),
                        _buildInfoRow('อายุ', emp['age'] != null && emp['age'] != 0 ? '${emp['age']} ปี' : ''),
                        _buildInfoRow('เบอร์โทร', emp['phone_number']),
                        _buildInfoRow('อีเมล', emp['email']),
                        _buildInfoRow('เลขประจำตัวประชาชน', emp['id_card_number']),
                        _buildInfoRow('เลขที่หนังสือเดินทาง', emp['passport_number']),
                        _buildInfoRow('ประกันสังคม', emp['social_security_number']),

                        const SizedBox(height: 24),
                        _buildSectionHeader('ที่อยู่', Icons.home_rounded),
                        const SizedBox(height: 12),
                        _buildInfoRow('ที่อยู่', emp['address']),

                        const SizedBox(height: 24),
                        _buildSectionHeader('ข้อมูลการทำงาน', Icons.work_rounded),
                        const SizedBox(height: 12),
                        _buildInfoRow('วันที่เริ่มงาน', emp['start_date']),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// การ์ดแจ้งเตือนใบเตือน พร้อมปุ่มเปิดหน้าใบเตือน
  Widget _buildWarningAlertCard(BuildContext dialogCtx, int count) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'คุณมีใบเตือนในระบบ',
                      style: GoogleFonts.ibmPlexSansThai(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'จำนวน $count รายการ',
                      style: GoogleFonts.ibmPlexSansThai(
                          fontSize: 13, color: Colors.red.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                // ✅ เมื่อเปิดหน้าใบเตือน ให้ mark ว่าอ่านแล้ว + ยกเลิกแจ้งเตือน
                await _markWarningsAsRead();
                if (!mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmployeeWarningScreen(
                      employeeCode: widget.user.employeeCode ?? '',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                'ดูรายละเอียดใบเตือน',
                style:
                    GoogleFonts.ibmPlexSansThai(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.ibmPlexSansThai(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, dynamic value, {bool highlight = false}) {
    final displayValue = (value == null || value.toString().isEmpty) ? '-' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 14,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
                color: highlight ? const Color(0xFF1A1A1A) : const Color(0xFF333333),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // เมนูของที่ปรึกษา — มีแค่สลิปเงินเดือน
  Widget _buildConsultantMenuGrid(BuildContext context) {
    return _menuGrid([
      _ActionCard(
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF1565C0),
        title: 'สลิปเงินเดือน',
        subtitle: 'ดูสลิปย้อนหลัง',
        onTap: () {
          // ที่ปรึกษามีสลิปเป็นแท็บบนแถบเมนูล่าง — สลับแท็บแทนการเปิดหน้าซ้อน
          final shell = context.findAncestorStateOfType<_MainAppScreenState>();
          final int payslipIndex =
              shell?._pages.indexWhere((page) => page is PayslipScreen) ?? -1;
          if (shell != null && payslipIndex != -1) {
            shell._onItemTapped(payslipIndex);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PayslipScreen(user: widget.user),
              ),
            );
          }
        },
      ),
    ]);
  }

  // Helper widget to build the approver section
  Widget _buildApproverSection() {
    final int leaveCount = _asCount(_menuData?['pending_leave_count']);
    final int addTimeCount = _asCount(_menuData?['pending_addtime_count']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader('สำหรับผู้อนุมัติ'),
        _menuGrid([
          _ActionCard(
            icon: Icons.event_available_rounded,
            color: const Color(0xFF0277BD),
            title: 'อนุมัติการลา',
            subtitle:
                leaveCount > 0 ? '$leaveCount คำขอรออนุมัติ' : 'ไม่มีคำขอค้าง',
            badge: leaveCount > 0 ? '$leaveCount' : null,
            onTap: () {
              // 🔔 mark as seen + ยกเลิกแจ้งเตือน
              markApproverLeaveAsSeen();
              _openApprovalsTab(0, (_) => ApproveLeaveScreen(user: widget.user));
            },
          ),
          _ActionCard(
            icon: Icons.more_time_rounded,
            color: const Color(0xFF00695C),
            title: 'อนุมัติเพิ่มเวลา',
            subtitle: addTimeCount > 0
                ? '$addTimeCount คำขอรออนุมัติ'
                : 'ไม่มีคำขอค้าง',
            badge: addTimeCount > 0 ? '$addTimeCount' : null,
            onTap: () {
              // 🔔 mark as seen + ยกเลิกแจ้งเตือน
              markApproverAddTimeAsSeen();
              _openApprovalsTab(
                  1, (_) => ApproveAddTimeScreen(user: widget.user));
            },
          ),
        ]),
      ],
    );
  }

  /// เปิดหน้าอนุมัติตรงแท็บที่ต้องการ — ถ้าไม่มีแถบเมนูล่าง (หน้าแรกเปิดเดี่ยว) เปิดเป็นหน้าใหม่
  void _openApprovalsTab(int tab, WidgetBuilder fallback) {
    final shell = context.findAncestorStateOfType<_MainAppScreenState>();
    if (shell != null &&
        shell._pages.any((page) => page is ApprovalsHubScreen)) {
      shell._openApprovals(tab);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: fallback));
    }
  }

  // Helper widget to build the check-in history list
  Widget _buildHistoryList() {
    final List history = _menuData?['checkin_history'] ?? [];
    if (history.isEmpty) {
      return AppPanel(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_rounded,
                size: 36, color: AppColors.textFaint),
            const SizedBox(height: 8),
            Text(
              'ยังไม่มีการลงเวลาใน 3 วันล่าสุด',
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
          ],
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

        Map<String, dynamic>? currentIn;
        for (var entry in entriesForDate) {
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
              unmatchedEntries.add(entry);
            }
          }
        }
        if (currentIn != null) {
          pairedEntries.add({'in': currentIn, 'out': null});
        }
        for (var unmatched in unmatchedEntries) {
          pairedEntries.add({'in': null, 'out': unmatched});
        }

        pairedEntries.sort((a, b) {
          String? timeA =
              a['in']?['full_datetime'] ?? a['out']?['full_datetime'];
          String? timeB =
              b['in']?['full_datetime'] ?? b['out']?['full_datetime'];
          if (timeA == null || timeB == null) return 0;
          return timeA.compareTo(timeB);
        });

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppPanel(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display the date (e.g., "24 กรกฎาคม 2025")
                Text(
                  _formatDateForHistory(currentDate),
                  style: GoogleFonts.ibmPlexSansThai(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                // Display each paired check-in/out entry for this date
                ...(() {
                  final info = _lateMinutes[currentDate];
                  final lateRow = lateRowIndexFor(pairedEntries, info);
                  return pairedEntries.asMap().entries.map((e) {
                    final pair = e.value;
                    return _CheckInOutPairCard(
                      inTime: pair['in']?['work_time'],
                      outTime: pair['out']?['work_time'],
                      lateMinutes: e.key == lateRow ? info?.minutes : null,
                    );
                  }).toList();
                })(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// การ์ดเมนูบนหน้าแรก — ไอคอนสีเฉพาะเมนู ชื่อ และคำอธิบายสั้น
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// ตัวเลขสีแดงมุมขวาบน เช่นจำนวนคำขอที่รออนุมัติ
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.frame(Theme.of(context).colorScheme.primary),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge!,
                        style: GoogleFonts.ibmPlexSansThai(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ibmPlexSansThai(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: AppColors.text,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ibmPlexSansThai(
                  fontSize: 11.5,
                  height: 1.3,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// สถานะการลงเวลาของวันนี้ ที่หน้าแรกสรุปจากประวัติ
class _TodayStatus {
  const _TodayStatus({this.firstIn, this.lastOut, this.lastType});

  final String? firstIn;
  final String? lastOut;

  /// 'in' / 'out' / null (วันนี้ยังไม่ลงเวลา)
  final String? lastType;

  bool get isWorking => lastType == 'in';
}

/// ช่องเวลาเข้างาน/ออกงานบนการ์ด "วันนี้"
class _TimeStat extends StatelessWidget {
  const _TimeStat({
    required this.icon,
    required this.label,
    required this.time,
    required this.color,
    this.note,
  });

  final IconData icon;
  final String label;
  final String? time;
  final Color color;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final String? value = time;
    final bool hasTime = value != null && value.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: hasTime ? color : AppColors.textFaint),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.ibmPlexSansThai(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasTime ? '${_hhmm(value)} น.' : '--:--',
            style: GoogleFonts.ibmPlexSansThai(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: hasTime ? AppColors.text : AppColors.textFaint,
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

/// "08:02:15" → "08:02" (เวลาจากระบบอาจมีวินาทีติดมา)
String _hhmm(String time) =>
    time.length > 5 && time[2] == ':' ? time.substring(0, 5) : time;

/// "สาย 22 นาที" / "สาย 1 ชม 5 นาที"
String _lateLabel(int minutes) {
  if (minutes < 60) return 'สาย $minutes นาที';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? 'สาย $h ชม' : 'สาย $h ชม $m นาที';
}

/// ตัวเลขจำนวนจาก JSON — กันกรณีเซิร์ฟเวอร์ส่งมาเป็นสตริงหรือ null
int _asCount(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

/// "YYYY-MM-DD" แบบเดียวกับ work_date ที่ระบบส่งมา
String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class RealTimeClock extends StatefulWidget {
  const RealTimeClock({super.key, this.trailing});

  /// วางไว้ท้ายบรรทัดเวลา เช่นป้ายสถานะการทำงานของวันนี้
  final Widget? trailing;

  @override
  State<RealTimeClock> createState() => _RealTimeClockState();
}

class _RealTimeClockState extends State<RealTimeClock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEEที่ d MMMM yyyy', 'th').format(_now),
          style: GoogleFonts.ibmPlexSansThai(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
        Row(
          children: [
            Text(
              DateFormat('HH:mm:ss').format(_now),
              style: GoogleFonts.ibmPlexSansThai(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: AppColors.text,
                // ตัวเลขกว้างเท่ากัน วินาทีเดินแล้วตัวหนังสือไม่ขยับไปมา
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ],
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
            style: GoogleFonts.ibmPlexSansThai(
              fontSize: 22,
              color: onBackground,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'กำลังอยู่ในระหว่างการพัฒนา',
            style: GoogleFonts.ibmPlexSansThai(fontSize: 15, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

/// หาว่าใน 1 วัน ควรแสดงข้อความ "สาย" ที่แถวไหน
///
/// วันหนึ่งสแกนเข้าได้หลายครั้ง แต่ระบบคิดสายจาก "ครั้งแรกของวัน" ครั้งเดียว
/// จึงต้องแปะข้อความแค่แถวนั้น ไม่ใช่ทุกแถว (ไม่งั้นเข้า 09:52 กับ 10:28
/// จะขึ้นสายเท่ากันทั้งคู่ ซึ่งผิด)
///
/// จับคู่ด้วยเวลาเข้าที่ Odoo ใช้คำนวณก่อน — ถ้าไม่ตรงสักแถว
/// (เช่นถูก manual_time_log แก้เวลา) ค่อยตกมาใช้แถวแรกที่มีการเข้างาน
int lateRowIndexFor(List<Map<String, dynamic>> pairs, LateInfo? info) {
  if (info == null) return -1;
  if (info.checkin.isNotEmpty) {
    for (int i = 0; i < pairs.length; i++) {
      if (pairs[i]['in']?['work_time'] == info.checkin) return i;
    }
  }
  for (int i = 0; i < pairs.length; i++) {
    if (pairs[i]['in'] != null) return i;
  }
  return -1;
}

class _CheckInOutPairCard extends StatelessWidget {
  final String? inTime;
  final String? outTime;

  /// นาทีที่สายของวันนั้น — มาจากสูตรที่ตั้งไว้ใน Odoo (ไม่ได้คำนวณในแอป)
  /// null หรือ 0 = ไม่สาย → ไม่แสดงข้อความอะไรเลย
  final int? lateMinutes;

  const _CheckInOutPairCard({
    Key? key,
    required this.inTime,
    required this.outTime,
    this.lateMinutes,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TimeEntryBubble(
                  label: 'เข้า',
                  time: inTime ?? '-',
                  isCheckIn: true,
                  showIcon: inTime != null,
                ),
                // สายกี่นาที — วางใต้เวลาเข้างาน แสดงเฉพาะวันที่สายจริง
                if (inTime != null && (lateMinutes ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 38),
                    child: Text(
                      _lateLabel(lateMinutes!),
                      style: GoogleFonts.ibmPlexSansThai(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
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

  /// มีเวลาจริงไหม — ไม่มีจะแสดงเป็น "--:--" สีจาง
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
    final Color tone = showIcon
        ? (isCheckIn ? AppColors.success : AppColors.danger)
        : AppColors.textFaint;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
            size: 16,
            color: tone,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.ibmPlexSansThai(
                  fontSize: 11.5,
                  height: 1.2,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                showIcon ? '${_hhmm(time)} น.' : '--:--',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ibmPlexSansThai(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: showIcon ? AppColors.text : AppColors.textFaint,
                ),
              ),
            ],
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

  /// ข้อมูลสายรายวัน — ดึงจาก Odoo ตามสูตรที่ตั้งไว้
  Map<String, LateInfo> _lateMinutes = {};

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
          // ✅ ดึงนาทีสายตามสูตรใน Odoo (ล้มเหลวก็แค่ไม่แสดงข้อความ ไม่ทำให้หน้าพัง)
          final late = await OdooRpcService().getLateMinutes(
              widget.user.employeeCode ?? '', _selectedMonth, _selectedYear);
          if (mounted) setState(() => _lateMinutes = late);
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
      appBar: AppGradientBar(
        title: Text('ประวัติการลงเวลาทั้งหมด', style: GoogleFonts.ibmPlexSansThai()),
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
                      border: Border.all(color: AppColors.frame(Theme.of(context).colorScheme.primary)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedMonth,
                        isExpanded: true,
                        style: GoogleFonts.ibmPlexSansThai(fontSize: 14, color: Colors.black),
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
                    border: Border.all(color: AppColors.frame(Theme.of(context).colorScheme.primary)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedYear,
                      style: GoogleFonts.ibmPlexSansThai(fontSize: 14, color: Colors.black),
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
                  style: GoogleFonts.ibmPlexSansThai(fontSize: 14, color: Colors.grey.shade600),
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
                            Text(_errorMessage, style: GoogleFonts.ibmPlexSansThai(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _fetchCheckinHistory,
                              icon: const Icon(Icons.refresh),
                              label: Text('ลองอีกครั้ง', style: GoogleFonts.ibmPlexSansThai()),
                            ),
                          ],
                        ),
                      )
                    : _checkinHistory.isEmpty
                        ? Center(
                            child: Text(
                              'ไม่มีข้อมูลการลงเวลาในเดือนนี้',
                              style: GoogleFonts.ibmPlexSansThai(fontSize: 16, color: Colors.grey),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: AppColors.frame(Theme.of(context).colorScheme.primary)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Header
                Text(
                  _formatDate(date),
                  style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const Divider(),
                // แสดงคู่ เข้า-ออก แบบเดียวกับหน้าหลัก
                ...(() {
                  final info = _lateMinutes[date];
                  final lateRow = lateRowIndexFor(pairedEntries, info);
                  return pairedEntries.asMap().entries.map((e) {
                    final pair = e.value;
                    return _CheckInOutPairCard(
                      inTime: pair['in']?['work_time'],
                      outTime: pair['out']?['work_time'],
                      lateMinutes: e.key == lateRow ? info?.minutes : null,
                    );
                  }).toList();
                })(),
              ],
            ),
          ),
        );
      },
    );
  }
}
