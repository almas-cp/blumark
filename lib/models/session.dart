class AttendanceSession {
  final String id;
  final String facultyId;
  final DateTime date;
  final int hour;
  final String department;
  final String batch;
  final int year;
  final String? deviceId;
  final bool isActive;
  final DateTime createdAt;

  // Optional: faculty name for display
  final String? facultyName;

  AttendanceSession({
    required this.id,
    required this.facultyId,
    required this.date,
    required this.hour,
    required this.department,
    required this.batch,
    required this.year,
    this.deviceId,
    this.isActive = true,
    required this.createdAt,
    this.facultyName,
  });

  factory AttendanceSession.fromJson(Map<String, dynamic> json) {
    return AttendanceSession(
      id: json['id'] as String,
      facultyId: json['faculty_id'] as String,
      date: DateTime.parse(json['date'] as String),
      hour: json['hour'] as int,
      department: json['department'] as String,
      batch: json['batch'] as String,
      year: json['year'] as int,
      deviceId: json['device_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      facultyName: json['faculty']?['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'faculty_id': facultyId,
      'date': date.toIso8601String().split('T')[0],
      'hour': hour,
      'department': department,
      'batch': batch,
      'year': year,
      'device_id': deviceId,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AttendanceSession copyWith({
    String? id,
    String? facultyId,
    DateTime? date,
    int? hour,
    String? department,
    String? batch,
    int? year,
    String? deviceId,
    bool? isActive,
    DateTime? createdAt,
    String? facultyName,
  }) {
    return AttendanceSession(
      id: id ?? this.id,
      facultyId: facultyId ?? this.facultyId,
      date: date ?? this.date,
      hour: hour ?? this.hour,
      department: department ?? this.department,
      batch: batch ?? this.batch,
      year: year ?? this.year,
      deviceId: deviceId ?? this.deviceId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      facultyName: facultyName ?? this.facultyName,
    );
  }
}
