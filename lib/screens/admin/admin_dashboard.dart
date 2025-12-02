import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_service.dart';
import '../../utils/constants.dart';
import '../login_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabaseService = SupabaseService();

  // Faculty form
  final _facultyNameController = TextEditingController();
  final _facultyEmailController = TextEditingController();
  final _facultyPasswordController = TextEditingController();

  // Student form
  final _studentNameController = TextEditingController();
  final _studentEmailController = TextEditingController();
  final _studentPasswordController = TextEditingController();
  String _selectedDepartment = AppConstants.departments.first;
  String _selectedBatch = AppConstants.batches.first;
  int _selectedYear = AppConstants.years.first;

  bool _isLoading = false;
  List<Map<String, dynamic>> _facultyList = [];
  List<Map<String, dynamic>> _studentList = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _facultyNameController.dispose();
    _facultyEmailController.dispose();
    _facultyPasswordController.dispose();
    _studentNameController.dispose();
    _studentEmailController.dispose();
    _studentPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final faculty = await _supabaseService.getAllFaculty();
      final students = await _supabaseService.getAllStudents();
      setState(() {
        _facultyList = faculty;
        _studentList = students;
      });
    } catch (e) {
      _showError('Failed to load data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addFaculty() async {
    if (_facultyNameController.text.isEmpty ||
        _facultyEmailController.text.isEmpty ||
        _facultyPasswordController.text.isEmpty) {
      _showError('Please fill all fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabaseService.createFaculty(
        name: _facultyNameController.text.trim(),
        email: _facultyEmailController.text.trim(),
        password: _facultyPasswordController.text,
      );
      _facultyNameController.clear();
      _facultyEmailController.clear();
      _facultyPasswordController.clear();
      _showSuccess('Faculty added successfully');
      _loadData();
    } catch (e) {
      _showError('Failed to add faculty: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addStudent() async {
    if (_studentNameController.text.isEmpty ||
        _studentEmailController.text.isEmpty ||
        _studentPasswordController.text.isEmpty) {
      _showError('Please fill all fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabaseService.createStudent(
        name: _studentNameController.text.trim(),
        email: _studentEmailController.text.trim(),
        password: _studentPasswordController.text,
        department: _selectedDepartment,
        batch: _selectedBatch,
        year: _selectedYear,
      );
      _studentNameController.clear();
      _studentEmailController.clear();
      _studentPasswordController.clear();
      _showSuccess('Student added successfully');
      _loadData();
    } catch (e) {
      _showError('Failed to add student: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFaculty(String id) async {
    final confirmed = await _showConfirmDialog('Delete this faculty?');
    if (!confirmed) return;

    try {
      await _supabaseService.deleteFaculty(id);
      _showSuccess('Faculty deleted');
      _loadData();
    } catch (e) {
      _showError('Failed to delete: $e');
    }
  }

  Future<void> _deleteStudent(String id) async {
    final confirmed = await _showConfirmDialog('Delete this student?');
    if (!confirmed) return;

    try {
      await _supabaseService.deleteStudent(id);
      _showSuccess('Student deleted');
      _loadData();
    } catch (e) {
      _showError('Failed to delete: $e');
    }
  }

  Future<bool> _showConfirmDialog(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Faculty'),
            Tab(icon: Icon(Icons.school), text: 'Students'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFacultyTab(),
                _buildStudentTab(),
              ],
            ),
    );
  }

  Widget _buildFacultyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Add Faculty Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add New Faculty',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _facultyNameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _facultyEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _facultyPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addFaculty,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Faculty'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Faculty List
          Text(
            'All Faculty (${_facultyList.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._facultyList.map((f) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade100,
                    child: Text(
                      (f['name'] as String).isNotEmpty
                          ? (f['name'] as String)[0].toUpperCase()
                          : 'F',
                    ),
                  ),
                  title: Text(f['name'] ?? ''),
                  subtitle: Text(f['email'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteFaculty(f['id']),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStudentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Add Student Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add New Student',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _studentNameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _studentEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _studentPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedDepartment,
                          decoration: const InputDecoration(labelText: 'Dept'),
                          items: AppConstants.departments
                              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedDepartment = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedBatch,
                          decoration: const InputDecoration(labelText: 'Batch'),
                          items: AppConstants.batches
                              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedBatch = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          decoration: const InputDecoration(labelText: 'Year'),
                          items: AppConstants.years
                              .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedYear = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addStudent,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Student'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Student List
          Text(
            'All Students (${_studentList.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._studentList.map((s) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      (s['name'] as String).isNotEmpty
                          ? (s['name'] as String)[0].toUpperCase()
                          : 'S',
                    ),
                  ),
                  title: Text(s['name'] ?? ''),
                  subtitle: Text(
                    '${s['email']}\n${s['department']} - Batch ${s['batch']} | Year ${s['year']}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteStudent(s['id']),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
