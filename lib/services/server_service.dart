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
      final payload = await request.readAsString();
      // Handle order creation here
      return Response.ok(
        jsonEncode({'status': 'success', 'message': 'Order received'}),
        headers: {'Content-Type': 'application/json'},
      );
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

    router.post('/api/db/query', (Request request) async {
      try {
        final payload = await request.readAsString();
        final body = jsonDecode(payload) as Map<String, dynamic>;
        final table = body['table'] as String;
        final distinct = body['distinct'] as bool?;
        final columns = (body['columns'] as List?)?.map((x) => x as String).toList();
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
            conflictAlgorithm = ConflictAlgorithm.values.firstWhere((e) => e.toString() == conflictAlgStr);
          } catch (_) {}
        }
        
        final db = await DatabaseHelper.instance.database;
        final result = await db.insert(
          table,
          values,
          nullColumnHack: nullColumnHack,
          conflictAlgorithm: conflictAlgorithm,
        );
        
        broadcastSyncMessage(jsonEncode({
          'event': 'db_change',
          'table': table,
          'type': 'insert',
          'timestamp': DateTime.now().toIso8601String()
        }));
        
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
            conflictAlgorithm = ConflictAlgorithm.values.firstWhere((e) => e.toString() == conflictAlgStr);
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
        
        broadcastSyncMessage(jsonEncode({
          'event': 'db_change',
          'table': table,
          'type': 'update',
          'timestamp': DateTime.now().toIso8601String()
        }));
        
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
        
        broadcastSyncMessage(jsonEncode({
          'event': 'db_change',
          'table': table,
          'type': 'delete',
          'timestamp': DateTime.now().toIso8601String()
        }));
        
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
        
        broadcastSyncMessage(jsonEncode({
          'event': 'db_change',
          'table': 'execute',
          'timestamp': DateTime.now().toIso8601String()
        }));
        
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
        
        broadcastSyncMessage(jsonEncode({
          'event': 'db_change',
          'table': 'rawInsert',
          'timestamp': DateTime.now().toIso8601String()
        }));
        
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
        
        broadcastSyncMessage(jsonEncode({
          'event': 'db_change',
          'table': 'rawUpdate',
          'timestamp': DateTime.now().toIso8601String()
        }));
        
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
        
        broadcastSyncMessage(jsonEncode({
          'event': 'db_change',
          'table': 'rawDelete',
          'timestamp': DateTime.now().toIso8601String()
        }));
        
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
    print('Server running on IP: ${_server!.address.address} Port: ${_server!.port}');

    // Start WebSocket server on Port 8081 for real-time broadcasts
    try {
      _wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8081);
      print('WebSocket server running on Port 8081');
      _wsServer!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _clients.add(socket);
            print('WebSocket Server: Client connected. Total: ${_clients.length}');
            socket.listen(
              (message) {
                print('WebSocket Server: Broadcast message: $message');
                // Forward the broadcast to all other connected clients
                broadcastSyncMessage(message, exclude: socket);
              },
              onDone: () {
                _clients.remove(socket);
                print('WebSocket Server: Client disconnected. Total: ${_clients.length}');
              },
              onError: (err) {
                _clients.remove(socket);
                print('WebSocket Server: Client error: $err. Total: ${_clients.length}');
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
