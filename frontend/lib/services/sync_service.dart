import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  final Logger _logger = Logger();
  
  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  String? _currentIp;

  final StreamController<String> _syncController = StreamController<String>.broadcast();
  Stream<String> get syncEvents => _syncController.stream;

  final ValueNotifier<bool> connectionState = ValueNotifier<bool>(false);

  SyncService._init();

  Future<void> initConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final isServer = prefs.getBool('is_server') ?? true;
    final serverIp = prefs.getString('server_ip') ?? 'localhost';
    
    _currentIp = isServer ? 'localhost' : serverIp;
    
    // Stop any existing connection or reconnect timers
    await closeConnection();
    
    _connect();
  }

  void _connect() async {
    if (_isConnecting || _currentIp == null) return;
    _isConnecting = true;
    
    final url = 'ws://$_currentIp:8081';
    _logger.i('SyncService: Connecting to $url...');
    
    try {
      _socket = await WebSocket.connect(url).timeout(const Duration(seconds: 5));
      connectionState.value = true;
      _isConnecting = false;
      _logger.i('SyncService: Connected to WebSocket server at $url');
      
      _reconnectTimer?.cancel();
      _reconnectTimer = null;

      _socket!.listen(
        (data) {
          if (data is String) {
            _logger.d('SyncService: Received message: $data');
            _syncController.add(data);
          }
        },
        onDone: () {
          _logger.w('SyncService: WebSocket connection closed by server.');
          _handleDisconnect();
        },
        onError: (error) {
          _logger.e('SyncService: WebSocket error: $error');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _logger.e('SyncService: Connection failed: $e');
      _isConnecting = false;
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    connectionState.value = false;
    _socket = null;
    
    // Attempt reconnection every 5 seconds
    if (_reconnectTimer == null || !_reconnectTimer!.isActive) {
      _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _logger.i('SyncService: Retrying connection...');
        _connect();
      });
    }
  }

  void broadcastEvent(String eventType, [Map<String, dynamic>? data]) {
    // If we are the client, send the event to the server to broadcast to everyone else
    // For simplicity, we just format as JSON
    final jsonStr = '{"event": "$eventType", "timestamp": "${DateTime.now().toIso8601String()}"}';
    
    // Immediately notify all local screen listeners so the active UI updates instantly
    _syncController.add(jsonStr);
    
    if (_socket != null && connectionState.value) {
      _socket!.add(jsonStr);
    } else {
      _logger.i('SyncService: Local broadcast dispatched (socket not connected)');
    }
  }

  Future<void> closeConnection() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = false;
    await _socket?.close();
    _socket = null;
    connectionState.value = false;
  }
}
