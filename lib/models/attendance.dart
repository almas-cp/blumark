class Attendance {
  final String id;
  final String studentId;
  final String sessionId;
  final int attendance; // 0 = absent, 1 = present
  final DateTime markedAt;

  // Optional: student details for display
  final String? studentName;
  final String? studentEmail;

  Attendance({
    required this.id,
    required this.studentId,
    required this.sessionId,
    required this.attendance,
    required this.markedAt,
    this.studentName,
    this.studentEmail,
  });

  bool get isPresent => attendance == 1;

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      sessionId: json['session_id'] as String,
      attendance: json['attendance'] as int,
      markedAt: DateTime.parse(json['marked_at'] as String),
      studentName: json['student']?['name'] as String?,
      studentEmail: json['student']?['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_id': studentId,
      'session_id': sessionId,
      'attendance': attendance,
      'marked_at': markedAt.toIso8601String(),
    };
  }
}
