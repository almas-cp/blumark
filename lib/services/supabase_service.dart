import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/faculty.dart';
import '../models/student.dart';
import '../models/session.dart';
import '../models/attendance.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ==================== AUTH ====================

  /// Login - checks admin, faculty, and student tables
  /// Returns {'type': 'admin'|'faculty'|'student', 'user': ...}
  Future<Map<String, dynamic>?> login(String email, String password) async {
    // Check admin table first (uses username instead of email)
    final adminResponse = await _client
        .from('admin')
        .select()
        .eq('username', email)
        .eq('password', password)
        .maybeSingle();

    if (adminResponse != null) {
      return {
        'type': 'admin',
        'user': adminResponse,
      };
    }

    // Check faculty table
    final facultyResponse = await _client
        .from('faculty')
        .select()
        .eq('email', email)
        .eq('password', password)
        .maybeSingle();

    if (facultyResponse != null) {
      return {
        'type': 'faculty',
        'user': Faculty.fromJson(facultyResponse),
      };
    }

    // Check student table
    final studentResponse = await _client
        .from('student')
        .select()
        .eq('email', email)
        .eq('password', password)
        .maybeSingle();

    if (studentResponse != null) {
      return {
        'type': 'student',
        'user': Student.fromJson(studentResponse),
      };
    }

    return null;
  }

  // ==================== ADMIN OPERATIONS ====================

  /// Get all faculty
  Future<List<Map<String, dynamic>>> getAllFaculty() async {
    final response = await _client
        .from('faculty')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Get all students
  Future<List<Map<String, dynamic>>> getAllStudents() async {
    final response = await _client
        .from('student')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Create faculty
  Future<void> createFaculty({
    required String name,
    required String email,
    required String password,
  }) async {
    await _client.from('faculty').insert({
      'name': name,
      'email': email,
      'password': password,
    });
  }

  /// Create student
  Future<void> createStudent({
    required String name,
    required String email,
    required String password,
    required String department,
    required String batch,
    required int year,
  }) async {
    await _client.from('student').insert({
      'name': name,
      'email': email,
      'password': password,
      'department': department,
      'batch': batch,
      'year': year,
    });
  }

  /// Delete faculty
  Future<void> deleteFaculty(String id) async {
    await _client.from('faculty').delete().eq('id', id);
  }

  /// Delete student
  Future<void> deleteStudent(String id) async {
    await _client.from('student').delete().eq('id', id);
  }

  // ==================== SESSION OPERATIONS ====================

  /// Create a new attendance session
  Future<AttendanceSession> createSession({
    required String facultyId,
    required DateTime date,
    required int hour,
    required String department,
    required String batch,
    required int year,
  }) async {
    final response = await _client.from('session').insert({
      'faculty_id': facultyId,
      'date': date.toIso8601String().split('T')[0],
      'hour': hour,
      'department': department,
      'batch': batch,
      'year': year,
      'is_active': true,
    }).select().single();

    return AttendanceSession.fromJson(response);
  }

  /// Update session with hex_ssid when BLE advertising starts
  Future<void> updateSessionHexSsid(String sessionId, String hexSsid) async {
    await _client.from('session').update({
      'hex_ssid': hexSsid,
    }).eq('id', sessionId);
  }

  /// Deactivate session
  Future<void> endSession(String sessionId) async {
    await _client.from('session').update({
      'is_active': false,
      'hex_ssid': null,
    }).eq('id', sessionId);
  }

  /// Get active sessions for a student's department/batch/year
  Future<List<AttendanceSession>> getActiveSessionsForStudent({
    required String department,
    required String batch,
    required int year,
  }) async {
    final response = await _client
        .from('session')
        .select('*, faculty:faculty_id(name)')
        .eq('department', department)
        .eq('batch', batch)
        .eq('year', year)
        .eq('is_active', true)
        .not('hex_ssid', 'is', null);

    return (response as List)
        .map((json) => AttendanceSession.fromJson(json))
        .toList();
  }

  /// Get session by hex_ssid
  Future<AttendanceSession?> getSessionByHexSsid(String hexSsid) async {
    final response = await _client
        .from('session')
        .select('*, faculty:faculty_id(name)')
        .eq('hex_ssid', hexSsid)
        .eq('is_active', true)
        .maybeSingle();

    if (response != null) {
      return AttendanceSession.fromJson(response);
    }
    return null;
  }

  /// Get faculty's session history
  Future<List<AttendanceSession>> getFacultySessions(String facultyId) async {
    final response = await _client
        .from('session')
        .select()
        .eq('faculty_id', facultyId)
        .order('created_at', ascending: false)
        .limit(50);

    return (response as List)
        .map((json) => AttendanceSession.fromJson(json))
        .toList();
  }

  /// Delete a session
  Future<void> deleteSession(String sessionId) async {
    await _client.from('session').delete().eq('id', sessionId);
  }

  /// Get session attendance count
  Future<int> getSessionAttendanceCount(String sessionId) async {
    final response = await _client
        .from('attendance')
        .select('id')
        .eq('session_id', sessionId);
    return (response as List).length;
  }

  // ==================== ATTENDANCE OPERATIONS ====================

  /// Mark student attendance
  Future<Attendance?> markAttendance({
    required String studentId,
    required String sessionId,
  }) async {
    try {
      final response = await _client.from('attendance').insert({
        'student_id': studentId,
        'session_id': sessionId,
        'attendance': 1,
      }).select().single();

      return Attendance.fromJson(response);
    } catch (e) {
      // Might fail if already marked (unique constraint)
      return null;
    }
  }

  /// Check if student already marked attendance for a session
  Future<bool> hasMarkedAttendance({
    required String studentId,
    required String sessionId,
  }) async {
    final response = await _client
        .from('attendance')
        .select('id')
        .eq('student_id', studentId)
        .eq('session_id', sessionId)
        .maybeSingle();

    return response != null;
  }

  /// Get attendance list for a session (with student details)
  Future<List<Attendance>> getSessionAttendance(String sessionId) async {
    final response = await _client
        .from('attendance')
        .select('*, student:student_id(name, email)')
        .eq('session_id', sessionId)
        .order('marked_at', ascending: false);

    return (response as List)
        .map((json) => Attendance.fromJson(json))
        .toList();
  }

  /// Get student's attendance history
  Future<List<Map<String, dynamic>>> getStudentAttendanceHistory(
      String studentId) async {
    final response = await _client
        .from('attendance')
        .select('*, session:session_id(date, hour, department, batch, year, faculty:faculty_id(name))')
        .eq('student_id', studentId)
        .order('marked_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(response);
  }

  // ==================== REALTIME ====================

  /// Subscribe to attendance updates for a session
  StreamSubscription<List<Map<String, dynamic>>> subscribeToSessionAttendance(
    String sessionId,
    void Function(List<Attendance>) onData,
  ) {
    return _client
        .from('attendance')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .listen((data) async {
          // Fetch with student details
          final attendanceList = await getSessionAttendance(sessionId);
          onData(attendanceList);
        });
  }
}
