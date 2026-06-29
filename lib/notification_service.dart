import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'odoo_rpc_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ✅ SharedPreferences keys สำหรับ cache วันหยุดบริษัท
  static const String _kHolidayCacheKey = 'company_holiday_cache_v1';
  static const String _kHolidayCacheDateKey = 'company_holiday_cache_date_v1';
  // ต่ออายุ cache ทุก 24 ชม. (fallback: ใช้ cache เดิมถ้าโหลดล้มเหลว)
  static const Duration _holidayCacheTtl = Duration(hours: 24);

  /// เริ่มต้น notification service
  Future<void> init() async {
    if (_initialized) return;

    // ตั้งค่า timezone
    tz_data.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));
    }

    // ตั้งค่า notification
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    // ขอสิทธิ์แจ้งเตือน (Android 13+)
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
    }

    _initialized = true;
    debugPrint('✅ NotificationService initialized');
  }

  /// ✅ โหลดวันหยุดบริษัทจาก Odoo แล้ว cache ลง SharedPreferences
  /// Cache 24 ชม. — fail-open (ถ้าโหลดไม่ได้ใช้ cache เดิม)
  Future<Set<String>> _loadAndCacheHolidays() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cacheDateStr = prefs.getString(_kHolidayCacheDateKey);
    final cachedJson = prefs.getString(_kHolidayCacheKey);

    // ตรวจว่า cache ยังสดอยู่หรือเปล่า
    bool cacheValid = false;
    if (cacheDateStr != null) {
      final cacheDate = DateTime.tryParse(cacheDateStr);
      if (cacheDate != null && now.difference(cacheDate) < _holidayCacheTtl) {
        cacheValid = true;
      }
    }

    if (cacheValid && cachedJson != null) {
      try {
        final List list = json.decode(cachedJson);
        return list.cast<String>().toSet();
      } catch (_) {
        // fallthrough to refresh
      }
    }

    // refresh
    try {
      final odoo = OdooRpcService();
      final thisYear = await odoo.getCompanyHolidays(year: now.year);
      final nextYear = await odoo.getCompanyHolidays(year: now.year + 1);
      final allDates = <String>{
        ...thisYear.map(_toDateKey),
        ...nextYear.map(_toDateKey),
      };
      await prefs.setString(_kHolidayCacheKey, json.encode(allDates.toList()));
      await prefs.setString(_kHolidayCacheDateKey, now.toIso8601String());
      debugPrint('🏝️ Cached ${allDates.length} company holidays');
      return allDates;
    } catch (e) {
      debugPrint('⚠️ Load holidays failed ($e) → use cache if any');
      if (cachedJson != null) {
        try {
          final List list = json.decode(cachedJson);
          return list.cast<String>().toSet();
        } catch (_) {}
      }
      return <String>{};
    }
  }

  String _toDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// เช็คว่าวันที่กำหนดเป็นวันหยุดบริษัทหรือไม่ (ใช้ cache)
  Future<bool> _isHoliday(DateTime d) async {
    final holidays = await _loadAndCacheHolidays();
    return holidays.contains(_toDateKey(d));
  }

  /// ดึงตารางงานจาก Odoo ผ่าน JSON-RPC แล้วตั้งแจ้งเตือน
  /// เช็คจากประวัติลงเวลา - ถ้าลงแล้วจะไม่แจ้งเตือน
  Future<void> scheduleWorkNotifications({
    required String employeeCode,
    required String employeeName,
    String odooBaseUrl = '',
  }) async {
    try {
      final odoo = OdooRpcService();
      final scheduleData = await odoo.getWorkSchedule(employeeCode);

      if (scheduleData == null) {
        debugPrint('❌ ไม่พบตารางงาน');
        return;
      }

      final String category = scheduleData['category'] ?? '';
      final List days = scheduleData['days'] ?? [];

      if (category == 'no_checkin' || days.isEmpty) {
        await cancelAllNotifications();
        debugPrint('ℹ️ ไม่ต้องเช็คอิน - ยกเลิกแจ้งเตือนทั้งหมด');
        return;
      }

      // ยกเลิกแจ้งเตือนเก่าทั้งหมดก่อนตั้งใหม่
      await cancelAllNotifications();

      // ✅ โหลดวันหยุดบริษัทไว้ก่อน (cache) — ใช้ข้าม scheduled notifications
      final holidays = await _loadAndCacheHolidays();

      const dayToWeekday = {
        'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
        'friday': 5, 'saturday': 6, 'sunday': 7,
      };

      // สร้าง map: weekday (1-7) → schedule
      final Map<int, Map<String, dynamic>> weekdaySchedule = {};
      for (final day in days) {
        final String dayName = day['day'] ?? '';
        final int weekday = dayToWeekday[dayName] ?? 0;
        if (weekday == 0 || weekday == 7) continue; // ข้ามวันอาทิตย์
        weekdaySchedule[weekday] = Map<String, dynamic>.from(day);
      }

      // ✅ ตั้งแจ้งเตือนแบบ one-shot สำหรับอีก 14 วันข้างหน้า
      // ข้ามวันอาทิตย์ + วันหยุดบริษัท
      int notifId = 100;
      int scheduledCount = 0;
      int skippedHolidayCount = 0;
      final now = DateTime.now();

      for (int dayOffset = 0; dayOffset < 14; dayOffset++) {
        final targetDate = DateTime(now.year, now.month, now.day)
            .add(Duration(days: dayOffset));
        final weekday = targetDate.weekday;

        // ไม่มีตารางวันนี้ (วันหยุดประจำสัปดาห์)
        final sched = weekdaySchedule[weekday];
        if (sched == null) continue;

        // ✅ ข้ามวันหยุดบริษัท
        final dateKey = _toDateKey(targetDate);
        if (holidays.contains(dateKey)) {
          skippedHolidayCount++;
          debugPrint('🏝️ Skip $dateKey (company holiday)');
          continue;
        }

        final double startHourRaw = (sched['start_hour'] ?? 0).toDouble();
        final double endHourRaw = (sched['end_hour'] ?? 0).toDouble();

        final int startHour = startHourRaw.floor();
        final int startMin = ((startHourRaw - startHour) * 60).round();
        final int endHour = endHourRaw.floor();
        final int endMin = ((endHourRaw - endHour) * 60).round();

        final String shiftStart =
            '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
        final String shiftEnd =
            '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';

        // เวลาแจ้งเตือนเข้างาน: ก่อน 2 นาที
        final checkinAlert = DateTime(targetDate.year, targetDate.month,
                targetDate.day, startHour, startMin)
            .subtract(const Duration(minutes: 2));
        // เวลาแจ้งเตือนออกงาน: หลัง 1 นาที
        final checkoutAlert = DateTime(targetDate.year, targetDate.month,
                targetDate.day, endHour, endMin)
            .add(const Duration(minutes: 1));

        // ข้ามเวลาที่ผ่านมาแล้ว
        if (checkinAlert.isAfter(now)) {
          await _scheduleOneShotNotification(
            id: notifId++,
            title: 'ใกล้ถึงเวลาเข้างานแล้ว!',
            body:
                'คุณ$employeeName อย่าลืมลงเวลาเข้างาน เวลา $shiftStart น.',
            when: checkinAlert,
          );
          scheduledCount++;
        }

        if (checkoutAlert.isAfter(now)) {
          await _scheduleOneShotNotification(
            id: notifId++,
            title: 'ถึงเวลาเลิกงานแล้ว!',
            body: 'คุณ$employeeName อย่าลืมลงเวลาออกงาน เวลา $shiftEnd น.',
            when: checkoutAlert,
          );
          scheduledCount++;
        }
      }

      // บันทึกว่าตั้งแจ้งเตือนแล้ว
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastScheduleSync', DateTime.now().toIso8601String());
      await prefs.setString('scheduleData', json.encode(scheduleData));
      await prefs.setString('employeeName', employeeName);

      debugPrint(
          '🔔 ตั้งแจ้งเตือน $scheduledCount รายการ สำหรับ $employeeName (ข้าม ${skippedHolidayCount} วันหยุดบริษัท + วันอาทิตย์)');

    } catch (e) {
      debugPrint('❌ Error scheduling notifications: $e');
    }
  }

  /// เช็คว่าวันนี้ลงเวลาแล้วหรือยัง แล้วแจ้งเตือนถ้ายังไม่ลงเวลา
  /// เรียกจาก HomePage timer ทุก 15 วินาที
  Future<void> checkAndNotify({
    required String employeeCode,
    required String employeeName,
    required List<dynamic> checkinHistory,
  }) async {
    if (!_initialized) return;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // วันอาทิตย์ (weekday=7) ไม่ต้องแจ้งเตือน
    if (now.weekday == 7) return;

    // ✅ วันหยุดบริษัท (จาก Odoo payroll.holiday) ไม่ต้องแจ้งเตือน
    if (await _isHoliday(now)) {
      debugPrint('🏝️ Today ($todayStr) is a company holiday — skip notification');
      return;
    }

    // ดูประวัติลงเวลาวันนี้
    bool hasCheckinToday = false;
    bool hasCheckoutToday = false;

    for (final entry in checkinHistory) {
      if (entry['work_date'] == todayStr) {
        if (entry['check_type'] == 'in') hasCheckinToday = true;
        if (entry['check_type'] == 'out') hasCheckoutToday = true;
      }
    }

    // ดึงตารางงานจาก cache
    final prefs = await SharedPreferences.getInstance();
    final scheduleJson = prefs.getString('scheduleData');
    if (scheduleJson == null) return;

    final scheduleData = json.decode(scheduleJson);
    final List days = scheduleData['days'] ?? [];

    // หาตารางงานของวันนี้
    const weekdayToDay = {
      1: 'monday', 2: 'tuesday', 3: 'wednesday', 4: 'thursday',
      5: 'friday', 6: 'saturday', 7: 'sunday',
    };
    final todayDayName = weekdayToDay[now.weekday] ?? '';

    Map<String, dynamic>? todaySchedule;
    for (final day in days) {
      if (day['day'] == todayDayName) {
        todaySchedule = Map<String, dynamic>.from(day);
        break;
      }
    }

    if (todaySchedule == null) return; // วันนี้ไม่ต้องทำงาน

    final double startHourRaw = (todaySchedule['start_hour'] ?? 0).toDouble();
    final double endHourRaw = (todaySchedule['end_hour'] ?? 0).toDouble();

    final int startHour = startHourRaw.floor();
    final int startMin = ((startHourRaw - startHour) * 60).round();
    final int endHour = endHourRaw.floor();
    final int endMin = ((endHourRaw - endHour) * 60).round();

    final String shiftStart = '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
    final String shiftEnd = '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';

    final startTime = DateTime(now.year, now.month, now.day, startHour, startMin);
    final endTime = DateTime(now.year, now.month, now.day, endHour, endMin);

    // เช็คเข้างาน: ก่อน 2 นาที ถึงเวลาเข้างาน + ยังไม่ได้ลงเวลาเข้า
    final checkinAlertTime = startTime.subtract(const Duration(minutes: 2));
    if (!hasCheckinToday &&
        now.isAfter(checkinAlertTime) &&
        now.isBefore(startTime.add(const Duration(minutes: 30)))) {
      // เช็คว่าแจ้งเตือนแล้วหรือยัง (ไม่ซ้ำทุก 15 วินาที)
      final lastCheckinAlert = prefs.getString('lastCheckinAlert_$todayStr');
      if (lastCheckinAlert == null) {
        await showInstantNotification(
          title: 'ใกล้ถึงเวลาเข้างานแล้ว!',
          body: 'คุณ$employeeName อย่าลืมลงเวลาเข้างาน เวลา $shiftStart น.',
        );
        await prefs.setString('lastCheckinAlert_$todayStr', now.toIso8601String());
        debugPrint('🔔 แจ้งเตือนเข้างาน - ยังไม่ได้ลงเวลา');
      }
    }

    // เช็คออกงาน: หลังเวลาออกงาน 1 นาที + ยังไม่ได้ลงเวลาออก + ต้องลงเวลาเข้าแล้ว
    final checkoutAlertTime = endTime.add(const Duration(minutes: 1));
    if (hasCheckinToday && !hasCheckoutToday &&
        now.isAfter(checkoutAlertTime) &&
        now.isBefore(endTime.add(const Duration(hours: 3)))) {
      final lastCheckoutAlert = prefs.getString('lastCheckoutAlert_$todayStr');
      if (lastCheckoutAlert == null) {
        await showInstantNotification(
          title: 'ถึงเวลาเลิกงานแล้ว!',
          body: 'คุณ$employeeName อย่าลืมลงเวลาออกงาน เวลา $shiftEnd น.',
        );
        await prefs.setString('lastCheckoutAlert_$todayStr', now.toIso8601String());
        debugPrint('🔔 แจ้งเตือนออกงาน - ยังไม่ได้ลงเวลาออก');
      }
    }
  }

  /// ✅ ตั้งแจ้งเตือนแบบยิงครั้งเดียว (one-shot) ที่เวลาที่กำหนด
  Future<void> _scheduleOneShotNotification({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final tzWhen = tz.TZDateTime.from(when, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzWhen,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'work_checkin_channel',
          'แจ้งเตือนลงเวลา',
          channelDescription: 'แจ้งเตือนเข้า-ออกงาน',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFFFD600),
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: 'NPD HRMS',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // ไม่ตั้ง matchDateTimeComponents → one-shot (ไม่ทวนซ้ำ)
    );

    debugPrint(
        '📅 ตั้งแจ้งเตือน #$id: ${when.toIso8601String()} — $title');
  }

  /// ตั้งแจ้งเตือนรายสัปดาห์ (ทุกวันจันทร์, อังคาร ฯลฯ) — DEPRECATED
  Future<void> _scheduleWeeklyNotification({
    required int id,
    required String title,
    required String body,
    required int weekday, // 1=จันทร์ ... 7=อาทิตย์
    required int hour,
    required int minute,
  }) async {
    // แปลง weekday จาก ISO (1=จันทร์) → Dart DateTime (1=จันทร์ เหมือนกัน)
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = _nextInstanceOfWeekday(weekday, hour, minute);

    // ถ้าเวลาอยู่ในอดีต (ผ่านไปแล้วในสัปดาห์นี้) ให้ข้ามไปสัปดาห์หน้า
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'work_checkin_channel',
          'แจ้งเตือนลงเวลา',
          channelDescription: 'แจ้งเตือนเข้า-ออกงาน',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',

          color: const Color(0xFFFFD600),
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: 'NPD HRMS',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );

    final dayNames = ['', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];
    debugPrint('📅 ตั้งแจ้งเตือน #$id: วัน${dayNames[weekday]} ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} - $title');
  }

  /// หาวันถัดไปที่ตรงกับ weekday + เวลา
  tz.TZDateTime _nextInstanceOfWeekday(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    // หาวันที่ตรงกับ weekday
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  // ===== 🧪 ฟังก์ชันทดสอบ =====

  /// ทดสอบแจ้งเตือนเข้างาน (แจ้งเตือนใน 5 วินาที)
  Future<void> testCheckinNotification(String employeeName) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));

    await _plugin.zonedSchedule(
      9990,
      'ใกล้ถึงเวลาเข้างานแล้ว!',
      'คุณ$employeeName อย่าลืมลงเวลาเข้างาน เวลา 08:00 น.',
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'work_checkin_channel',
          'แจ้งเตือนลงเวลา',
          channelDescription: 'แจ้งเตือนเข้า-ออกงาน',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',

          color: const Color(0xFFFFD600),
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            'คุณ$employeeName อย่าลืมลงเวลาเข้างาน เวลา 08:00 น.',
            contentTitle: 'ใกล้ถึงเวลาเข้างานแล้ว!',
            summaryText: 'NPD HRMS',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    debugPrint('🧪 ทดสอบแจ้งเตือนเข้างาน - จะแจ้งใน 5 วินาที');
  }

  /// ทดสอบแจ้งเตือนออกงาน (แจ้งเตือนใน 5 วินาที)
  Future<void> testCheckoutNotification(String employeeName) async {
    final scheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));

    await _plugin.zonedSchedule(
      9991,
      'ถึงเวลาเลิกงานแล้ว!',
      'คุณ$employeeName อย่าลืมลงเวลาออกงาน เวลา 17:00 น.',
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'work_checkin_channel',
          'แจ้งเตือนลงเวลา',
          channelDescription: 'แจ้งเตือนเข้า-ออกงาน',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',

          color: const Color(0xFFFFD600),
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            'คุณ$employeeName อย่าลืมลงเวลาออกงาน เวลา 17:00 น.',
            contentTitle: 'ถึงเวลาเลิกงานแล้ว!',
            summaryText: 'NPD HRMS',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    debugPrint('🧪 ทดสอบแจ้งเตือนออกงาน - จะแจ้งใน 5 วินาที');
  }

  /// แจ้งเตือนทันที (สำหรับทดสอบ)
  Future<void> showInstantNotification({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      9999,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'work_reminder_channel',
          'แจ้งเตือนเข้า-ออกงาน',
          channelDescription: 'แจ้งเตือนเวลาเข้า-ออกงาน',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFFFD600),
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: 'NPD HRMS',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    debugPrint('ส่งแจ้งเตือนทดสอบ: $title');
  }

  /// แจ้งเตือนอัปเดตเวอร์ชันใหม่ (แสดงที่หน้ามือถือทันที)
  Future<void> showUpdateNotification(String latestVersion) async {
    await _plugin.show(
      8888,
      'NPD HRMS มีเวอร์ชันใหม่!',
      'เวอร์ชัน $latestVersion พร้อมใช้งานแล้ว กรุณาอัปเดต',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'app_update_channel',
          'แจ้งเตือนอัปเดตแอป',
          channelDescription: 'แจ้งเตือนเมื่อมีเวอร์ชันใหม่',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFFFD600),
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            'เวอร์ชัน $latestVersion พร้อมใช้งานแล้ว กรุณาอัปเดตเพื่อประสบการณ์ที่ดีที่สุด',
            contentTitle: 'NPD HRMS มีเวอร์ชันใหม่!',
            summaryText: 'NPD HRMS',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    debugPrint('แจ้งเตือนอัปเดตเวอร์ชัน $latestVersion ที่หน้ามือถือ');
  }

  /// ยกเลิกแจ้งเตือนทั้งหมด
  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
    debugPrint('ยกเลิกแจ้งเตือนทั้งหมด');
  }

  /// ยกเลิกแจ้งเตือนเฉพาะ ID
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
    debugPrint('ยกเลิกแจ้งเตือน id=$id');
  }

  /// แจ้งเตือนใบเตือนพนักงาน (ใช้ ID 9901 เฉพาะ)
  static const int warningNotificationId = 9901;

  Future<void> showWarningNotification({
    required int count,
  }) async {
    final title = 'คุณมีใบเตือน';
    final body = 'พบใบเตือนในระบบ $count รายการ แตะเพื่อดูรายละเอียด';
    await _plugin.show(
      warningNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'work_reminder_channel',
          'แจ้งเตือนเข้า-ออกงาน',
          channelDescription: 'แจ้งเตือนใบเตือนพนักงาน',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFD32F2F),
          playSound: true,
          enableVibration: true,
          autoCancel: true, // ✅ ให้หายเองเมื่อแตะ
          ongoing: false, // ✅ ไม่ใช่ notification ติดค้าง
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: 'NPD HRMS',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    debugPrint('ส่งแจ้งเตือนใบเตือน: $count รายการ');
  }

  /// ยกเลิกแจ้งเตือนใบเตือนพนักงาน (เรียกเมื่ออ่านแล้ว)
  /// Cancel หลายครั้งเพื่อกัน Samsung OneUI ที่บางครั้ง cancel ไม่ทัน
  Future<void> cancelWarningNotification() async {
    try {
      // Cancel 3 ครั้งพร้อม delay
      await _plugin.cancel(warningNotificationId);
      await Future.delayed(const Duration(milliseconds: 200));
      await _plugin.cancel(warningNotificationId);
      await Future.delayed(const Duration(milliseconds: 300));
      await _plugin.cancel(warningNotificationId);

      debugPrint('✅ ยกเลิกแจ้งเตือนใบเตือน (id=$warningNotificationId) เสร็จ 3 ครั้ง');
    } catch (e) {
      debugPrint('⚠️ cancelWarningNotification error: $e');
    }
  }

  // ========== Notification IDs คงที่ ==========
  static const int approverLeaveNotificationId = 9902;
  static const int approverAddTimeNotificationId = 9903;
  static const int requesterLeaveStatusNotificationId = 9904;
  static const int requesterAddTimeStatusNotificationId = 9905;

  NotificationDetails _buildDetails({
    required String title,
    required String body,
    required Color color,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'work_reminder_channel',
        'แจ้งเตือนเข้า-ออกงาน',
        channelDescription: 'แจ้งเตือนระบบ HRMS',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: color,
        playSound: true,
        enableVibration: true,
        autoCancel: true,
        ongoing: false,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'NPD HRMS',
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> _aggressiveCancel(int id) async {
    try {
      await _plugin.cancel(id);
      await Future.delayed(const Duration(milliseconds: 200));
      await _plugin.cancel(id);
      await Future.delayed(const Duration(milliseconds: 300));
      await _plugin.cancel(id);
      debugPrint('✅ cancel notification id=$id x3');
    } catch (e) {
      debugPrint('⚠️ cancel error id=$id: $e');
    }
  }

  // ---------- สำหรับผู้อนุมัติ ----------

  /// แจ้งเตือนผู้อนุมัติเมื่อมีคำขอลาใหม่
  Future<void> showApproverLeaveNotification(int count) async {
    const title = 'มีคำขอลาใหม่';
    final body = 'มีคำขอลารออนุมัติ $count รายการ แตะเพื่อตรวจสอบ';
    await _plugin.show(
      approverLeaveNotificationId,
      title,
      body,
      _buildDetails(title: title, body: body, color: const Color(0xFF1976D2)),
    );
    debugPrint('ส่งแจ้งเตือนคำขอลาใหม่: $count รายการ');
  }

  Future<void> cancelApproverLeaveNotification() async {
    await _aggressiveCancel(approverLeaveNotificationId);
  }

  /// แจ้งเตือนผู้อนุมัติเมื่อมีคำขอเพิ่มเวลาใหม่
  Future<void> showApproverAddTimeNotification(int count) async {
    const title = 'มีคำขอเพิ่มเวลาใหม่';
    final body = 'มีคำขอเพิ่มเวลารออนุมัติ $count รายการ แตะเพื่อตรวจสอบ';
    await _plugin.show(
      approverAddTimeNotificationId,
      title,
      body,
      _buildDetails(title: title, body: body, color: const Color(0xFFE65100)),
    );
    debugPrint('ส่งแจ้งเตือนคำขอเพิ่มเวลาใหม่: $count รายการ');
  }

  Future<void> cancelApproverAddTimeNotification() async {
    await _aggressiveCancel(approverAddTimeNotificationId);
  }

  // ---------- สำหรับผู้ขอ ----------

  /// แจ้งเตือนผู้ขอลาเมื่อคำขอถูกอนุมัติ/ปฏิเสธ
  Future<void> showLeaveStatusNotification({
    required String state, // 'อนุมัติ' / 'ไม่อนุมัติ'
    required String leaveType,
    String? approverName,
    String? reason,
  }) async {
    final isApproved = state.contains('อนุมัติ') && !state.contains('ไม่');
    final title = 'คำขอลา${state}แล้ว';
    final buf = StringBuffer();
    buf.writeln('ประเภท: $leaveType');
    if (approverName != null && approverName.isNotEmpty) {
      buf.writeln('โดย: $approverName');
    }
    if (reason != null && reason.isNotEmpty) {
      buf.writeln('หมายเหตุ: $reason');
    }
    await _plugin.show(
      requesterLeaveStatusNotificationId,
      title,
      buf.toString().trim(),
      _buildDetails(
        title: title,
        body: buf.toString().trim(),
        color: isApproved ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
      ),
    );
    debugPrint('ส่งแจ้งเตือนสถานะการลา: $state');
  }

  Future<void> cancelLeaveStatusNotification() async {
    await _aggressiveCancel(requesterLeaveStatusNotificationId);
  }

  /// แจ้งเตือนผู้ขอเพิ่มเวลาเมื่อคำขอถูกอนุมัติ/ปฏิเสธ
  Future<void> showAddTimeStatusNotification({
    required String state,
    String? approverName,
    String? reason,
  }) async {
    final isApproved = state.contains('อนุมัติ') && !state.contains('ไม่');
    final title = 'คำขอเพิ่มเวลา${state}แล้ว';
    final buf = StringBuffer();
    if (approverName != null && approverName.isNotEmpty) {
      buf.writeln('โดย: $approverName');
    }
    if (reason != null && reason.isNotEmpty) {
      buf.writeln('หมายเหตุ: $reason');
    }
    await _plugin.show(
      requesterAddTimeStatusNotificationId,
      title,
      buf.toString().trim().isEmpty ? 'อัปเดตสถานะแล้ว' : buf.toString().trim(),
      _buildDetails(
        title: title,
        body: buf.toString().trim().isEmpty ? 'อัปเดตสถานะแล้ว' : buf.toString().trim(),
        color: isApproved ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
      ),
    );
    debugPrint('ส่งแจ้งเตือนสถานะเพิ่มเวลา: $state');
  }

  Future<void> cancelAddTimeStatusNotification() async {
    await _aggressiveCancel(requesterAddTimeStatusNotificationId);
  }


  /// ตั้งแจ้งเตือนใหม่จากข้อมูลที่บันทึกไว้ (สำหรับ boot receiver)
  Future<void> rescheduleFromCache({required String odooBaseUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final scheduleJson = prefs.getString('scheduleData');
    final employeeName = prefs.getString('employeeName') ?? '';

    if (scheduleJson == null || employeeName.isEmpty) return;

    final scheduleData = json.decode(scheduleJson);
    final employeeCode = scheduleData['employee_code'] ?? '';

    if (employeeCode.isNotEmpty) {
      await scheduleWorkNotifications(
        employeeCode: employeeCode,
        employeeName: employeeName,
        odooBaseUrl: odooBaseUrl,
      );
    }
  }
}
