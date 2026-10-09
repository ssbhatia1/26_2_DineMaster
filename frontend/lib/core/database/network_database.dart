import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';

class NetworkDatabase implements Database {
  final String serverIp;
  final int port;

  NetworkDatabase({required this.serverIp, this.port = 8082});

  Future<dynamic> _post(String endpoint, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://$serverIp:$port$endpoint'));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('Server error: $responseBody');
      }
      return jsonDecode(responseBody);
    } finally {
      client.close();
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final res = await _post('/api/db/rawQuery', {
      'sql': sql,
      'arguments': arguments,
    });
    return List<Map<String, Object?>>.from(
      (res['result'] as List).map((x) => Map<String, Object?>.from(x as Map)),
    );
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final res = await _post('/api/db/query', {
      'table': table,
      'distinct': distinct,
      'columns': columns,
      'where': where,
      'whereArgs': whereArgs,
      'groupBy': groupBy,
      'having': having,
      'orderBy': orderBy,
      'limit': limit,
      'offset': offset,
    });
    return List<Map<String, Object?>>.from(
      (res['result'] as List).map((x) => Map<String, Object?>.from(x as Map)),
    );
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final res = await _post('/api/db/insert', {
      'table': table,
      'values': values,
      'nullColumnHack': nullColumnHack,
      'conflictAlgorithm': conflictAlgorithm?.toString(),
    });
    return res['result'] as int;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final res = await _post('/api/db/update', {
      'table': table,
      'values': values,
      'where': where,
      'whereArgs': whereArgs,
      'conflictAlgorithm': conflictAlgorithm?.toString(),
    });
    return res['result'] as int;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final res = await _post('/api/db/delete', {
      'table': table,
      'where': where,
      'whereArgs': whereArgs,
    });
    return res['result'] as int;
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await _post('/api/db/execute', {
      'sql': sql,
      'arguments': arguments,
    });
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    final txn = NetworkTransaction(this);
    return await action(txn);
  }

  // --- Implement other Database interface methods with stubs ---
  
  @override
  String get path => 'network://$serverIp:$port';

  @override
  bool get isOpen => true;

  Future<bool> get isOpenAsync async => true;

  @override
  Future<void> close() async {}

  Future<int> getVersion() async => 1;

  Future<void> setVersion(int version) async {}

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final res = await _post('/api/db/rawInsert', {'sql': sql, 'arguments': arguments});
    return res['result'] as int;
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    final res = await _post('/api/db/rawUpdate', {'sql': sql, 'arguments': arguments});
    return res['result'] as int;
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    final res = await _post('/api/db/rawDelete', {'sql': sql, 'arguments': arguments});
    return res['result'] as int;
  }

  @override
  Batch batch() => throw UnimplementedError('Batch operations not supported over NetworkDatabase.');

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) async {
    final txn = NetworkTransaction(this);
    return await action(txn);
  }

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) => throw UnimplementedError();

  @override
  Future<T> devInvokeSqlMethod<T>(String method, String sql, [List<Object?>? arguments]) => throw UnimplementedError();

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => throw UnimplementedError('Cursor operations not supported over NetworkDatabase.');

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => throw UnimplementedError('Cursor operations not supported over NetworkDatabase.');

  @override
  Database get database => this;

  Future<List<Map<String, Object?>>> devSetDebugModeOn([bool? on]) async => [];
}

class NetworkTransaction implements Transaction {
  final NetworkDatabase _db;
  NetworkTransaction(this._db);

  @override
  Database get database => _db;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) => _db.execute(sql, arguments);

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      _db.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) =>
      _db.query(table, distinct: distinct, columns: columns, where: where, whereArgs: whereArgs, groupBy: groupBy, having: having, orderBy: orderBy, limit: limit, offset: offset);

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) => _db.rawQuery(sql, arguments);

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) =>
      _db.update(table, values, where: where, whereArgs: whereArgs, conflictAlgorithm: conflictAlgorithm);

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) => _db.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) => _db.rawInsert(sql, arguments);

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) => _db.rawUpdate(sql, arguments);

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) => _db.rawDelete(sql, arguments);

  @override
  Batch batch() => throw UnimplementedError();

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => _db.queryCursor(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
        bufferSize: bufferSize,
      );

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => _db.rawQueryCursor(sql, arguments, bufferSize: bufferSize);
}
