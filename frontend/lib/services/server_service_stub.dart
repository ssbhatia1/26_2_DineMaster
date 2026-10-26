class ServerService {
  static final ServerService instance = ServerService._init();

  ServerService._init();

  Future<void> startServer() async {}

  void broadcastSyncMessage(String message, {Object? exclude}) {}
}
