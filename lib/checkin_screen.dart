import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api_client.dart';
import 'ui/app_theme.dart';

class CheckinScreen extends StatefulWidget {
  final int userId;
  final bool isDemoUser;
  final Function(String message, bool isSuccess)? onCheckinComplete;

  const CheckinScreen({
    super.key,
    required this.userId,
    this.isDemoUser = false,
    this.onCheckinComplete,
  });

  @override
  State<CheckinScreen> createState() => CheckinScreenState(); // ✅ เปลี่ยนเป็น public
}

// ✅ เปลี่ยนเป็น public class เพื่อให้เรียก refreshData() จากภายนอกได้
class CheckinScreenState extends State<CheckinScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Position? _currentPosition;
  Map<String, dynamic>? _checkinData;
  double? _distanceInMeters;
  int _allowOffsiteTime = 0;
  bool _isDisposed = false; // ✅ เพิ่ม flag ตรวจสอบว่า widget ถูก dispose แล้วหรือยัง

  GoogleMapController? _mapController;
  final Set<Circle> _circles = {};

  Map<String, dynamic>? _suspension; // ไม่ null = กำลังถูกพักงาน

  @override
  void initState() {
    super.initState();
    _loadSuspension();
    _initializeCheckin();
  }

  /// ถาม Odoo ว่าวันนี้ถูกพักงานอยู่ไหม ถ้าใช่จะบล็อกไม่ให้ลงเวลา
  ///
  /// ไม่ต้องส่งรหัสพนักงาน เพราะ token บอกเซิร์ฟเวอร์อยู่แล้วว่าใครถาม
  /// ถามไม่ได้ (เน็ตสะดุด/เซิร์ฟเวอร์ล่ม) ให้ลงเวลาได้ตามปกติ
  /// ยอมให้คนถูกพักงานหลุดไปตอกบัตร ดีกว่าทั้งบริษัทตอกบัตรไม่ได้
  Future<void> _loadSuspension() async {
    try {
      final res = await ApiClient.instance.get('/suspension');
      final data = res['data'];
      if (!mounted || _isDisposed) return;
      if (data is Map && data['is_suspended'] == true) {
        _safeSetState(() => _suspension = Map<String, dynamic>.from(data));
      } else {
        _safeSetState(() => _suspension = null);
      }
    } catch (e) {
      debugPrint('เช็คสถานะพักงานไม่สำเร็จ: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // ✅ ตั้ง flag ก่อน dispose
    // ✅ ไม่ต้อง dispose _mapController เอง เพราะ GoogleMap widget จัดการเอง
    _mapController = null;
    super.dispose();
  }

  /// Odoo ส่ง false กลับมาแทนค่าว่างสำหรับช่องข้อความ/วันที่
  /// ถ้า cast เป็น String ตรง ๆ จะพังทันที จึงต้องแปลงผ่านตัวนี้เสมอ
  String _asText(dynamic value) {
    if (value == null || value == false) return '';
    return value.toString();
  }

  /// แปลง 2026-09-18 เป็น 18 ก.ย. 2569 ให้อ่านง่าย
  String _thaiDate(dynamic value) {
    final raw = _asText(value);
    if (raw.isEmpty) return '-';
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    const months = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return raw;
    if (month < 1 || month > 12) return raw;
    return '$day ${months[month - 1]} ${year + 543}';
  }

  /// หน้าจอตอนถูกพักงาน — ไม่แสดงปุ่มลงเวลาเลย
  ///
  /// ตั้งใจไม่ให้กดได้ ไม่ใช่กดแล้วเด้ง error เพราะพนักงานควรเห็นตั้งแต่แรกว่า
  /// ทำไมถึงลงเวลาไม่ได้ และถูกพักงานถึงเมื่อไร จะได้ไม่ต้องไปถาม HR
  Widget _buildSuspendedBody() {
    final data = _suspension!;
    // เซิร์ฟเวอร์แปลง พ.ศ. มาให้แล้ว ถ้าไม่มีค่อยแปลงเอง
    final start = _asText(data['date_start_display']).isNotEmpty
        ? _asText(data['date_start_display'])
        : _thaiDate(data['date_start']);
    final end = _asText(data['date_end_display']).isNotEmpty
        ? _asText(data['date_end_display'])
        : _thaiDate(data['date_end']);
    final reason = _asText(data['reason']).trim();
    final note = _asText(data['note']).trim();
    final days = data['day_count'];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(Icons.gpp_maybe_rounded,
                size: 78, color: Colors.orange.shade700),
            const SizedBox(height: 16),
            Text('อยู่ในช่วงถูกพักงาน',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('ระหว่างนี้ยังลงเวลาเข้า-ออกงานไม่ได้',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 15, color: Colors.grey.shade700)),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _suspensionRow(Icons.event_busy_rounded, 'ตั้งแต่วันที่', start),
                    const SizedBox(height: 10),
                    _suspensionRow(Icons.event_available_rounded, 'ถึงวันที่', end),
                    if (days != null && days != false) ...[
                      const SizedBox(height: 10),
                      _suspensionRow(
                          Icons.today_rounded, 'รวม', '$days วัน'),
                    ],
                    if (reason.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text('เหตุผล',
                          style: GoogleFonts.ibmPlexSansThai(
                              fontSize: 13, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text(reason,
                          style: GoogleFonts.ibmPlexSansThai(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(note,
                          style: GoogleFonts.ibmPlexSansThai(
                              fontSize: 14, color: Colors.grey.shade800)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('หากข้อมูลไม่ถูกต้อง กรุณาติดต่อฝ่ายบุคคล',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSansThai(
                    fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _suspensionRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.orange.shade800),
        const SizedBox(width: 10),
        Text(label,
            style: GoogleFonts.ibmPlexSansThai(
                fontSize: 14, color: Colors.grey.shade800)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.ibmPlexSansThai(
                fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ✅ Safe setState ที่เช็ค mounted และ _isDisposed
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  // ✅ Public method สำหรับรีเฟรชข้อมูลจากภายนอก
  Future<void> refreshData() async {
    if (_isDisposed) return;
    await _initializeCheckin();
  }

  Future<void> _initializeCheckin() async {
    if (_isDisposed) return; // ✅ เช็คก่อนทำงาน
    
    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _fetchCheckinStatus();
      if (_isDisposed) return; // ✅ เช็คอีกครั้งหลัง async
      
      _currentPosition = await _determinePosition();
      if (_isDisposed) return; // ✅ เช็คอีกครั้งหลัง async
      
      // คำนวณระยะทางเมื่อไม่ใช่โหมดสาธิตเท่านั้น
      if (_allowOffsiteTime == 0) {
        _calculateDistance();
      }
      if (_mapController != null && !_isDisposed) {
        _updateMap();
      }
    } catch (e) {
      _safeSetState(() {
        _errorMessage = e.toString();
      });
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchCheckinStatus() async {
    try {
      final decoded = await ApiClient.instance.get('/checkin/status');
      _checkinData = decoded['data'];
      _allowOffsiteTime =
          int.tryParse('${_checkinData?['allowOffsiteTime']}') ?? 0;
    } on ApiException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception('❗ ${e.toString()}');
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('กรุณาเปิด GPS');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('กรุณาอนุญาตให้เข้าถึงตำแหน่ง');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('การเข้าถึงตำแหน่งถูกปฏิเสธถาวร');
    }

    // ✅ แก้บัค: ระบุ accuracy สูงสุด + timeout เพื่อให้ตำแหน่งแม่นยำ
    // ดึงตำแหน่งแรกก่อน (อาจเป็น cache)
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 15),
    );

    // ✅ ถ้าความแม่นยำต่ำกว่า 50 เมตร ลองดึงอีกครั้ง
    if (position.accuracy > 50) {
      try {
        final betterPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 10),
        );
        // ใช้ตำแหน่งใหม่ถ้าแม่นยำกว่า
        if (betterPosition.accuracy < position.accuracy) {
          position = betterPosition;
        }
      } catch (_) {
        // ถ้า timeout ใช้ตำแหน่งเดิม
        debugPrint('⚠️ ดึงตำแหน่งรอบ 2 ไม่สำเร็จ ใช้ตำแหน่งเดิม (accuracy: ${position.accuracy}m)');
      }
    }

    debugPrint('📍 ตำแหน่ง: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
    return position;
  }

  void _calculateDistance() {
    if (_currentPosition == null || _checkinData == null || _isDisposed) return;

    final targetLat =
        double.tryParse(_checkinData!['targetLat'].toString()) ?? 0;
    final targetLng =
        double.tryParse(_checkinData!['targetLng'].toString()) ?? 0;

    _safeSetState(() {
      _distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        targetLat,
        targetLng,
      );
    });
  }

  void _updateMap() {
    if (_checkinData == null || _isDisposed || _mapController == null) return;

    final targetLat =
        double.tryParse(_checkinData!['targetLat'].toString()) ?? 0;
    final targetLng =
        double.tryParse(_checkinData!['targetLng'].toString()) ?? 0;
    final allowedMeter =
        double.tryParse(_checkinData!['allowedMeter'].toString()) ?? 100;

    final branchLocation = LatLng(targetLat, targetLng);

    _safeSetState(() {
      _circles.clear();
      // ไม่แสดงวงกลมในโหมดสาธิต
      if (_allowOffsiteTime == 0) {
        _circles.add(Circle(
          circleId: const CircleId('radius'),
          center: branchLocation,
          radius: allowedMeter,
          fillColor: Colors.green.withOpacity(0.2),
          strokeColor: Colors.green,
          strokeWidth: 2,
        ));
      }
    });

    LatLng cameraTarget = branchLocation;
    if (_currentPosition != null) {
      cameraTarget =
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    // ✅ เช็คอีกครั้งก่อนใช้ _mapController
    if (!_isDisposed && _mapController != null) {
      try {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(cameraTarget, 16),
        );
      } catch (e) {
        debugPrint('Error animating camera: $e');
      }
    }
  }

  // ✅ Reverse Geocoding: ดึงที่อยู่ไทยแบบละเอียด รวมเป็นฟิลด์เดียว
  // ใช้ native API ของ iOS/Android (ไม่ต้องใช้ API key)
  // คืนค่าเป็น String เดียว เช่น "123 ถนนสุขุมวิท ต.คลองตันเหนือ อ.วัฒนา จ.กรุงเทพมหานคร 10110"
  Future<String> _getThaiAddressFromCoordinates(
      double lat, double lng) async {
    try {
      // ตั้ง locale เป็นไทยก่อน (geocoding 3.0.0 ไม่มี named param แล้ว)
      try {
        await setLocaleIdentifier('th_TH');
      } catch (_) {
        // ถ้า set locale ไม่สำเร็จ ใช้ default ของระบบ
      }

      final placemarks = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 8));

      if (placemarks.isEmpty) return '';

      final p = placemarks.first;

      // โครงสร้างที่อยู่ไทยจาก Placemark:
      // - name              → เลขที่/ชื่อสถานที่
      // - thoroughfare      → ถนน
      // - subLocality       → ตำบล / แขวง
      // - locality          → อำเภอ / เขต
      // - administrativeArea → จังหวัด
      // - postalCode        → รหัสไปรษณีย์
      final parts = <String>[
        if ((p.name ?? '').isNotEmpty && p.name != p.thoroughfare) p.name!,
        if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
        if ((p.subLocality ?? '').isNotEmpty) 'ต.${p.subLocality}',
        if ((p.locality ?? '').isNotEmpty) 'อ.${p.locality}',
        if ((p.administrativeArea ?? '').isNotEmpty)
          'จ.${p.administrativeArea}',
        if ((p.postalCode ?? '').isNotEmpty) p.postalCode!,
      ];

      return parts.join(' ').trim();
    } catch (e) {
      debugPrint('⚠️ Reverse Geocoding failed: $e');
      return '';
    }
  }

  Future<void> _performCheckin(String type) async {
    if (_currentPosition == null) {
      _showStatusDialog('❗ ไม่พบตำแหน่งปัจจุบัน', isError: true);
      return;
    }

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // ✅ ดึงที่อยู่ไทยรวมเป็นฟิลด์เดียว (ถ้าดึงไม่ได้ ส่งค่าว่าง — ไม่บล็อกการลงเวลา)
      final address = await _getThaiAddressFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (_isDisposed) return;

      final decoded = await ApiClient.instance.post('/checkin', body: {
        'type': type,
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
        'accuracy': _currentPosition!.accuracy,
        'address': address, // ✅ ที่อยู่ไทยรวมฟิลด์เดียว
      });

      if (_isDisposed) return; // ✅ เช็คหลัง async

      // ยิงไม่ผ่านจะโยน ApiException ออกมาแล้ว — มาถึงตรงนี้คือสำเร็จ
      if (widget.onCheckinComplete != null) {
        widget.onCheckinComplete!('✅ ${decoded['message']}', true);
      } else {
        _showStatusDialog('✅ ${decoded['message']}', isError: false);
      }
    } on ApiException catch (e) {
      if (_isDisposed) return;
      if (widget.onCheckinComplete != null) {
        widget.onCheckinComplete!('❌ ${e.message}', false);
      } else {
        _showStatusDialog('❌ ${e.message}', isError: true);
      }
    } catch (e) {
      if (_isDisposed) return; // ✅ เช็คหลัง async
      if (widget.onCheckinComplete != null) {
        widget.onCheckinComplete!('❌ ${e.toString()}', false);
      } else {
        _showStatusDialog('❌ ${e.toString()}', isError: true);
      }
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  void _showStatusDialog(String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          backgroundColor: isError ? Colors.red.shade50 : Colors.green.shade50,
          title: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.red.shade700 : Colors.green.shade700,
                size: 30,
              ),
              const SizedBox(width: 10),
              Text(
                isError ? 'เกิดข้อผิดพลาด' : 'สำเร็จ',
                style: TextStyle(
                  color: isError ? Colors.red.shade700 : Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: isError ? Colors.red.shade900 : Colors.green.shade900,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'ตกลง',
                style: TextStyle(
                  color: isError ? Colors.red.shade700 : Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool canCheckIn = false;
    bool canCheckOut = false;
    bool inRange = false;

    // ตรวจสอบข้อมูลที่ได้รับจาก API
    if (_checkinData != null) {
      canCheckIn = _checkinData!['canCheckIn'] == true;
      canCheckOut = _checkinData!['canCheckOut'] == true;

      // ถ้าเป็นโหมดสาธิต (ไม่ว่าจะจาก widget.isDemoUser หรือ API)
      if (_allowOffsiteTime == 1) {
        inRange = true; // ถือว่าอยู่ในระยะเสมอ
      } else {
        // ถ้าไม่ใช่โหมดสาธิต ให้เช็คระยะทาง
        final allowed =
            double.tryParse(_checkinData!['allowedMeter'].toString()) ?? 100;
        if (_distanceInMeters != null) {
          inRange = _distanceInMeters! <= allowed;
        }
      }
    }

    LatLng initialLocation = const LatLng(13.7563, 100.5018);
    if (_checkinData != null) {
      try {
        initialLocation = LatLng(
          double.parse(_checkinData!['targetLat'].toString()),
          double.parse(_checkinData!['targetLng'].toString()),
        );
      } catch (_) {}
    }

    final bool enableCheckInButton = (canCheckIn && inRange) && !_isLoading;
    final bool enableCheckOutButton = (canCheckOut && inRange) && !_isLoading;

    return Scaffold(
      appBar: AppGradientBar(
        automaticallyImplyLeading: true, // ไม่ต้องมีปุ่ม back
        title: const Text('ลงเวลาเข้า-ออกงาน'),
        centerTitle: true, // ไอคอนจะอยู่ตรงกลางถ้าอยากได้
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรชข้อมูล',
            onPressed: _initializeCheckin, // ✅ ใช้ฟังก์ชันนี้แทน
          ),
        ],
      ),
      body: _suspension != null
          ? _buildSuspendedBody()
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)))
                  : _buildBody(
                      canCheckIn, canCheckOut, inRange, initialLocation),
    );
  }

  /// แถวข้อมูล 1 บรรทัด — ชื่อรายการชิดซ้าย ค่าชิดขวา อ่านกวาดตาลงมาได้เร็ว
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.ibmPlexSansThai(
              fontSize: 13.5,
              color: AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value.isEmpty ? '-' : value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexSansThai(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
      bool canCheckIn, bool canCheckOut, bool inRange, LatLng initialLocation) {
    final bool enableCheckInButton = (canCheckIn && inRange) && !_isLoading;
    final bool enableCheckOutButton = (canCheckOut && inRange) && !_isLoading;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AppPanel(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              children: [
                _infoRow(
                  icon: Icons.badge_outlined,
                  label: 'พนักงาน',
                  value:
                      '${_checkinData?['firstName'] ?? ''} ${_checkinData?['lastName'] ?? ''}'
                          .trim(),
                ),
                const Divider(height: 18),
                // แสดงข้อความโหมดสาธิตเมื่อเป็นไปตามเงื่อนไข
                if (_allowOffsiteTime == 1)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: AppStatusChip(
                      label: 'โหมดสาธิต: ลงเวลาได้ทุกพื้นที่',
                      color: AppColors.warning,
                    ),
                  )
                else ...[
                  _infoRow(
                    icon: Icons.place_outlined,
                    label: 'ระยะจากสาขา',
                    value: _distanceInMeters == null
                        ? '-'
                        : '${NumberFormat('#,##0').format(_distanceInMeters)} เมตร',
                  ),
                  if (_currentPosition != null) ...[
                    const SizedBox(height: 8),
                    _infoRow(
                      icon: Icons.gps_fixed_rounded,
                      label: 'ความแม่นยำ GPS',
                      value:
                          '${_currentPosition!.accuracy.toStringAsFixed(0)} เมตร',
                      // ตัวเลขยิ่งน้อยยิ่งแม่น — สีบอกคุณภาพสัญญาณก่อนกดลงเวลา
                      valueColor: _currentPosition!.accuracy <= 20
                          ? AppColors.success
                          : _currentPosition!.accuracy <= 50
                              ? AppColors.warning
                              : AppColors.danger,
                    ),
                  ],
                  if (_distanceInMeters != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppStatusChip(
                        label: inRange
                            ? 'อยู่ในพื้นที่ลงเวลา'
                            : 'อยู่นอกพื้นที่ที่กำหนด',
                        color: inRange ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: initialLocation,
              zoom: 16,
            ),
            onMapCreated: (controller) {
              // ✅ เช็คว่า widget ยังไม่ถูก dispose ก่อน assign controller
              if (!_isDisposed && mounted) {
                _mapController = controller;
                _updateMap();
              }
            },
            circles: _circles,
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
            markers: const {},
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed:
                    enableCheckInButton ? () => _performCheckin('in') : null,
                icon: const Icon(Icons.login),
                label: const Text('เข้างาน'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white),
              ),
              ElevatedButton.icon(
                onPressed:
                    enableCheckOutButton ? () => _performCheckin('out') : null,
                icon: const Icon(Icons.logout),
                label: const Text('ออกงาน'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
            ],
          ),
        )
      ],
    );
  }
}
