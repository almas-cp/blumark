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

  // Debug info
  final List<String> _debugLogs = [];
  List<ScanResult> _foundDevices = [];
  String _bluetoothState = 'Unknown';
  Map<Permission, PermissionStatus> _permissionStatuses = {};

  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
    _checkBluetoothState();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _debugLogs.insert(0, '[$timestamp] $message');
      if (_debugLogs.length > 50) _debugLogs.removeLast();
    });
  }

  Future<void> _checkBluetoothState() async {
    FlutterBluePlus.adapterState.listen((state) {
      setState(() => _bluetoothState = state.toString().split('.').last);
      _log('Bluetooth state: $_bluetoothState');
    });
  }

  Future<void> _loadStudentInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('student_name') ?? 'Student';
    });
    _log('Loaded student: $_studentName');
    _log('Student ID: ${prefs.getString('student_id')}');
  }


  Future<void> _checkPermissions() async {
    _log('Checking permissions...');
    _permissionStatuses = {
      Permission.bluetoothScan: await Permission.bluetoothScan.status,
      Permission.bluetoothConnect: await Permission.bluetoothConnect.status,
      Permission.location: await Permission.location.status,
    };
    _permissionStatuses.forEach((perm, status) {
      _log('${perm.toString().split('.').last}: ${status.toString().split('.').last}');
    });
    setState(() {});
  }

  Future<bool> _requestPermissions() async {
    _log('Requesting permissions...');
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    _permissionStatuses = statuses;
    statuses.forEach((perm, status) {
      _log('${perm.toString().split('.').last}: ${status.toString().split('.').last}');
    });
    setState(() {});

    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  Future<void> _startScanning() async {
    if (_isScanning) return;

    _log('--- Starting scan ---');
    setState(() => _foundDevices = []);

    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      _log('ERROR: Permissions denied');
      setState(() => _status = 'Permissions denied');
      return;
    }

    final btState = await FlutterBluePlus.adapterState.first;
    _log('Bluetooth adapter state: $btState');
    if (btState != BluetoothAdapterState.on) {
      _log('ERROR: Bluetooth is off');
      setState(() => _status = 'Please turn on Bluetooth');
      return;
    }

    setState(() {
      _isScanning = true;
      _status = 'Scanning...';
    });

    try {
      _log('Starting BLE scan (no service filter for debug)...');
      
      // Scan WITHOUT service filter to see ALL devices
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 30),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        setState(() => _foundDevices = results);
        
        for (var result in results) {
          final name = result.device.platformName;
          final advName = result.advertisementData.advName;
          final services = result.advertisementData.serviceUuids;
          final mfgData = result.advertisementData.manufacturerData;
          
          // Log devices with names, services, or manufacturer data
          if (name.isNotEmpty || services.isNotEmpty || mfgData.isNotEmpty) {
            _log('Found: ${name.isEmpty ? advName : name} | Svc: ${services.length} | Mfg: ${mfgData.keys} | RSSI: ${result.rssi}');
          }

          // Check for ATT_ prefix in device name
          if (name.startsWith('ATT_')) {
            _log('*** FOUND ATTENDANCE BEACON (name): $name ***');
            _handleFoundSession(result);
            return;
          }

          // Check for ATT_ prefix in advertisement name
          if (advName.startsWith('ATT_')) {
            _log('*** FOUND ATTENDANCE BEACON (advName): $advName ***');
            _handleFoundSession(result);
            return;
          }

          // Check manufacturer data for our company ID (0xFFFF)
          if (mfgData.containsKey(0xFFFF) || mfgData.containsKey(65535)) {
            _log('*** FOUND BY MANUFACTURER DATA ***');
            _handleFoundSession(result);
            return;
          }

          // Also check service UUID
          final hasService = services.any(
            (uuid) => uuid.toString().toLowerCase() == serviceUuid
          );
          if (hasService) {
            _log('*** FOUND BY SERVICE UUID ***');
            _handleFoundSession(result);
            return;
          }
        }
      });

      await Future.delayed(const Duration(seconds: 30));
      if (_isScanning && mounted) {
        _log('Scan timeout - no session found');
        setState(() {
          _isScanning = false;
          _status = 'No session found. Try again.';
        });
      }
    } catch (e) {
      _log('SCAN ERROR: $e');
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

    _log('Processing beacon: ${result.device.platformName}');
    _log('advName: ${result.advertisementData.advName}');
    _log('Manufacturer data keys: ${result.advertisementData.manufacturerData.keys}');
    setState(() => _status = 'Session found! Marking attendance...');

    try {
      String? sessionToken;
      
      // Try device name first
      if (result.device.platformName.startsWith('ATT_')) {
        sessionToken = result.device.platformName.substring(4);
        _log('Token from platformName: $sessionToken');
      }
      
      // Try local name from advertisement
      if (sessionToken == null) {
        final localName = result.advertisementData.advName;
        if (localName.startsWith('ATT_')) {
          sessionToken = localName.substring(4);
          _log('Token from advName: $sessionToken');
        }
      }

      // Try manufacturer data with our company ID (0xFFFF = 65535)
      if (sessionToken == null) {
        final mfgData = result.advertisementData.manufacturerData;
        // Check both int representations
        final data = mfgData[65535] ?? mfgData[0xFFFF];
        if (data != null && data.isNotEmpty) {
          sessionToken = String.fromCharCodes(data);
          _log('Token from manufacturer data: $sessionToken');
        }
      }
      
      // Fallback: try any manufacturer data
      if (sessionToken == null && result.advertisementData.manufacturerData.isNotEmpty) {
        final data = result.advertisementData.manufacturerData.values.first;
        try {
          sessionToken = utf8.decode(data);
          _log('Token from raw manufacturer data: $sessionToken');
        } catch (e) {
          _log('Could not decode manufacturer data: $e');
        }
      }

      if (sessionToken == null) {
        _log('ERROR: Could not extract session token');
        setState(() {
          _isScanning = false;
          _status = 'Invalid session beacon';
        });
        return;
      }

      _log('Looking up session with token: $sessionToken');
      final sessionResponse = await supabase
          .rpc('get_session_by_token', params: {'p_token': sessionToken});

      _log('Session response: $sessionResponse');

      if (sessionResponse == null || (sessionResponse as List).isEmpty) {
        _log('ERROR: Session not found in database');
        setState(() {
          _isScanning = false;
          _status = 'Session not found or expired';
        });
        return;
      }

      final sessionId = sessionResponse[0]['session_id'];
      _log('Session ID: $sessionId');

      final prefs = await SharedPreferences.getInstance();
      final studentId = prefs.getString('student_id');
      final studentName = prefs.getString('student_name');
      final rollNumber = prefs.getString('roll_number');

      _log('Marking attendance for: $studentName ($rollNumber)');

      final attendanceResponse = await supabase.rpc('mark_attendance', params: {
        'p_session_id': sessionId,
        'p_student_id': studentId,
        'p_student_name': studentName,
        'p_roll_number': rollNumber,
      });

      _log('Attendance response: $attendanceResponse');

      if (mounted) {
        setState(() {
          _isScanning = false;
          if (attendanceResponse['success'] == true) {
            _status = '✓ Attendance marked successfully!';
            _log('SUCCESS: Attendance marked');
          } else {
            _status = attendanceResponse['message'] ?? 'Failed';
            _log('FAILED: ${attendanceResponse['message']}');
          }
        });
      }
    } catch (e) {
      _log('ERROR: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _stopScanning() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    setState(() {
      _isScanning = false;
      _status = 'Scan stopped';
    });
    _log('Scan stopped manually');
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissions,
          ),
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
        child: Column(
          children: [
            // Status section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text('Welcome, $_studentName!',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _status.contains('✓') ? Colors.green.shade100 : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isScanning) const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        if (_isScanning) const SizedBox(width: 8),
                        Flexible(child: Text(_status, textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isScanning ? _stopScanning : _startScanning,
                          icon: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching),
                          label: Text(_isScanning ? 'Stop' : 'Scan'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isScanning ? Colors.red : Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Debug panel
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Logs'),
                        Tab(text: 'Devices'),
                        Tab(text: 'Status'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Logs tab
                          Container(
                            color: Colors.black87,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _debugLogs.length,
                              itemBuilder: (ctx, i) => Text(
                                _debugLogs[i],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ),
                          ),
                          // Devices tab
                          ListView.builder(
                            itemCount: _foundDevices.length,
                            itemBuilder: (ctx, i) {
                              final d = _foundDevices[i];
                              final name = d.device.platformName.isEmpty 
                                  ? d.advertisementData.advName 
                                  : d.device.platformName;
                              return ListTile(
                                dense: true,
                                title: Text(name.isEmpty ? '(unnamed)' : name),
                                subtitle: Text(
                                  'RSSI: ${d.rssi} | Services: ${d.advertisementData.serviceUuids.length}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: d.device.platformName.startsWith('ATT_')
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : null,
                              );
                            },
                          ),
                          // Status tab
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Bluetooth: $_bluetoothState'),
                                const Divider(),
                                const Text('Permissions:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ..._permissionStatuses.entries.map((e) => Text(
                                  '${e.key.toString().split('.').last}: ${e.value.toString().split('.').last}'
                                )),
                                const Divider(),
                                Text('Devices found: ${_foundDevices.length}'),
                                Text('Service UUID: $serviceUuid'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
