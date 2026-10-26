import 'package:flutter/foundation.dart';
import '../core/api/api_mode.dart';
import '../core/database/database_helper.dart';
import '../models/user_model.dart';
import '../services/backend_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final BackendApiClient _apiClient = const BackendApiClient();

  Future<UserModel?> login(String username, String password) async {
    if (await _useBackendApi()) {
      try {
        final response = await _apiClient.postJson('/api/auth/login', {
          'username': username,
          'password': password,
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', response['token'].toString());
        final user = UserModel.fromMap(
          Map<String, dynamic>.from(response['user'] as Map),
        );
        await prefs.setString('username', user.username);
        await prefs.setString('role', user.role);
        return user;
      } on BackendApiException {
        return null;
      }
    }

    final db = await _dbHelper.database;
    final hashedPassword = DatabaseHelper.hashPassword(password);

    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'username = ? AND password = ? AND is_active = 1',
      whereArgs: [username, hashedPassword],
    );

    if (maps.isNotEmpty) {
      return UserModel.fromMap(maps.first);
    }
    return null;
  }

  Future<List<UserModel>> getUsers() async {
    if (await _useBackendApi()) {
      final response = await _apiClient.getJson('/api/users');
      return _parseUsers(response);
    }

    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('users');
    return List.generate(maps.length, (i) => UserModel.fromMap(maps[i]));
  }

  Future<int> addUser(UserModel user) async {
    if (await _useBackendApi()) {
      final response = await _apiClient.postJson('/api/users', _toApiMap(user));
      return (response['id'] as num).toInt();
    }

    final db = await _dbHelper.database;
    return await db.insert('users', user.toMap());
  }

  Future<int> updateUser(UserModel user) async {
    if (await _useBackendApi()) {
      if (user.id == null)
        throw ArgumentError('User ID is required for update');
      await _apiClient.putJson('/api/users/${user.id}', _toApiMap(user));
      return 1;
    }

    final db = await _dbHelper.database;
    return await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<int> deleteUser(int id) async {
    if (await _useBackendApi()) {
      await _apiClient.delete('/api/users/$id');
      return 1;
    }

    final db = await _dbHelper.database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> _useBackendApi() async {
    final prefs = await SharedPreferences.getInstance();
    return kIsWeb || (prefs.getBool('use_backend_api') ?? ApiMode.defaultUseBackendApi);
  }

  List<UserModel> _parseUsers(dynamic response) {
    if (response is! List)
      throw const FormatException('Expected a user list from the backend');
    return response
        .map(
          (item) => UserModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Map<String, dynamic> _toApiMap(UserModel user) => {
    'name': user.name,
    'username': user.username,
    if (user.password.isNotEmpty && user.password != '********')
      'password': user.password,
    'role': user.role,
    'active': user.isActive,
  };
}

