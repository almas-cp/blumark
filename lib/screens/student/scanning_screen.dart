import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;
import 'package:permission_handler/permission_handler.dart';
import '../../models/session.dart';
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

/// Represents a discovered session with its validity status
class DiscoveredSession {
  final AttendanceSession session;
  final bool isValid; // Matches student's department/batch/year
  final String? invalidReason;
  final int rssi; // Signal strength

  DiscoveredSession({
    required this.session,
    required this.isValid,
    this.invalidReason,
    this.rssi = 0,
  });
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

  // Track discovered sessions
  final Map<String, DiscoveredSession> _discoveredSessions = {};
  final Set<String> _processingTokens = {}; // Tokens currently being fetched

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
      _discoveredSessions.clear();
      _processingTokens.clear();
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

      // Timeout handling - only show error if NO sessions found
      Future.delayed(AppConstants.scanTimeout, () {
        if (_isScanning && mounted && !_isProcessing) {
          _stopScanning();
          // Only show error if no sessions were discovered
          if (_discoveredSessions.isEmpty) {
            setState(() {
              _status = 'No session found nearby';
              _resultMessage = _getNoSessionMessage();
              _isSuccess = false;
            });
          }
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
    // Find ALL BluMark beacons, not just the first one
    final foundTokens = _findAllSessionBeacons(results);
    
    for (final entry in foundTokens.entries) {
      final token = entry.key;
      final rssi = entry.value;
      
      // Skip if already discovered or currently being processed
      if (_discoveredSessions.containsKey(token) || _processingTokens.contains(token)) {
        continue;
      }
      
      // Fetch session details in background
      _fetchSessionDetails(token, rssi);
    }
  }

  /// Find all BluMark session beacons from scan results
  /// Returns a map of session token -> RSSI
  Map<String, int> _findAllSessionBeacons(List<ScanResult> results) {
    final Map<String, int> tokens = {};
    
    for (var result in results) {
      String? token;
      
      // Check platform name
      final platformName = result.device.platformName;
      if (platformName.startsWith(AppConstants.bleDevicePrefix)) {
        token = platformName.substring(AppConstants.bleDevicePrefix.length);
      }
      
      // Check advertisement name
      if (token == null) {
        final advName = result.advertisementData.advName;
        if (advName.startsWith(AppConstants.bleDevicePrefix)) {
          token = advName.substring(AppConstants.bleDevicePrefix.length);
        }
      }
      
      if (token != null && token.isNotEmpty) {
        tokens[token] = result.rssi;
      }
    }
    
    return tokens;
  }

  /// Fetch session details from database
  Future<void> _fetchSessionDetails(String token, int rssi) async {
    _processingTokens.add(token);
    
    try {
      final session = await _supabaseService.getSessionByHexSsid(token);
      
      if (session != null && mounted) {
        // Check if session matches student's department/batch/year
        final isValid = session.department == widget.department &&
            session.batch == widget.batch &&
            session.year == widget.year;
        
        String? invalidReason;
        if (!isValid) {
          invalidReason = '${session.department} - Batch ${session.batch} (Year ${session.year})';
        }
        
        setState(() {
          _discoveredSessions[token] = DiscoveredSession(
            session: session,
            isValid: isValid,
            invalidReason: invalidReason,
            rssi: rssi,
          );
        });
      }
    } catch (e) {
      // Ignore errors for individual sessions
    } finally {
      _processingTokens.remove(token);
    }
  }

  /// Handle user selecting a session to mark attendance
  Future<void> _selectSession(DiscoveredSession discovered) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = 'Marking attendance...';
    });

    // Stop scanning when user selects
    await _bluetoothService.stopScanning();
    _scanSubscription?.cancel();
    _animationController.stop();
    setState(() => _isScanning = false);

    try {
      final session = discovered.session;

      // Check if already marked
      final alreadyMarked = await _supabaseService.hasMarkedAttendance(
        studentId: widget.studentId,
        sessionId: session.id,
      );

      if (alreadyMarked) {
        setState(() {
          _isProcessing = false;
          _status = 'Already marked';
          _resultMessage = 'You have already marked your attendance for this session.';
          _isSuccess = true;
        });
        return;
      }

      // Mark attendance
      final attendance = await _supabaseService.markAttendance(
        studentId: widget.studentId,
        sessionId: session.id,
      );

      if (attendance != null) {
        setState(() {
          _isProcessing = false;
          _status = 'Success!';
          _resultMessage = 'Your attendance has been marked successfully for Hour ${session.hour}!';
          _isSuccess = true;
        });
      } else {
        setState(() {
          _isProcessing = false;
          _status = 'Failed';
          _resultMessage = 'Failed to mark attendance. Please try again.';
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
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
      _status = _discoveredSessions.isEmpty ? 'Scan stopped' : 'Select a session';
    });
  }

  /// Get sorted list of discovered sessions (valid first, then by signal strength)
  List<DiscoveredSession> get _sortedSessions {
    final sessions = _discoveredSessions.values.toList();
    sessions.sort((a, b) {
      // Valid sessions first
      if (a.isValid && !b.isValid) return -1;
      if (!a.isValid && b.isValid) return 1;
      // Then by signal strength (higher is better)
      return b.rssi.compareTo(a.rssi);
    });
    return sessions;
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

                  const SizedBox(height: 20),

                  // Found Devices Count (while scanning)
                  if (_foundDevices.isNotEmpty)
                    Text(
                      '${_foundDevices.length} BLE devices nearby',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Discovered Sessions Panel
          if (_discoveredSessions.isNotEmpty && _resultMessage == null)
            _buildSessionsPanel(),

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
                    onPressed: _isProcessing ? null : (_isScanning ? _stopScanning : _startScanning),
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

  /// Build the floating panel showing discovered sessions
  Widget _buildSessionsPanel() {
    final sessions = _sortedSessions;
    final validCount = sessions.where((s) => s.isValid).length;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sessions Found (${sessions.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      if (validCount > 0)
                        Text(
                          '$validCount matching your class',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isScanning)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                    ),
                  ),
              ],
            ),
          ),
          
          // Sessions List
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final discovered = sessions[index];
                return _buildSessionTile(discovered);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single session tile
  Widget _buildSessionTile(DiscoveredSession discovered) {
    final session = discovered.session;
    final isValid = discovered.isValid;
    
    return InkWell(
      onTap: isValid && !_isProcessing ? () => _selectSession(discovered) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          children: [
            // Status Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isValid ? Colors.green.shade50 : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isValid ? Icons.check_circle : Icons.block,
                color: isValid ? Colors.green : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            
            // Session Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${session.department} - Batch ${session.batch}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isValid ? Colors.black : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isValid ? Colors.green.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Hour ${session.hour}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isValid ? Colors.green.shade700 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isValid 
                        ? 'Year ${session.year} • ${session.facultyName ?? 'Faculty'}'
                        : discovered.invalidReason ?? 'Not for your class',
                    style: TextStyle(
                      fontSize: 12,
                      color: isValid ? Colors.grey.shade600 : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            
            // Signal Strength & Action
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Signal strength indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getSignalIcon(discovered.rssi),
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${discovered.rssi} dBm',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                if (isValid) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tap to mark',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Get signal strength icon based on RSSI
  IconData _getSignalIcon(int rssi) {
    if (rssi > -50) return Icons.signal_cellular_4_bar;
    if (rssi > -60) return Icons.signal_cellular_alt;
    if (rssi > -70) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }
}
