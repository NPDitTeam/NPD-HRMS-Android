import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    _initializeCheckin();
  }

  @override
  void dispose() {
    _isDisposed = true; // ✅ ตั้ง flag ก่อน dispose
    // ✅ ไม่ต้อง dispose _mapController เอง เพราะ GoogleMap widget จัดการเอง
    _mapController = null;
    super.dispose();
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
      if (!widget.isDemoUser && _allowOffsiteTime == 0) {
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
      final url = Uri.parse(
          'https://npdhrms.com/api/api_checkin_status1.php?user_id=${widget.userId}');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded['status'] == 'success') {
          _checkinData = decoded['data'];
          _allowOffsiteTime =
              int.tryParse(_checkinData!['allowOffsiteTime'].toString()) ?? 0;
        } else {
          throw Exception(decoded['message'] ?? 'ไม่สามารถโหลดข้อมูลลงเวลา');
        }
      } else {
        throw Exception('รหัสสถานะ: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('⏱️ การเชื่อมต่อล่าช้าเกิน 10 วินาที');
    } on SocketException {
      throw Exception('🌐 ไม่มีอินเทอร์เน็ตหรือเซิร์ฟเวอร์ไม่ตอบสนอง');
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

    return await Geolocator.getCurrentPosition();
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
      if (!widget.isDemoUser && _allowOffsiteTime == 0) {
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

  Future<void> _performCheckin(String type) async {
    if (_currentPosition == null) {
      _showStatusDialog('❗ ไม่พบตำแหน่งปัจจุบัน', isError: true);
      return;
    }

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      final url =
          Uri.parse('https://npdhrms.com/api/api_checkin_save_test1.php');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': widget.userId,
          'type': type,
          'lat': _currentPosition!.latitude,
          'lng': _currentPosition!.longitude,
        }),
      );

      if (_isDisposed) return; // ✅ เช็คหลัง async

      final decoded = json.decode(response.body);
      if (decoded['status'] == 'success') {
        // ✅ เรียก callback เพื่อให้หน้าหลักจัดการ
        if (widget.onCheckinComplete != null) {
          widget.onCheckinComplete!('✅ ${decoded['message']}', true);
        } else {
          _showStatusDialog('✅ ${decoded['message']}', isError: false);
        }
      } else {
        if (widget.onCheckinComplete != null) {
          widget.onCheckinComplete!('❌ ${decoded['message']}', false);
        } else {
          _showStatusDialog('❌ ${decoded['message']}', isError: true);
        }
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
      if (widget.isDemoUser || _allowOffsiteTime == 1) {
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
      appBar: AppBar(
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red)))
              : _buildBody(canCheckIn, canCheckOut, inRange, initialLocation),
    );
  }

  Widget _buildBody(
      bool canCheckIn, bool canCheckOut, bool inRange, LatLng initialLocation) {
    final bool enableCheckInButton = (canCheckIn && inRange) && !_isLoading;
    final bool enableCheckOutButton = (canCheckOut && inRange) && !_isLoading;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '👤 คุณ: ${_checkinData?['firstName']} ${_checkinData?['lastName']}',
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              // แสดงข้อความโหมดสาธิตเมื่อเป็นไปตามเงื่อนไข
              if (widget.isDemoUser || _allowOffsiteTime == 1)
                Text('📍 โหมดสาธิต: ไม่จำกัดพื้นที่',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold))
              else ...[
                Text(
                    '📍 ระยะจากสาขา: ${_distanceInMeters?.toStringAsFixed(0) ?? '-'} เมตร',
                    style: const TextStyle(fontSize: 16)),
                if (!inRange && _distanceInMeters != null)
                  const Text('(คุณอยู่นอกพื้นที่ที่กำหนด)',
                      style: TextStyle(color: Colors.red)),
              ],
            ],
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
