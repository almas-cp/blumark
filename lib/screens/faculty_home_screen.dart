import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';

class FacultyHomeScreen extends StatefulWidget {
  const FacultyHomeScreen({super.key});

  @override
  State<FacultyHomeScreen> createState() => _FacultyHomeScreenState();
}

class _FacultyHomeScreenState extends State<FacultyHomeScreen> {
  final _facultyNameController = TextEditingController();
  final _blePeripheral = FlutterBlePeripheral();

  bool _isSessionActive = false;
  bool _isLoading = false;
  bool _isAdvertising = false;
  String? _sessionId;
  String? _sessionToken;
  List<Map<String, dynamic>> _attendanceList = [];
  StreamSubscription? _realtimeSubscription;

  // Debug info
  final List<String> _debugLogs = [];
  bool _isPeripheralSupported = false;
  Map<Permission, PermissionStatus> _permissionStatuses = {};

  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  @override
  void initState() {
    super.initState();
    _checkPeripheralSupport();
  }

  @override
  void dispose() {
    _facultyNameController.dispose();
    _realtimeSubscription?.cancel();
    _stopAdvertising();
    super.dispose();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _debugLogs.insert(0, '[$timestamp] $message');
      if (_debugLogs.length > 50) _debugLogs.removeLast();
    });
  }

  Future<void> _checkPeripheralSupport() async {
    try {
      _isPeripheralSupported = await _blePeripheral.isSupported;
      _log('BLE Peripheral supported: $_isPeripheralSupported');
      
      final isAdvertising = await _blePeripheral.isAdvertising;
      _log('Currently advertising: $isAdvertising');
      
      setState(() {});
    } catch (e) {
      _log('Error checking peripheral support: $e');
    }
  }


  Future<void> _checkPermissions() async {
    _log('Checking permissions...');
    _permissionStatuses = {
      Permission.bluetoothAdvertise: await Permission.bluetoothAdvertise.status,
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
      Permission.bluetoothAdvertise,
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

  Future<void> _startSession() async {
    if (_facultyNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    _log('--- Starting session ---');

    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      _log('ERROR: Permissions denied');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth permissions required')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Generate session token
      _sessionToken = const Uuid().v4().substring(0, 8);
      _log('Generated token: $_sessionToken');

      // Create session in Supabase
      _log('Creating session in Supabase...');
      final response = await supabase.from('sessions').insert({
        'faculty_name': _facultyNameController.text.trim(),
        'session_token': _sessionToken,
        'status': 'active',
      }).select().single();

      _sessionId = response['id'];
      _log('Session created with ID: $_sessionId');

      // Start BLE advertising
      await _startAdvertising();

      // Subscribe to realtime attendance updates
      _subscribeToAttendance();

      setState(() {
        _isSessionActive = true;
        _isLoading = false;
      });
    } catch (e) {
      _log('ERROR starting session: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _startAdvertising() async {
    _log('Starting BLE advertising...');
    
    // Check support
    final isSupported = await _blePeripheral.isSupported;
    _log('Peripheral supported: $isSupported');
    if (!isSupported) {
      throw Exception('BLE Peripheral mode not supported');
    }

    final localName = 'ATT_$_sessionToken';
    _log('Advertising name: $localName');
    _log('Service UUID: $serviceUuid');

    final advertiseData = AdvertiseData(
      serviceUuid: serviceUuid,
      localName: localName,
    );

    final advertiseSettings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
      connectable: false,
    );

    _log('Calling _blePeripheral.start()...');
    await _blePeripheral.start(
      advertiseData: advertiseData,
      advertiseSettings: advertiseSettings,
    );

    // Verify advertising started
    await Future.delayed(const Duration(milliseconds: 500));
    final isAdvertising = await _blePeripheral.isAdvertising;
    _log('Advertising started: $isAdvertising');
    setState(() => _isAdvertising = isAdvertising);
  }

  Future<void> _stopAdvertising() async {
    try {
      _log('Stopping advertising...');
      await _blePeripheral.stop();
      setState(() => _isAdvertising = false);
      _log('Advertising stopped');
    } catch (e) {
      _log('Error stopping advertising: $e');
    }
  }

  void _subscribeToAttendance() {
    _log('Subscribing to realtime attendance...');
    _realtimeSubscription = supabase
        .from('attendance_records')
        .stream(primaryKey: ['id'])
        .eq('session_id', _sessionId!)
        .listen((data) {
          _log('Realtime update: ${data.length} records');
          if (mounted) {
            setState(() {
              _attendanceList = List<Map<String, dynamic>>.from(data);
            });
          }
        });
  }


  Future<void> _endSession() async {
    _log('--- Ending session ---');
    setState(() => _isLoading = true);

    try {
      await _stopAdvertising();
      _realtimeSubscription?.cancel();

      _log('Calling end_session RPC...');
      final response = await supabase.rpc('end_session', params: {
        'p_session_id': _sessionId,
      });
      _log('End session response: $response');

      if (mounted) {
        final count = response['total_attendance'] ?? _attendanceList.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session ended. Total: $count')),
        );

        setState(() {
          _isSessionActive = false;
          _isLoading = false;
          _sessionId = null;
          _sessionToken = null;
          _attendanceList = [];
        });
      }
    } catch (e) {
      _log('ERROR ending session: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _checkPeripheralSupport();
              _checkPermissions();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _isSessionActive
                ? null
                : () async {
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
            // Control section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_isSessionActive) ...[
                    TextField(
                      controller: _facultyNameController,
                      decoration: const InputDecoration(
                        labelText: 'Faculty Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _startSession,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Start Session'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isAdvertising ? Colors.green.shade100 : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isAdvertising ? Colors.green : Colors.orange,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isAdvertising ? Icons.bluetooth : Icons.bluetooth_disabled,
                                color: _isAdvertising ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isAdvertising ? 'Broadcasting' : 'Not Broadcasting',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _isAdvertising ? Colors.green : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Token: $_sessionToken'),
                          Text('Session ID: ${_sessionId?.substring(0, 8)}...'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${_attendanceList.length}',
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          const SizedBox(width: 8),
                          const Text('students checked in'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _endSession,
                      icon: const Icon(Icons.stop),
                      label: const Text('End Session'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
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
                        Tab(text: 'Attendance'),
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
                          // Attendance tab
                          _attendanceList.isEmpty
                              ? const Center(child: Text('No students yet'))
                              : ListView.builder(
                                  itemCount: _attendanceList.length,
                                  itemBuilder: (ctx, i) {
                                    final record = _attendanceList[i];
                                    return ListTile(
                                      leading: CircleAvatar(child: Text('${i + 1}')),
                                      title: Text(record['student_name'] ?? ''),
                                      subtitle: Text(record['roll_number'] ?? ''),
                                      trailing: Text(_formatTime(record['timestamp'])),
                                    );
                                  },
                                ),
                          // Status tab
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BLE Peripheral Supported: $_isPeripheralSupported',
                                  style: TextStyle(
                                    color: _isPeripheralSupported ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('Currently Advertising: $_isAdvertising'),
                                const Divider(),
                                const Text('Permissions:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ..._permissionStatuses.entries.map((e) => Text(
                                  '${e.key.toString().split('.').last}: ${e.value.toString().split('.').last}'
                                )),
                                const Divider(),
                                Text('Service UUID: $serviceUuid'),
                                if (_sessionToken != null) Text('Broadcast Name: ATT_$_sessionToken'),
                                if (_sessionId != null) Text('Session ID: $_sessionId'),
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

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
