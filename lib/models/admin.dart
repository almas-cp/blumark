class Admin {
  final String id;
  final String username;
  final DateTime createdAt;

  Admin({
    required this.id,
    required this.username,
    required this.createdAt,
  });

  factory Admin.fromJson(Map<String, dynamic> json) {
    return Admin(
      id: json['id'] as String,
      username: json['username'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
