import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../utils/constants.dart';
import 'live_attendance_screen.dart';

class SessionCreationScreen extends StatefulWidget {
  final String facultyId;
  final String facultyName;

  const SessionCreationScreen({
    super.key,
    required this.facultyId,
    required this.facultyName,
  });

  @override
  State<SessionCreationScreen> createState() => _SessionCreationScreenState();
}

class _SessionCreationScreenState extends State<SessionCreationScreen> {
  final _supabaseService = SupabaseService();

  String _selectedDepartment = AppConstants.departments.first;
  String _selectedBatch = AppConstants.batches.first;
  int _selectedYear = AppConstants.years.first;
  int _selectedHour = AppConstants.hours.first;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _createSession() async {
    setState(() => _isLoading = true);

    try {
      final session = await _supabaseService.createSession(
        facultyId: widget.facultyId,
        date: _selectedDate,
        hour: _selectedHour,
        department: _selectedDepartment,
        batch: _selectedBatch,
        year: _selectedYear,
      );

      if (!mounted) return;

      // Navigate to live attendance screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LiveAttendanceScreen(
            session: session,
            facultyName: widget.facultyName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create session: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Create Session'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Configure the session details below. Students matching these criteria will be able to mark attendance.',
                      style: TextStyle(color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Date Selection
            _buildSectionTitle('Date'),
            InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.calendar_today, color: Colors.orange.shade700),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _formatDate(_selectedDate),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Department Selection
            _buildSectionTitle('Department'),
            _buildOptionSelector(
              options: AppConstants.departments,
              selected: _selectedDepartment,
              onSelect: (value) => setState(() => _selectedDepartment = value),
              icon: Icons.school,
              color: Colors.purple,
            ),

            const SizedBox(height: 24),

            // Batch Selection
            _buildSectionTitle('Batch'),
            _buildOptionSelector(
              options: AppConstants.batches,
              selected: _selectedBatch,
              onSelect: (value) => setState(() => _selectedBatch = value),
              icon: Icons.group,
              color: Colors.teal,
            ),

            const SizedBox(height: 24),

            // Year Selection
            _buildSectionTitle('Year'),
            _buildOptionSelector(
              options: AppConstants.years.map((y) => y.toString()).toList(),
              selected: _selectedYear.toString(),
              onSelect: (value) => setState(() => _selectedYear = int.parse(value)),
              icon: Icons.calendar_view_day,
              color: Colors.indigo,
            ),

            const SizedBox(height: 24),

            // Hour/Period Selection
            _buildSectionTitle('Hour / Period'),
            _buildOptionSelector(
              options: AppConstants.hours.map((h) => h.toString()).toList(),
              selected: _selectedHour.toString(),
              onSelect: (value) => setState(() => _selectedHour = int.parse(value)),
              icon: Icons.access_time,
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
                  _buildSummaryRow('Faculty', widget.facultyName),
                  _buildSummaryRow('Department', _selectedDepartment),
                  _buildSummaryRow('Batch', _selectedBatch),
                  _buildSummaryRow('Year', _selectedYear.toString()),
                  _buildSummaryRow('Hour', _selectedHour.toString()),
                  _buildSummaryRow('Date', _formatDate(_selectedDate)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Create Button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _createSession,
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
                _isLoading ? 'Creating...' : 'Create Session',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
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
      ),
    );
  }

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

  Widget _buildOptionSelector({
    required List<String> options,
    required String selected,
    required Function(String) onSelect,
    required IconData icon,
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
