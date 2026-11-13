import 'package:flutter/foundation.dart';
import '../core/api/api_mode.dart';
import '../core/database/database_helper.dart';
import '../models/user_model.dart';
import '../services/backend_api_client.dart';
import '../services/auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final BackendApiClient _apiClient = const BackendApiClient();

  Future<UserModel?> login(String username, String password) async {
    if (await _useBackendApi()) {
      try {
        final response = await _apiClient.postJson('/api/v1/auth/login', {
          'username': username,
          'password': password,
        });
        final prefs = await SharedPreferences.getInstance();
        await AuthTokenStorage.save(
          accessToken: (response['accessToken'] ?? response['token'])
              ?.toString(),
          refreshToken: response['refreshToken']?.toString(),
        );
        await prefs.remove('token');
        await prefs.remove('flutter.token');
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
    final maps = await db.query(
      'users',
      where: 'username = ? AND password = ? AND is_active = 1',
      whereArgs: [username, hashedPassword],
    );
    return maps.isEmpty ? null : UserModel.fromMap(maps.first);
  }

  Future<List<UserModel>> getUsers() async {
    if (await _useBackendApi()) {
      final users = <UserModel>[];
      var page = 0;
      while (true) {
        final response = await _apiClient.getJson(
          '/api/v1/users?page=$page&size=100&sort=name,asc',
        );
        users.addAll(_parseUsers(response));
        if (response is! Map ||
            response['last'] == true ||
            (response['content'] is List &&
                (response['content'] as List).length < 100)) {
          return users;
        }
        page++;
      }
    }

    final db = await _dbHelper.database;
    final maps = await db.query('users');
    return List.generate(maps.length, (i) => UserModel.fromMap(maps[i]));
  }

  Future<int> addUser(UserModel user) async {
    if (await _useBackendApi()) {
      final response = await _apiClient.postJson(
        '/api/v1/users',
        _toApiMap(user),
      );
      return (response['id'] as num).toInt();
    }
    final db = await _dbHelper.database;
    return db.insert('users', user.toMap());
  }

  Future<int> updateUser(UserModel user) async {
    if (await _useBackendApi()) {
      if (user.id == null) {
        throw ArgumentError('User ID is required for update');
      }
      await _apiClient.putJson('/api/v1/users/${user.id}', {
        'fullName': user.name,
        'phone': user.contactDetails,
        'shiftTiming': user.shiftTiming,
      });
      await _apiClient.putJson('/api/v1/users/${user.id}/roles', {
        'roleCodes': [user.role],
      });
      await _apiClient.putJson('/api/v1/users/${user.id}/branches', {
        'branchIds': user.branchIds,
      });
      return 1;
    }
    final db = await _dbHelper.database;
    return db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<int> deleteUser(int id) async {
    if (await _useBackendApi()) {
      await _apiClient.postJson('/api/v1/users/$id/deactivate', {});
      return 1;
    }
    final db = await _dbHelper.database;
    return db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (!await _useBackendApi()) {
      throw UnsupportedError('Password change requires the backend API');
    }
    await _apiClient.postJson('/api/v1/auth/password/change', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    if (await _useBackendApi()) {
      final refreshToken = await AuthTokenStorage.readRefreshToken();
      if (refreshToken != null) {
        try {
          await _apiClient.postJson('/api/v1/auth/logout', {
            'refreshToken': refreshToken,
          });
        } catch (_) {
          // Local credential cleanup should still complete if the server session expired.
        }
      }
    }
    await AuthTokenStorage.clear();
    await prefs.remove('token');
    await prefs.remove('flutter.token');
    await prefs.remove('username');
    await prefs.remove('role');
    await prefs.remove('remember_me');
  }

  Future<bool> _useBackendApi() async {
    final prefs = await SharedPreferences.getInstance();
    return kIsWeb ||
        (prefs.getBool('use_backend_api') ?? ApiMode.defaultUseBackendApi);
  }

  List<UserModel> _parseUsers(dynamic response) {
    final items = response is List
        ? response
        : response is Map
        ? response['content']
        : null;
    if (items is! List) {
      throw const FormatException('Expected a user list from the backend');
    }
    return items
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
    'contactDetails': user.contactDetails,
    'shiftTiming': user.shiftTiming,
    if (user.branchIds.isNotEmpty) 'branchIds': user.branchIds,
  };
}
