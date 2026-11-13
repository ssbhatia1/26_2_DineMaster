import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite/sqflite.dart';
import '../repositories/product_repository.dart';
import '../core/database/database_helper.dart';

class ServerService {
  static final ServerService instance = ServerService._init();
  HttpServer? _server;
  HttpServer? _wsServer;
  final List<WebSocket> _clients = [];
  final _productRepository = ProductRepository();

  ServerService._init();

  void broadcastSyncMessage(String message, {WebSocket? exclude}) {
    for (var client in _clients) {
      if (client != exclude) {
        try {
          client.add(message);
        } catch (e) {
          print('ServerService: Error broadcasting to client: $e');
        }
      }
    }
  }

  Future<void> startServer() async {
    final router = Router();

    // Menu Endpoint
    router.get('/api/menu', (Request request) async {
      try {
        final products = await _productRepository.getProducts();
        final jsonList = products.map((p) => p.toMap()).toList();
        return Response.ok(
          jsonEncode(jsonList),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    // Digital Menu Web Page
    router.get('/menu', (Request request) async {
      final html = '''
<!DOCTYPE html>
<html>
<head>
    <title>RestoPro Digital Menu</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 16px; background: #f5f5f5; }
        header { background: #6200ee; color: white; padding: 16px; margin: -16px -16px 16px -16px; text-align: center; }
        .product { background: white; padding: 16px; margin-bottom: 12px; border-radius: 12px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); display: flex; justify-content: space-between; align-items: center; }
        .product-info h3 { margin: 0; font-size: 16px; }
        .product-info p { margin: 4px 0 0 0; color: #666; font-size: 14px; }
        .price { font-weight: bold; color: #6200ee; }
        .btn { background: #6200ee; color: white; border: none; padding: 8px 16px; border-radius: 20px; cursor: pointer; font-weight: bold; }
        .cart-bar { position: fixed; bottom: 0; left: 0; right: 0; background: white; padding: 16px; box-shadow: 0 -2px 10px rgba(0,0,0,0.1); display: flex; justify-content: space-between; align-items: center; }
    </style>
</head>
<body>
    <header>
        <h1>RestoPro</h1>
        <p>Digital Menu</p>
    </header>
    <div id="products">Loading menu...</div>
    <div class="cart-bar">
        <div><span id="cart-count">0</span> Items in Cart</div>
        <button class="btn" onclick="placeOrder()">Place Order</button>
    </div>
    <script>
        let cart = [];
        fetch('/api/menu')
            .then(res => res.json())
            .then(data => {
                const div = document.getElementById('products');
                div.innerHTML = '';
                data.forEach(p => {
                    const el = document.createElement('div');
                    el.className = 'product';
                    el.innerHTML = `
                        <div class="product-info">
                            <h3>\${p.name}</h3>
                            <p>\${p.description || 'Delicious food'}</p>
                            <p class="price">₹\${p.price}</p>
                        </div>
                        <button class="btn" onclick="addToCart(\${p.id}, '\${p.name}', \${p.price})">Add</button>
                    `;
                    div.appendChild(el);
                });
            });
            
        function addToCart(id, name, price) {
            cart.push({id, name, price});
            document.getElementById('cart-count').innerText = cart.length;
        }
        
        function placeOrder() {
            if (cart.length === 0) { alert('Cart is empty!'); return; }
            const urlParams = new URLSearchParams(window.location.search);
            const table = urlParams.get('table') || 'Takeaway';
            
            fetch('/api/order', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    table: table,
                    items: cart
                })
            })
            .then(res => res.json())
            .then(data => {
                alert('Order placed successfully for Table ' + table + '!');
                cart = [];
                document.getElementById('cart-count').innerText = '0';
            });
        }
    </script>
</body>
</html>
''';
      return Response.ok(html, headers: {'Content-Type': 'text/html'});
    });

    // Order Placement Endpoint
    router.post('/api/order', (Request request) async {
      try {
        final decoded = jsonDecode(await request.readAsString());
        if (decoded is! Map) {
          return _jsonResponse({
            'error': 'Request body must be a JSON object',
          }, statusCode: 400);
        }

        final body = Map<String, dynamic>.from(decoded);
        final rawItems = body['items'];
        if (rawItems is! List || rawItems.isEmpty) {
          return _jsonResponse({
            'error': 'At least one order item is required',
          }, statusCode: 400);
        }

        final tableValue = body['table']?.toString().trim();
        final isTakeaway =
            tableValue == null ||
            tableValue.isEmpty ||
            tableValue.toLowerCase() == 'takeaway';
        final restaurantId = DatabaseHelper.currentRestaurantId ?? 1;
        final db = await DatabaseHelper.instance.database;

        int? tableId;
        if (!isTakeaway) {
          final tables = await db.query(
            'tables',
            columns: ['id'],
            where:
                '(table_number = ? OR CAST(id AS TEXT) = ?) AND restaurant_id = ?',
            whereArgs: [tableValue, tableValue, restaurantId],
            limit: 1,
          );
          if (tables.isEmpty) {
            return _jsonResponse({
              'error': 'Table does not exist for this restaurant',
            }, statusCode: 400);
          }
          tableId = (tables.first['id'] as num).toInt();
        }

        final preparedItems = <Map<String, dynamic>>[];
        var total = 0.0;
        for (final rawItem in rawItems) {
          if (rawItem is! Map) {
            return _jsonResponse({
              'error': 'Each order item must be an object',
            }, statusCode: 400);
          }
          final item = Map<String, dynamic>.from(rawItem);
          final productId = (item['id'] ?? item['productId']) is num
              ? ((item['id'] ?? item['productId']) as num).toInt()
              : int.tryParse(
                  (item['id'] ?? item['productId'])?.toString() ?? '',
                );
          final quantity = item['quantity'] is num
              ? (item['quantity'] as num).toInt()
              : 1;
          if (productId == null ||
              productId <= 0 ||
              quantity <= 0 ||
              quantity > 100) {
            return _jsonResponse({
              'error': 'Each item requires a valid product id and quantity',
            }, statusCode: 400);
          }

          final products = await db.query(
            'products',
            columns: ['id', 'price', 'is_available'],
            where: 'id = ? AND restaurant_id = ?',
            whereArgs: [productId, restaurantId],
            limit: 1,
          );
          if (products.isEmpty ||
              (products.first['is_available'] as num? ?? 0) == 0) {
            return _jsonResponse({
              'error': 'Product is unavailable or not found: $productId',
            }, statusCode: 400);
          }

          final price = (products.first['price'] as num?)?.toDouble();
          if (price == null || price < 0) {
            return _jsonResponse({
              'error': 'Product has an invalid price: $productId',
            }, statusCode: 500);
          }
          total += price * quantity;
          preparedItems.add({
            'product_id': productId,
            'quantity': quantity,
            'price': price,
            'notes': item['notes']?.toString(),
          });
        }

        final orderId = await db.transaction((txn) async {
          final id = await txn.insert('orders', {
            'table_id': tableId,
            'total_amount': total,
            'status': 'Received',
            'type': isTakeaway ? 'Takeaway' : 'Dine-In',
            'order_time': DateTime.now().toIso8601String(),
            'notes': body['notes']?.toString(),
            'payment_status': 'Unpaid',
            'discount_amount': 0,
            'customer_name': body['customerName']?.toString(),
            'customer_phone': body['customerPhone']?.toString(),
            'restaurant_id': restaurantId,
          });
          for (final item in preparedItems) {
            await txn.insert('order_items', {
              ...item,
              'order_id': id,
              'status': 'Pending',
            });
          }
          await DatabaseHelper.instance.logOrderStatus(
            id,
            'Received',
            changedBy: 'LAN Customer',
            executor: txn,
          );
          await DatabaseHelper.instance.generateKOTForOrder(id, null, txn);
          if (tableId != null) {
            await txn.update(
              'tables',
              {'status': 'Occupied'},
              where: 'id = ?',
              whereArgs: [tableId],
            );
          }
          return id;
        });

        broadcastSyncMessage(
          jsonEncode({
            'event': 'database_update',
            'action': 'create_order',
            'orderId': orderId,
          }),
        );
        return _jsonResponse({
          'status': 'success',
          'orderId': orderId,
          'totalAmount': total,
        }, statusCode: 201);
      } on FormatException catch (error) {
        return _jsonResponse({'error': error.message}, statusCode: 400);
      } catch (error) {
        return _jsonResponse({
          'error': 'Could not create order',
        }, statusCode: 500);
      }
    });

    // --- DB HTTP Proxy Endpoints ---

    router.post('/api/db/rawQuery', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final sql = body['sql'] as String;
        final args = body['arguments'] as List?;

        final db = await DatabaseHelper.instance.database;
        final result = await db.rawQuery(sql, args);

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/batch', (Request request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map || body['operations'] is! List) {
          return _jsonResponse({
            'error': 'Batch operations must be a list',
          }, statusCode: 400);
        }
        final operations = (body['operations'] as List)
            .map((operation) => Map<String, dynamic>.from(operation as Map))
            .toList();
        final continueOnError = body['continueOnError'] == true;
        final noResult = body['noResult'] == true;
        final db = await DatabaseHelper.instance.database;
        final results = await db.transaction((txn) async {
          final values = <Object?>[];
          for (final operation in operations) {
            try {
              values.add(await _executeBatchOperation(txn, operation));
            } catch (error) {
              if (!continueOnError) rethrow;
              values.add(error.toString());
            }
          }
          return values;
        });

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': 'batch',
            'type': 'batch',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );
        return _jsonResponse({'result': noResult ? <Object?>[] : results});
      } on FormatException catch (error) {
        return _jsonResponse({'error': error.message}, statusCode: 400);
      } catch (error) {
        return _jsonResponse({
          'error': 'Batch execution failed',
        }, statusCode: 500);
      }
    });

    router.post('/api/db/query', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final table = body['table'] as String;
        final distinct = body['distinct'] as bool?;
        final columns = (body['columns'] as List?)
            ?.map((x) => x as String)
            .toList();
        final where = body['where'] as String?;
        final whereArgs = body['whereArgs'] as List?;
        final groupBy = body['groupBy'] as String?;
        final having = body['having'] as String?;
        final orderBy = body['orderBy'] as String?;
        final limit = body['limit'] as int?;
        final offset = body['offset'] as int?;

        final db = await DatabaseHelper.instance.database;
        final result = await db.query(
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
        );

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/insert', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final table = body['table'] as String;
        final values = Map<String, Object?>.from(body['values'] as Map);
        final nullColumnHack = body['nullColumnHack'] as String?;
        final conflictAlgStr = body['conflictAlgorithm'] as String?;

        ConflictAlgorithm? conflictAlgorithm;
        if (conflictAlgStr != null) {
          try {
            conflictAlgorithm = ConflictAlgorithm.values.firstWhere(
              (e) => e.toString() == conflictAlgStr,
            );
          } catch (_) {}
        }

        final db = await DatabaseHelper.instance.database;
        final result = await db.insert(
          table,
          values,
          nullColumnHack: nullColumnHack,
          conflictAlgorithm: conflictAlgorithm,
        );

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': table,
            'type': 'insert',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/update', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final table = body['table'] as String;
        final values = Map<String, Object?>.from(body['values'] as Map);
        final where = body['where'] as String?;
        final whereArgs = body['whereArgs'] as List?;
        final conflictAlgStr = body['conflictAlgorithm'] as String?;

        ConflictAlgorithm? conflictAlgorithm;
        if (conflictAlgStr != null) {
          try {
            conflictAlgorithm = ConflictAlgorithm.values.firstWhere(
              (e) => e.toString() == conflictAlgStr,
            );
          } catch (_) {}
        }

        final db = await DatabaseHelper.instance.database;
        final result = await db.update(
          table,
          values,
          where: where,
          whereArgs: whereArgs,
          conflictAlgorithm: conflictAlgorithm,
        );

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': table,
            'type': 'update',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/delete', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final table = body['table'] as String;
        final where = body['where'] as String?;
        final whereArgs = body['whereArgs'] as List?;

        final db = await DatabaseHelper.instance.database;
        final result = await db.delete(
          table,
          where: where,
          whereArgs: whereArgs,
        );

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': table,
            'type': 'delete',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/execute', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final sql = body['sql'] as String;
        final args = body['arguments'] as List?;

        final db = await DatabaseHelper.instance.database;
        await db.execute(sql, args);

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': 'execute',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        return Response.ok(
          jsonEncode({'result': 'success'}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/rawInsert', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final sql = body['sql'] as String;
        final args = body['arguments'] as List?;

        final db = await DatabaseHelper.instance.database;
        final result = await db.rawInsert(sql, args);

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': 'rawInsert',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/rawUpdate', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final sql = body['sql'] as String;
        final args = body['arguments'] as List?;

        final db = await DatabaseHelper.instance.database;
        final result = await db.rawUpdate(sql, args);

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': 'rawUpdate',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/api/db/rawDelete', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final sql = body['sql'] as String;
        final args = body['arguments'] as List?;

        final db = await DatabaseHelper.instance.database;
        final result = await db.rawDelete(sql, args);

        broadcastSyncMessage(
          jsonEncode({
            'event': 'db_change',
            'table': 'rawDelete',
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        return Response.ok(
          jsonEncode({'result': result}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

    // Fallback or static files (if any)
    router.all('/<ignored|.*>', (Request request) {
      return Response.ok('RestoPro API is running');
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    // Bind to all interfaces (0.0.0.0) to allow external access in LAN
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8082);
    print(
      'Server running on IP: ${_server!.address.address} Port: ${_server!.port}',
    );

    // Keep the sync socket separate from the Spring API port (8081).
    try {
      _wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8083);
      print('WebSocket server running on Port 8083');
      _wsServer!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _clients.add(socket);
            print(
              'WebSocket Server: Client connected. Total: ${_clients.length}',
            );
            socket.listen(
              (message) {
                print('WebSocket Server: Broadcast message: $message');
                // Forward the broadcast to all other connected clients
                broadcastSyncMessage(message, exclude: socket);
              },
              onDone: () {
                _clients.remove(socket);
                print(
                  'WebSocket Server: Client disconnected. Total: ${_clients.length}',
                );
              },
              onError: (err) {
                _clients.remove(socket);
                print(
                  'WebSocket Server: Client error: $err. Total: ${_clients.length}',
                );
              },
              cancelOnError: true,
            );
          });
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.close();
        }
      });
    } catch (e) {
      print('Failed to bind WebSocket server: $e');
    }
  }

  Response _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Object?> _executeBatchOperation(
    DatabaseExecutor db,
    Map<String, dynamic> operation,
  ) async {
    final type = operation['type'] as String?;
    ConflictAlgorithm? conflictAlgorithm;
    final conflictValue = operation['conflictAlgorithm'] as String?;
    if (conflictValue != null) {
      conflictAlgorithm = ConflictAlgorithm.values
          .cast<ConflictAlgorithm?>()
          .firstWhere(
            (value) => value.toString() == conflictValue,
            orElse: () => null,
          );
    }

    switch (type) {
      case 'rawInsert':
        return db.rawInsert(
          operation['sql'] as String,
          operation['arguments'] as List?,
        );
      case 'rawUpdate':
        return db.rawUpdate(
          operation['sql'] as String,
          operation['arguments'] as List?,
        );
      case 'rawDelete':
        return db.rawDelete(
          operation['sql'] as String,
          operation['arguments'] as List?,
        );
      case 'execute':
        await db.execute(
          operation['sql'] as String,
          operation['arguments'] as List?,
        );
        return null;
      case 'insert':
        return db.insert(
          operation['table'] as String,
          Map<String, Object?>.from(operation['values'] as Map),
          nullColumnHack: operation['nullColumnHack'] as String?,
          conflictAlgorithm: conflictAlgorithm,
        );
      case 'update':
        return db.update(
          operation['table'] as String,
          Map<String, Object?>.from(operation['values'] as Map),
          where: operation['where'] as String?,
          whereArgs: operation['whereArgs'] as List?,
          conflictAlgorithm: conflictAlgorithm,
        );
      case 'delete':
        return db.delete(
          operation['table'] as String,
          where: operation['where'] as String?,
          whereArgs: operation['whereArgs'] as List?,
        );
      case 'query':
        return db.query(
          operation['table'] as String,
          distinct: operation['distinct'] as bool?,
          columns: (operation['columns'] as List?)?.cast<String>(),
          where: operation['where'] as String?,
          whereArgs: operation['whereArgs'] as List?,
          groupBy: operation['groupBy'] as String?,
          having: operation['having'] as String?,
          orderBy: operation['orderBy'] as String?,
          limit: operation['limit'] as int?,
          offset: operation['offset'] as int?,
        );
      case 'rawQuery':
        return db.rawQuery(
          operation['sql'] as String,
          operation['arguments'] as List?,
        );
      default:
        throw ArgumentError('Unsupported batch operation');
    }
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    await _wsServer?.close(force: true);
    for (var client in _clients) {
      await client.close();
    }
    _clients.clear();
    print('Server stopped');
  }

  String get serverUrl {
    if (_server == null) return '';
    return 'http://${_server!.address.address}:${_server!.port}';
  }
}
