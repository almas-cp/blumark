import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isCompleted = false;
  List<Map<String, dynamic>> _students = [];
  String _facultyName = '';
  DateTime _submittedAt = DateTime.now();
  
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
      _facultyName = prefs.getString(AppConstants.prefUserName) ?? 'Faculty';
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

      // Mark attendance for each present student
      for (var student in _students) {
        final isPresent = _attendance[student['id']] ?? false;
        if (isPresent) {
          await _supabaseService.markAttendance(
            studentId: student['id'],
            sessionId: session.id,
          );
        }
      }

      // End the session
      await _supabaseService.endSession(session.id);

      if (!mounted) return;

      // Show completion screen with copy options
      setState(() {
        _isCompleted = true;
        _submittedAt = DateTime.now();
      });
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
          : _isCompleted
              ? _buildCompletionScreen()
              : _isSessionStarted
                  ? _buildAttendanceView()
                  : _buildSessionSelector(),
    );
  }

  // ==================== COPY METHODS ====================

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  String _buildAttendanceMessage({required String filter}) {
    final buffer = StringBuffer();
    
    // Header
    buffer.writeln('📋 *ATTENDANCE REPORT*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');
    buffer.writeln('👨‍🏫 *Faculty:* $_facultyName');
    buffer.writeln('📅 *Date:* ${_formatDateTime(_submittedAt)}');
    buffer.writeln('🏫 *Class:* $_selectedDepartment - Batch $_selectedBatch');
    buffer.writeln('📚 *Year:* $_selectedYear | *Hour:* $_selectedHour');
    buffer.writeln('');
    
    // Get filtered students
    List<Map<String, dynamic>> filteredStudents;
    String title;
    
    if (filter == 'present') {
      filteredStudents = _students.where((s) => _attendance[s['id']] == true).toList();
      title = '✅ PRESENT STUDENTS';
    } else if (filter == 'absent') {
      filteredStudents = _students.where((s) => _attendance[s['id']] != true).toList();
      title = '❌ ABSENT STUDENTS';
    } else {
      filteredStudents = _students;
      title = '📝 ALL STUDENTS';
    }
    
    // Count
    final presentCount = _attendance.values.where((v) => v).length;
    final absentCount = _students.length - presentCount;
    buffer.writeln('📊 *Summary:* $presentCount Present | $absentCount Absent');
    buffer.writeln('');
    buffer.writeln('*$title (${filteredStudents.length})*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    
    // Student list
    for (var student in filteredStudents) {
      final isPresent = _attendance[student['id']] == true;
      final status = isPresent ? '✅' : '❌';
      final roll = student['roll_number'] ?? '?';
      final name = student['name'] ?? 'Unknown';
      buffer.writeln('$status  $roll. $name');
    }
    
    buffer.writeln('');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('_Generated by BluMark_');
    
    return buffer.toString();
  }

  void _copyToClipboard(String filter) {
    final message = _buildAttendanceMessage(filter: filter);
    Clipboard.setData(ClipboardData(text: message));
    
    String label;
    if (filter == 'present') {
      label = 'Present students';
    } else if (filter == 'absent') {
      label = 'Absent students';
    } else {
      label = 'Full attendance';
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Completion screen with copy options
  Widget _buildCompletionScreen() {
    final presentCount = _attendance.values.where((v) => v).length;
    final absentCount = _students.length - presentCount;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          
          // Success icon
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.green.shade600,
            ),
          ),
          const SizedBox(height: 24),
          
          const Text(
            'Attendance Saved!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatDateTime(_submittedAt),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          
          // Summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '$_selectedDepartment - Batch $_selectedBatch',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('Year $_selectedYear • Hour $_selectedHour'),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatItem('Present', presentCount, Colors.green),
                      Container(width: 1, height: 40, color: Colors.grey.shade300),
                      _buildStatItem('Absent', absentCount, Colors.red),
                      Container(width: 1, height: 40, color: Colors.grey.shade300),
                      _buildStatItem('Total', _students.length, Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Copy options
          const Text(
            'Copy Attendance Report',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // Full class button
          _buildCopyButton(
            icon: Icons.groups,
            label: 'Full Class Report',
            subtitle: 'All ${_students.length} students',
            color: Colors.blue,
            onTap: () => _copyToClipboard('all'),
          ),
          const SizedBox(height: 12),
          
          // Present only button
          _buildCopyButton(
            icon: Icons.check_circle,
            label: 'Present Students Only',
            subtitle: '$presentCount students',
            color: Colors.green,
            onTap: () => _copyToClipboard('present'),
          ),
          const SizedBox(height: 12),
          
          // Absent only button
          _buildCopyButton(
            icon: Icons.cancel,
            label: 'Absent Students Only',
            subtitle: '$absentCount students',
            color: Colors.red,
            onTap: () => _copyToClipboard('absent'),
          ),
          const SizedBox(height: 32),
          
          // Done button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.done),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCopyButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.copy, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  /// Session selection screen - matches BLE session creation UI
  Widget _buildSessionSelector() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Manual attendance mode. Select the class details below to load the student list.',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Mode Selection
          _buildSectionTitle('Attendance Mode'),
          _buildModeSelector(),

          const SizedBox(height: 24),

          // Department Selection
          _buildSectionTitle('Department'),
          _buildOptionSelector(
            options: AppConstants.departments,
            selected: _selectedDepartment,
            onSelect: (value) => setState(() => _selectedDepartment = value),
            color: Colors.purple,
          ),

          const SizedBox(height: 24),

          // Batch Selection
          _buildSectionTitle('Batch'),
          _buildOptionSelector(
            options: AppConstants.batches,
            selected: _selectedBatch,
            onSelect: (value) => setState(() => _selectedBatch = value),
            color: Colors.teal,
          ),

          const SizedBox(height: 24),

          // Year Selection
          _buildSectionTitle('Year'),
          _buildOptionSelector(
            options: AppConstants.years.map((y) => y.toString()).toList(),
            selected: _selectedYear.toString(),
            onSelect: (value) => setState(() => _selectedYear = int.parse(value)),
            color: Colors.indigo,
          ),

          const SizedBox(height: 24),

          // Hour/Period Selection
          _buildSectionTitle('Hour / Period'),
          _buildOptionSelector(
            options: AppConstants.hours.map((h) => h.toString()).toList(),
            selected: _selectedHour.toString(),
            onSelect: (value) => setState(() => _selectedHour = int.parse(value)),
            color: Colors.pink,
          ),

          const SizedBox(height: 32),

          // Summary Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Session Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSummaryRow('Faculty', _facultyName),
                _buildSummaryRow('Department', _selectedDepartment),
                _buildSummaryRow('Batch', _selectedBatch),
                _buildSummaryRow('Year', _selectedYear.toString()),
                _buildSummaryRow('Hour', _selectedHour.toString()),
                _buildSummaryRow('Mode', _attendanceMode == 'swipe' ? 'Swipe Cards' : 'Checkbox List'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Start button
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _startSession,
            icon: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 28),
            label: Text(
              _isLoading ? 'Loading...' : 'Start Attendance',
              style: const TextStyle(fontSize: 18),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 24),
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

  // ==================== UI HELPER WIDGETS ====================

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _attendanceMode = 'swipe');
                _savePreferences();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _attendanceMode == 'swipe' ? Colors.orange.shade100 : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swipe,
                      size: 20,
                      color: _attendanceMode == 'swipe' ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Swipe Cards',
                      style: TextStyle(
                        fontWeight: _attendanceMode == 'swipe' ? FontWeight.bold : FontWeight.normal,
                        color: _attendanceMode == 'swipe' ? Colors.orange.shade700 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _attendanceMode = 'tick');
                _savePreferences();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _attendanceMode == 'tick' ? Colors.orange.shade100 : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.checklist,
                      size: 20,
                      color: _attendanceMode == 'tick' ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Checkbox List',
                      style: TextStyle(
                        fontWeight: _attendanceMode == 'tick' ? FontWeight.bold : FontWeight.normal,
                        color: _attendanceMode == 'tick' ? Colors.orange.shade700 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionSelector({
    required List<String> options,
    required String selected,
    required Function(String) onSelect,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = option == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? color.shade100 : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  option,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? color.shade700 : Colors.grey.shade600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
