class UserModel {
  final int? id;
  final String name;
  final String username;
  final String password;
  final String role;
  final bool isActive;
  final String createdAt;

  UserModel({
    this.id,
    required this.name,
    required this.username,
    required this.password,
    required this.role,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'password': password,
      'role': role,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final active = map['is_active'] ?? map['active'];
    return UserModel(
      id: map['id'],
      name: map['name'] ?? '',
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      role: map['role'] ?? '',
      isActive: active == 1 || active == true,
      createdAt: map['created_at'] ?? map['createdAt'] ?? '',
    );
  }
}
