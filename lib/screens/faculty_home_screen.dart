import 'dart:async';
import 'dart:convert';
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
  String? _sessionId;
  String? _sessionToken;
  List<Map<String, dynamic>> _attendanceList = [];
  StreamSubscription? _realtimeSubscription;

  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  @override
  void dispose() {
    _facultyNameController.dispose();
    _realtimeSubscription?.cancel();
    _stopAdvertising();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

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

    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth permissions required')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Generate session token (short enough for BLE advertising)
      _sessionToken = const Uuid().v4().substring(0, 8);

      // Create session in Supabase
      final response = await supabase.from('sessions').insert({
        'faculty_name': _facultyNameController.text.trim(),
        'session_token': _sessionToken,
        'status': 'active',
      }).select().single();

      _sessionId = response['id'];

      // Start BLE advertising
      await _startAdvertising();

      // Subscribe to realtime attendance updates
      _subscribeToAttendance();

      setState(() {
        _isSessionActive = true;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start session: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _startAdvertising() async {
    final advertiseData = AdvertiseData(
      serviceUuid: serviceUuid,
      manufacturerData: utf8.encode(_sessionToken!),
    );

    // Also set device name with token prefix for easier detection
    final advertiseSettings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
      connectable: false,
      timeout: 0,
    );

    await _blePeripheral.start(
      advertiseData: advertiseData,
      advertiseSettings: advertiseSettings,
    );
  }

  Future<void> _stopAdvertising() async {
    try {
      await _blePeripheral.stop();
    } catch (_) {}
  }

  void _subscribeToAttendance() {
    _realtimeSubscription = supabase
        .from('attendance_records')
        .stream(primaryKey: ['id'])
        .eq('session_id', _sessionId!)
        .listen((data) {
          if (mounted) {
            setState(() {
              _attendanceList = List<Map<String, dynamic>>.from(data);
            });
          }
        });
  }


  Future<void> _endSession() async {
    setState(() => _isLoading = true);

    try {
      await _stopAdvertising();
      _realtimeSubscription?.cancel();

      final response = await supabase.rpc('end_session', params: {
        'p_session_id': _sessionId,
      });

      if (mounted) {
        final count = response['total_attendance'] ?? _attendanceList.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session ended. Total attendance: $count')),
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
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ending session: ${e.toString()}')),
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
        child: Padding(
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
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _startSession,
                    icon: const Icon(Icons.play_arrow),
                    label: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Start Attendance Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bluetooth, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'Session Active',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Token: $_sessionToken',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${_attendanceList.length}',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const Text(
                        'Students Checked In',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Attendance List',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _attendanceList.isEmpty
                      ? const Center(
                          child: Text(
                            'Waiting for students...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _attendanceList.length,
                          itemBuilder: (context, index) {
                            final record = _attendanceList[index];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(record['student_name'] ?? ''),
                                subtitle: Text(record['roll_number'] ?? ''),
                                trailing: Text(
                                  _formatTime(record['timestamp']),
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _endSession,
                    icon: const Icon(Icons.stop),
                    label: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('End Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
