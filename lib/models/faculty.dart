class Faculty {
  final String id;
  final String name;
  final String email;
  final String userType;
  final DateTime createdAt;

  Faculty({
    required this.id,
    required this.name,
    required this.email,
    this.userType = 'faculty',
    required this.createdAt,
  });

  factory Faculty.fromJson(Map<String, dynamic> json) {
    return Faculty(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      userType: json['user_type'] as String? ?? 'faculty',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'user_type': userType,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
