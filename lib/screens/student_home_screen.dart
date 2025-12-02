import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  String _studentName = '';
  String _status = 'Ready to scan';
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _loadStudentInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('student_name') ?? 'Student';
    });
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  Future<void> _startScanning() async {
    if (_isScanning) return;

    // Check permissions
    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      setState(() => _status = 'Permissions denied');
      return;
    }

    // Check if Bluetooth is on
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      setState(() => _status = 'Please turn on Bluetooth');
      return;
    }

    setState(() {
      _isScanning = true;
      _status = 'Scanning for attendance session...';
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: const Duration(seconds: 30),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (var result in results) {
          // Check for our service UUID
          final hasService = result.advertisementData.serviceUuids
              .any((uuid) => uuid.toString().toLowerCase() == serviceUuid);

          if (hasService) {
            await _handleFoundSession(result);
            return;
          }
        }
      });

      // Handle scan timeout
      await Future.delayed(const Duration(seconds: 30));
      if (_isScanning && mounted) {
        setState(() {
          _isScanning = false;
          _status = 'No session found. Try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = 'Scan error: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _handleFoundSession(ScanResult result) async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();

    setState(() => _status = 'Session found! Marking attendance...');

    try {
      // Extract session token from device name or manufacturer data
      String? sessionToken;
      
      // Try to get from device name first
      if (result.device.platformName.startsWith('ATT_')) {
        sessionToken = result.device.platformName.substring(4);
      }
      
      // Or from manufacturer data
      if (sessionToken == null && result.advertisementData.manufacturerData.isNotEmpty) {
        final data = result.advertisementData.manufacturerData.values.first;
        sessionToken = utf8.decode(data);
      }

      if (sessionToken == null) {
        setState(() {
          _isScanning = false;
          _status = 'Invalid session beacon';
        });
        return;
      }

      // Get session ID from token
      final sessionResponse = await supabase
          .rpc('get_session_by_token', params: {'p_token': sessionToken});

      if (sessionResponse == null || (sessionResponse as List).isEmpty) {
        setState(() {
          _isScanning = false;
          _status = 'Session not found or expired';
        });
        return;
      }

      final sessionId = sessionResponse[0]['session_id'];

      // Get student info
      final prefs = await SharedPreferences.getInstance();
      final studentId = prefs.getString('student_id');
      final studentName = prefs.getString('student_name');
      final rollNumber = prefs.getString('roll_number');

      // Mark attendance using stored procedure
      final attendanceResponse = await supabase.rpc('mark_attendance', params: {
        'p_session_id': sessionId,
        'p_student_id': studentId,
        'p_student_name': studentName,
        'p_roll_number': rollNumber,
      });

      if (mounted) {
        setState(() {
          _isScanning = false;
          if (attendanceResponse['success'] == true) {
            _status = '✓ Attendance marked successfully!';
          } else {
            _status = attendanceResponse['message'] ?? 'Failed to mark attendance';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = 'Error: ${e.toString()}';
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.person,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome, $_studentName!',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _status.contains('✓')
                      ? Colors.green.shade50
                      : _status.contains('error') || _status.contains('denied')
                          ? Colors.red.shade50
                          : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isScanning)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_isScanning) const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 16,
                          color: _status.contains('✓')
                              ? Colors.green.shade700
                              : _status.contains('error') ||
                                      _status.contains('denied')
                                  ? Colors.red.shade700
                                  : Colors.blue.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScanning,
                  icon: const Icon(Icons.bluetooth_searching, size: 28),
                  label: Text(
                    _isScanning ? 'Scanning...' : 'Scan for Attendance',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
