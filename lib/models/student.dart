class Student {
  final String id;
  final String name;
  final String email;
  final String department;
  final String batch;
  final int year;
  final int? rollNumber;
  final String userType;
  final DateTime createdAt;

  Student({
    required this.id,
    required this.name,
    required this.email,
    required this.department,
    required this.batch,
    required this.year,
    this.rollNumber,
    this.userType = 'student',
    required this.createdAt,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      department: json['department'] as String,
      batch: json['batch'] as String,
      year: json['year'] as int,
      rollNumber: json['roll_number'] as int?,
      userType: json['user_type'] as String? ?? 'student',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'department': department,
      'batch': batch,
      'year': year,
      'roll_number': rollNumber,
      'user_type': userType,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
