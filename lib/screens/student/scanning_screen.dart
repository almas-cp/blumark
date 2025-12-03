import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;
import 'package:permission_handler/permission_handler.dart';
import '../../services/supabase_service.dart';
import '../../services/bluetooth_service.dart';
import '../../services/permission_service.dart';
import '../../utils/constants.dart';

class ScanningScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String department;
  final String batch;
  final int year;

  const ScanningScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.department,
    required this.batch,
    required this.year,
  });

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with SingleTickerProviderStateMixin {
  final _supabaseService = SupabaseService();
  final _bluetoothService = BluetoothService();

  bool _isScanning = false;
  bool _isProcessing = false;
  String _status = 'Ready to scan';
  String? _resultMessage;
  bool? _isSuccess;
  List<ScanResult> _foundDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scanSubscription?.cancel();
    _bluetoothService.stopScanning();
    super.dispose();
  }

  Future<void> _startScanning() async {
    if (_isScanning) return;

    setState(() {
      _foundDevices = [];
      _resultMessage = null;
      _isSuccess = null;
      _status = 'Checking permissions...';
    });

    // Check permissions
    final hasPermissions = await PermissionService.requestBluetoothScanPermissions();
    if (!hasPermissions) {
      setState(() => _status = 'Bluetooth permissions denied');
      _showPermissionDialog();
      return;
    }

    // Run pre-scan checks (Bluetooth, Location Services, etc.)
    final checkError = await _bluetoothService.preScanChecks();
    if (checkError != null) {
      setState(() => _status = checkError);
      
      // Show specific dialog for Location Services
      if (checkError.contains('Location Services')) {
        _showLocationServicesDialog();
      }
      return;
    }

    setState(() {
      _isScanning = true;
      _status = 'Scanning for sessions...';
    });

    _animationController.repeat();

    try {
      // Use aggressive scanning for better compatibility with OnePlus, Nothing, etc.
      final scanStream = await _bluetoothService.startAggressiveScanning(
        timeout: AppConstants.scanTimeout,
      );
      
      _scanSubscription = scanStream.listen((results) {
        setState(() => _foundDevices = results);
        _checkForSessionBeacon(results);
      });

      // Timeout handling
      Future.delayed(AppConstants.scanTimeout, () {
        if (_isScanning && mounted && !_isProcessing) {
          _stopScanning();
          setState(() {
            _status = 'No session found nearby';
            _resultMessage = _getNoSessionMessage();
            _isSuccess = false;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = 'Scan error: $e';
      });
      _animationController.stop();
    }
  }

  String _getNoSessionMessage() {
    return 'Could not find any active session.\n\n'
        'Please make sure:\n'
        '• You are near the faculty\'s device\n'
        '• Faculty has started the session\n'
        '• Bluetooth is ON\n'
        '• Location/GPS is ON';
  }

  void _showLocationServicesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Location Required'),
          ],
        ),
        content: const Text(
          'Bluetooth scanning on Android requires Location Services (GPS) to be enabled.\n\n'
          'This is an Android system requirement for Bluetooth Low Energy scanning.\n\n'
          'Please enable Location/GPS in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Open location settings
              if (Platform.isAndroid) {
                await openAppSettings();
              }
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _checkForSessionBeacon(List<ScanResult> results) {
    if (_isProcessing) return;

    final sessionToken = _bluetoothService.findSessionBeacon(results);
    if (sessionToken != null) {
      _handleFoundSession(sessionToken);
    }
  }

  Future<void> _handleFoundSession(String sessionToken) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = 'Session found! Verifying...';
    });

    await _bluetoothService.stopScanning();
    _scanSubscription?.cancel();
    _animationController.stop();

    try {
      // Get session by hex_ssid
      final session = await _supabaseService.getSessionByHexSsid(sessionToken);

      if (session == null) {
        setState(() {
          _isScanning = false;
          _isProcessing = false;
          _status = 'Session not found';
          _resultMessage = 'The session may have ended or is not active.';
          _isSuccess = false;
        });
        return;
      }

      // Verify department/batch/year match
      if (session.department != widget.department ||
          session.batch != widget.batch ||
          session.year != widget.year) {
        setState(() {
          _isScanning = false;
          _isProcessing = false;
          _status = 'Session mismatch';
          _resultMessage = 'This session is for ${session.department} - Batch ${session.batch} (Year ${session.year}).\nYou are in ${widget.department} - Batch ${widget.batch} (Year ${widget.year}).';
          _isSuccess = false;
        });
        return;
      }

      // Check if already marked
      final alreadyMarked = await _supabaseService.hasMarkedAttendance(
        studentId: widget.studentId,
        sessionId: session.id,
      );

      if (alreadyMarked) {
        setState(() {
          _isScanning = false;
          _isProcessing = false;
          _status = 'Already marked';
          _resultMessage = 'You have already marked your attendance for this session.';
          _isSuccess = true; // Show as success since they're present
        });
        return;
      }

      // Mark attendance
      setState(() => _status = 'Marking attendance...');
      
      final attendance = await _supabaseService.markAttendance(
        studentId: widget.studentId,
        sessionId: session.id,
      );

      if (attendance != null) {
        setState(() {
          _isScanning = false;
          _isProcessing = false;
          _status = 'Success!';
          _resultMessage = 'Your attendance has been marked successfully for Hour ${session.hour}!';
          _isSuccess = true;
        });
      } else {
        setState(() {
          _isScanning = false;
          _isProcessing = false;
          _status = 'Failed';
          _resultMessage = 'Failed to mark attendance. Please try again.';
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _isProcessing = false;
        _status = 'Error';
        _resultMessage = 'An error occurred: ${e.toString()}';
        _isSuccess = false;
      });
    }
  }

  void _stopScanning() {
    _bluetoothService.stopScanning();
    _scanSubscription?.cancel();
    _animationController.stop();
    setState(() {
      _isScanning = false;
      _status = 'Scan stopped';
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'Bluetooth and location permissions are required to scan for attendance sessions. '
          'Please grant these permissions in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              PermissionService.openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.studentName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.department} - Batch ${widget.batch} | Year ${widget.year}',
                        style: TextStyle(
                          color: Colors.blue.shade100,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Scanning Animation / Result
                  if (_resultMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _isSuccess! ? Colors.green.shade50 : Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isSuccess! ? Icons.check_circle : Icons.error,
                        size: 80,
                        color: _isSuccess! ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _isSuccess! ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _resultMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ] else ...[
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue.shade50,
                            boxShadow: _isScanning
                                ? [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.3 * (1 - _animationController.value)),
                                      blurRadius: 60 * _animationController.value,
                                      spreadRadius: 40 * _animationController.value,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            Icons.bluetooth_searching,
                            size: 80,
                            color: Colors.blue.shade700,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (_isScanning) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.blue.shade100,
                          valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 40),

                  // Found Devices Count (while scanning)
                  if (_isScanning && _foundDevices.isNotEmpty)
                    Text(
                      '${_foundDevices.length} devices found',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Action
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (_resultMessage != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Dashboard'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (_resultMessage != null) const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? _stopScanning : _startScanning,
                    icon: Icon(
                      _isScanning ? Icons.stop : Icons.bluetooth_searching,
                      size: 28,
                    ),
                    label: Text(
                      _isScanning
                          ? 'Stop Scanning'
                          : (_resultMessage != null ? 'Scan Again' : 'Start Scanning'),
                      style: const TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScanning ? Colors.red.shade600 : Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
