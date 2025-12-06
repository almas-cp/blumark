import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/session.dart';
import '../../models/attendance.dart';
import '../../services/supabase_service.dart';
import '../../services/bluetooth_service.dart';
import '../../services/permission_service.dart';
import '../../utils/device_id_encoder.dart';
import 'faculty_dashboard.dart';

class LiveAttendanceScreen extends StatefulWidget {
  final AttendanceSession session;
  final String facultyName;

  const LiveAttendanceScreen({
    super.key,
    required this.session,
    required this.facultyName,
  });

  @override
  State<LiveAttendanceScreen> createState() => _LiveAttendanceScreenState();
}

class _LiveAttendanceScreenState extends State<LiveAttendanceScreen> {
  final _supabaseService = SupabaseService();
  final _bluetoothService = BluetoothService();

  bool _isAdvertising = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _sessionToken;
  String? _errorMessage;
  List<Attendance> _attendanceList = [];
  List<Map<String, dynamic>> _allStudents = [];
  Set<String> _markedStudentIds = {};
  StreamSubscription? _realtimeSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
    _loadAllStudents();
  }

  Future<void> _loadAllStudents() async {
    try {
      final students = await _supabaseService.getStudentsByClass(
        department: widget.session.department,
        batch: widget.session.batch,
        year: widget.session.year,
      );
      if (mounted) {
        setState(() => _allStudents = students);
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _refreshTimer?.cancel();
    _stopAdvertising();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    try {
      await _bluetoothService.initialize();
      
      final isSupported = await _bluetoothService.isPeripheralSupported();
      if (!isSupported) {
        setState(() {
          _errorMessage = 'BLE Peripheral mode is not supported on this device';
        });
        return;
      }

      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize Bluetooth: $e';
      });
    }
  }

  Future<void> _startAdvertising() async {
    setState(() => _isLoading = true);

    try {
      // Request permissions
      final hasPermissions = await PermissionService.requestBluetoothAdvertisePermissions();
      if (!hasPermissions) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions are required'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Generate session token (hex_ssid)
      _sessionToken = DeviceIdEncoder.encodeForBle(widget.session.id);

      // Update session with hex_ssid
      await _supabaseService.updateSessionHexSsid(
        widget.session.id,
        _sessionToken!,
      );

      // Start advertising
      await _bluetoothService.startAdvertising(_sessionToken!);

      // Subscribe to attendance updates
      _subscribeToAttendance();

      setState(() {
        _isAdvertising = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to start advertising: $e';
      });
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await _bluetoothService.stopAdvertising();
      setState(() => _isAdvertising = false);
    } catch (e) {
      // Ignore errors when stopping
    }
  }

  void _subscribeToAttendance() {
    // Load initial attendance immediately
    _loadAttendance();
    
    // Subscribe to realtime updates
    _realtimeSubscription = _supabaseService.subscribeToSessionAttendance(
      widget.session.id,
      (attendanceList) {
        if (mounted) {
          setState(() => _attendanceList = attendanceList);
        }
      },
    );

    // Also start periodic refresh every 3 seconds as backup
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadAttendance();
    });
  }

  Future<void> _loadAttendance() async {
    try {
      final list = await _supabaseService.getSessionAttendance(widget.session.id);
      if (mounted) {
        setState(() {
          _attendanceList = list;
          _markedStudentIds = list.map((a) => a.studentId).toSet();
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  void _openManualAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ManualBleAttendanceScreen(
          session: widget.session,
          allStudents: _allStudents,
          markedStudentIds: _markedStudentIds,
          onRefresh: _loadAttendance,
        ),
      ),
    );
  }

  Future<void> _stopSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session'),
        content: Text(
          'Are you sure you want to end this session?\n\n'
          'Total attendance: ${_attendanceList.length} students',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await _stopAdvertising();
      await _supabaseService.endSession(widget.session.id);
      _realtimeSubscription?.cancel();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session ended. Total: ${_attendanceList.length} students'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const FacultyDashboard()),
        (_) => false,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error ending session: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Live Attendance'),
        backgroundColor: _isAdvertising ? Colors.green.shade600 : Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          if (!_isAdvertising)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
      body: Column(
        children: [
          // Status Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _isAdvertising ? Colors.green.shade600 : Colors.blue.shade700,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Session Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSessionInfoItem(
                        'Department',
                        widget.session.department,
                      ),
                      _buildSessionInfoItem(
                        'Batch',
                        widget.session.batch,
                      ),
                      _buildSessionInfoItem(
                        'Year',
                        widget.session.year.toString(),
                      ),
                      _buildSessionInfoItem(
                        'Hour',
                        widget.session.hour.toString(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Bluetooth Status
                if (_isAdvertising) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bluetooth,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Broadcasting',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Students can now mark attendance',
                            style: TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'HEX SSID: $_sessionToken',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ] else if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Attendance Counter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${_attendanceList.length}',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Students',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Marked attendance',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Manual Attendance Button
          if (_isAdvertising && _allStudents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: OutlinedButton.icon(
                onPressed: _openManualAttendance,
                icon: const Icon(Icons.person_add),
                label: Text(
                  'Manual Attendance (${_allStudents.length - _markedStudentIds.length} remaining)',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  side: BorderSide(color: Colors.orange.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Attendance List
          Expanded(
            child: _buildBleAttendanceList(),
          ),

          // Bottom Action Button
          Padding(
            padding: const EdgeInsets.all(20),
            child: _isAdvertising
                ? ElevatedButton.icon(
                    onPressed: _isLoading ? null : _stopSession,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.stop),
                    label: const Text('Stop Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: (_isLoading || !_isInitialized) ? null : _startAdvertising,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bluetooth, size: 28),
                    label: Text(
                      _isLoading ? 'Starting...' : 'Start Bluetooth Beacon',
                      style: const TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionInfoItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// BLE attendance list (original view)
  Widget _buildBleAttendanceList() {
    if (_attendanceList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _isAdvertising
                  ? 'Waiting for students...'
                  : 'Start broadcasting to receive attendance',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _attendanceList.length,
      itemBuilder: (context, index) {
        final attendance = _attendanceList[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.green.shade100,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attendance.studentName ?? 'Student',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (attendance.studentEmail != null)
                      Text(
                        attendance.studentEmail!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.check_circle,
                color: Colors.green.shade600,
              ),
            ],
          ),
        );
      },
    );
  }

}

/// Separate screen for manual attendance during BLE session
class _ManualBleAttendanceScreen extends StatefulWidget {
  final AttendanceSession session;
  final List<Map<String, dynamic>> allStudents;
  final Set<String> markedStudentIds;
  final VoidCallback onRefresh;

  const _ManualBleAttendanceScreen({
    required this.session,
    required this.allStudents,
    required this.markedStudentIds,
    required this.onRefresh,
  });

  @override
  State<_ManualBleAttendanceScreen> createState() => _ManualBleAttendanceScreenState();
}

class _ManualBleAttendanceScreenState extends State<_ManualBleAttendanceScreen> {
  final _supabaseService = SupabaseService();
  late Set<String> _markedStudentIds;
  final Set<String> _selectedStudentIds = {}; // Local selection before save
  bool _isSaving = false;
  StreamSubscription? _realtimeSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _markedStudentIds = Set.from(widget.markedStudentIds);
    _subscribeToAttendance();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _subscribeToAttendance() {
    // Load initial
    _loadAttendance();

    // Subscribe to realtime updates
    _realtimeSubscription = _supabaseService.subscribeToSessionAttendance(
      widget.session.id,
      (attendanceList) {
        if (mounted) {
          setState(() {
            _markedStudentIds = attendanceList.map((a) => a.studentId).toSet();
          });
        }
      },
    );

    // Periodic refresh as backup
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadAttendance();
    });
  }

  Future<void> _loadAttendance() async {
    try {
      final list = await _supabaseService.getSessionAttendance(widget.session.id);
      if (mounted) {
        setState(() {
          _markedStudentIds = list.map((a) => a.studentId).toSet();
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  void _toggleSelection(String studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
      }
    });
  }

  Future<void> _saveAttendance() async {
    if (_selectedStudentIds.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      // Mark all selected students
      for (final studentId in _selectedStudentIds) {
        await _supabaseService.markAttendance(
          studentId: studentId,
          sessionId: widget.session.id,
        );
      }

      // Update local state
      setState(() {
        _markedStudentIds.addAll(_selectedStudentIds);
        _selectedStudentIds.clear();
      });

      // Refresh parent
      widget.onRefresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance saved'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get unmarked students in proper order (by roll number)
    final unmarkedStudents = widget.allStudents
        .where((s) => !_markedStudentIds.contains(s['id']))
        .toList()
      ..sort((a, b) => (a['roll_number'] ?? 0).compareTo(b['roll_number'] ?? 0));

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          'Manual (${_markedStudentIds.length}/${widget.allStudents.length})',
        ),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // BLE indicator
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bluetooth, size: 16),
                SizedBox(width: 4),
                Text('Live', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      body: unmarkedStudents.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 80, color: Colors.green.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'All students marked!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_markedStudentIds.length} students present',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Student list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: unmarkedStudents.length,
                    itemBuilder: (context, index) {
                      final student = unmarkedStudents[index];
                      final isSelected = _selectedStudentIds.contains(student['id']);
                      return _buildStudentTile(student, isSelected);
                    },
                  ),
                ),

                // Save button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _selectedStudentIds.isEmpty || _isSaving
                        ? null
                        : _saveAttendance,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving
                          ? 'Saving...'
                          : 'Save (${_selectedStudentIds.length} selected)',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentTile(Map<String, dynamic> student, bool isSelected) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: isSelected ? Colors.green.shade50 : Colors.white,
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (_) => _toggleSelection(student['id']),
        activeColor: Colors.green,
        controlAffinity: ListTileControlAffinity.trailing,
        secondary: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.green.shade100 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${student['roll_number'] ?? '?'}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.green.shade700 : Colors.grey.shade700,
            ),
          ),
        ),
        title: Text(
          student['name'] ?? 'Unknown',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.green.shade700 : Colors.black87,
          ),
        ),
      ),
    );
  }
}
