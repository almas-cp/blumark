import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_service.dart';
import '../../utils/constants.dart';

/// Manual Attendance Screen with Swipe Cards or List Tick methods
class ManualAttendanceScreen extends StatefulWidget {
  final String facultyId;

  const ManualAttendanceScreen({super.key, required this.facultyId});

  @override
  State<ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<ManualAttendanceScreen> {
  final _supabaseService = SupabaseService();

  // Mode: 'swipe' or 'tick'
  String _attendanceMode = 'swipe';

  // Session selection
  String _selectedDepartment = AppConstants.departments.first;
  String _selectedBatch = AppConstants.batches.first;
  int _selectedYear = AppConstants.years.first;
  int _selectedHour = AppConstants.hours.first;

  // State
  bool _isLoading = false;
  bool _isSessionStarted = false;
  List<Map<String, dynamic>> _students = [];
  
  // Attendance tracking: studentId -> present (true/false)
  final Map<String, bool> _attendance = {};
  
  // For swipe mode
  int _currentCardIndex = 0;
  final List<Map<String, dynamic>> _undoStack = [];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _attendanceMode = prefs.getString('manual_attendance_mode') ?? 'swipe';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manual_attendance_mode', _attendanceMode);
  }

  Future<void> _startSession() async {
    setState(() => _isLoading = true);

    try {
      // Fetch students matching the selection
      final students = await _supabaseService.getStudentsByClass(
        department: _selectedDepartment,
        batch: _selectedBatch,
        year: _selectedYear,
      );

      if (students.isEmpty) {
        _showError('No students found for this class');
        setState(() => _isLoading = false);
        return;
      }

      // Sort by roll number
      students.sort((a, b) => 
        (a['roll_number'] as int? ?? 0).compareTo(b['roll_number'] as int? ?? 0));

      setState(() {
        _students = students;
        _isSessionStarted = true;
        _currentCardIndex = 0;
        _attendance.clear();
        _undoStack.clear();
        
        // Initialize all as absent
        for (var student in students) {
          _attendance[student['id']] = false;
        }
      });
    } catch (e) {
      _showError('Failed to load students: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _markAttendance(String studentId, bool present) {
    // Save to undo stack before changing
    _undoStack.add({
      'studentId': studentId,
      'previousValue': _attendance[studentId],
      'cardIndex': _currentCardIndex,
    });

    setState(() {
      _attendance[studentId] = present;
      if (_attendanceMode == 'swipe' && _currentCardIndex < _students.length - 1) {
        _currentCardIndex++;
      }
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;

    final lastAction = _undoStack.removeLast();
    setState(() {
      _attendance[lastAction['studentId']] = lastAction['previousValue'];
      if (_attendanceMode == 'swipe') {
        _currentCardIndex = lastAction['cardIndex'];
      }
    });
  }

  Future<void> _submitAttendance() async {
    // Check if all students have been marked in swipe mode
    if (_attendanceMode == 'swipe' && _currentCardIndex < _students.length - 1) {
      final confirm = await _showConfirmDialog(
        'Not all students marked',
        'You have ${_students.length - _currentCardIndex - 1} students remaining. Submit anyway?',
      );
      if (!confirm) return;
    }

    setState(() => _isLoading = true);

    try {
      // Create session first
      final session = await _supabaseService.createSession(
        facultyId: widget.facultyId,
        date: DateTime.now(),
        hour: _selectedHour,
        department: _selectedDepartment,
        batch: _selectedBatch,
        year: _selectedYear,
      );

      // Mark attendance for each student
      int presentCount = 0;
      for (var student in _students) {
        final isPresent = _attendance[student['id']] ?? false;
        if (isPresent) {
          await _supabaseService.markAttendance(
            studentId: student['id'],
            sessionId: session.id,
          );
          presentCount++;
        }
      }

      // End the session
      await _supabaseService.endSession(session.id);

      if (!mounted) return;

      _showSuccess('Attendance saved! $presentCount/${_students.length} present');
      
      // Go back to dashboard
      Navigator.pop(context);
    } catch (e) {
      _showError('Failed to save attendance: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showModeSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attendance Mode',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.swipe,
                color: _attendanceMode == 'swipe' ? Colors.blue : Colors.grey,
              ),
              title: const Text('Swipe Cards'),
              subtitle: const Text('Tinder-style swipe right for present'),
              selected: _attendanceMode == 'swipe',
              onTap: () {
                setState(() => _attendanceMode = 'swipe');
                _savePreferences();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.checklist,
                color: _attendanceMode == 'tick' ? Colors.blue : Colors.grey,
              ),
              title: const Text('Checkbox List'),
              subtitle: const Text('Tick checkboxes for present students'),
              selected: _attendanceMode == 'tick',
              onTap: () {
                setState(() => _attendanceMode = 'tick');
                _savePreferences();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Manual Attendance'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (!_isSessionStarted)
            IconButton(
              icon: Icon(_attendanceMode == 'swipe' ? Icons.swipe : Icons.checklist),
              onPressed: _showModeSelector,
              tooltip: 'Change Mode',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isSessionStarted
              ? _buildAttendanceView()
              : _buildSessionSelector(),
    );
  }

  /// Session selection screen
  Widget _buildSessionSelector() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode indicator
          Card(
            child: ListTile(
              leading: Icon(
                _attendanceMode == 'swipe' ? Icons.swipe : Icons.checklist,
                color: Colors.blue,
              ),
              title: Text(
                _attendanceMode == 'swipe' ? 'Swipe Cards Mode' : 'Checkbox List Mode',
              ),
              subtitle: const Text('Tap settings icon to change'),
              trailing: IconButton(
                icon: const Icon(Icons.settings),
                onPressed: _showModeSelector,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Class selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Class',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  // Department
                  DropdownButtonFormField<String>(
                    value: _selectedDepartment,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    items: AppConstants.departments
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedDepartment = v!),
                  ),
                  const SizedBox(height: 16),

                  // Batch & Year row
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedBatch,
                          decoration: const InputDecoration(
                            labelText: 'Batch',
                            prefixIcon: Icon(Icons.group),
                            border: OutlineInputBorder(),
                          ),
                          items: AppConstants.batches
                              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedBatch = v!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            prefixIcon: Icon(Icons.calendar_today),
                            border: OutlineInputBorder(),
                          ),
                          items: AppConstants.years
                              .map((y) => DropdownMenuItem(value: y, child: Text('Year $y')))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedYear = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Hour
                  DropdownButtonFormField<int>(
                    value: _selectedHour,
                    decoration: const InputDecoration(
                      labelText: 'Hour',
                      prefixIcon: Icon(Icons.access_time),
                      border: OutlineInputBorder(),
                    ),
                    items: AppConstants.hours
                        .map((h) => DropdownMenuItem(value: h, child: Text('Hour $h')))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedHour = v!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Start button
          ElevatedButton.icon(
            onPressed: _startSession,
            icon: const Icon(Icons.play_arrow, size: 28),
            label: const Text('Start Attendance', style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Attendance view (swipe or tick mode)
  Widget _buildAttendanceView() {
    return Column(
      children: [
        // Header with class info
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_selectedDepartment - Batch $_selectedBatch',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Year $_selectedYear • Hour $_selectedHour',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              // Progress
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_attendance.values.where((v) => v).length}/${_students.length}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Text('Present', style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ),

        // Main content
        Expanded(
          child: _attendanceMode == 'swipe'
              ? _buildSwipeCards()
              : _buildTickList(),
        ),

        // Bottom bar
        _buildBottomBar(),
      ],
    );
  }

  /// Swipe cards mode
  Widget _buildSwipeCards() {
    if (_currentCardIndex >= _students.length) {
      return Center(
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
              '${_attendance.values.where((v) => v).length} present, ${_attendance.values.where((v) => !v).length} absent',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final student = _students[_currentCardIndex];

    return Column(
      children: [
        // Progress indicator
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_currentCardIndex + 1) / _students.length,
                backgroundColor: Colors.grey.shade300,
                valueColor: const AlwaysStoppedAnimation(Colors.blue),
              ),
              const SizedBox(height: 8),
              Text(
                '${_currentCardIndex + 1} of ${_students.length}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),

        // Card with AnimatedSwitcher for smooth transitions
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildStudentCard(student),
            ),
          ),
        ),

        // Action buttons - Present / Absent
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Absent button
              GestureDetector(
                onTap: () => _markAttendance(student['id'], false),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.shade400, width: 3),
                  ),
                  child: Icon(Icons.close, color: Colors.red.shade600, size: 40),
                ),
              ),
              
              // Present button
              GestureDetector(
                onTap: () => _markAttendance(student['id'], true),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green.shade400, width: 3),
                  ),
                  child: Icon(Icons.check, color: Colors.green.shade600, size: 40),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return Container(
      key: ValueKey(student['id']),
      width: 280,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Roll number circle
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              '${student['roll_number'] ?? '?'}',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Roll number badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Roll No. ${student['roll_number'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              student['name'] ?? 'Unknown',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Email
          Text(
            student['email'] ?? '',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// Tick list mode
  Widget _buildTickList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final student = _students[index];
        final isPresent = _attendance[student['id']] ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: CheckboxListTile(
            value: isPresent,
            onChanged: (value) {
              _markAttendance(student['id'], value ?? false);
            },
            activeColor: Colors.green,
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isPresent ? Colors.green.shade100 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${student['roll_number'] ?? index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isPresent ? Colors.green.shade700 : Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student['name'] ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        student['email'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            secondary: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isPresent ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isPresent ? 'P' : 'A',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPresent ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Bottom bar with undo and submit
  Widget _buildBottomBar() {
    return Container(
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
      child: Row(
        children: [
          // Undo button
          if (_undoStack.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _undo,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          if (_undoStack.isNotEmpty) const SizedBox(width: 12),

          // Submit button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _submitAttendance,
              icon: const Icon(Icons.save),
              label: Text(
                'Submit (${_attendance.values.where((v) => v).length} Present)',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
