class UserModel {
  final int? id;
  final String name;
  final String username;
  final String password;
  final String role;
  final bool isActive;
  final String createdAt;
  final String contactDetails;
  final String shiftTiming;

  UserModel({
    this.id,
    required this.name,
    required this.username,
    required this.password,
    required this.role,
    this.isActive = true,
    required this.createdAt,
    this.contactDetails = '',
    this.shiftTiming = '',
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
      'contact_details': contactDetails,
      'shift_timing': shiftTiming,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final active = map['is_active'] ?? map['active'];

    return UserModel(
      id: map['id'] == null ? null : (map['id'] as num).toInt(),
      name: (map['name'] ?? '').toString(),
      username: (map['username'] ?? '').toString(),
      password: (map['password'] ?? '').toString(),
      role: (map['role'] ?? '').toString(),
      isActive: active == 1 || active == true ||
          active?.toString().toLowerCase() == 'true',
      createdAt: (map['created_at'] ?? map['createdAt'] ?? '').toString(),
      contactDetails:
          (map['contact_details'] ?? map['contactDetails'] ?? '').toString(),
      shiftTiming:
          (map['shift_timing'] ?? map['shiftTiming'] ?? '').toString(),
    );
  }
}
