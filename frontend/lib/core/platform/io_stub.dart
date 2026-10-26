class FileSystemEntity {
  FileSystemEntity(this.path);
  final String path;
}

class File extends FileSystemEntity {
  File(super.path);

  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<File> copy(String newPath) async => File(newPath);
  Future<File> rename(String newPath) async => File(newPath);
  Future<void> delete() async {}
  DateTime lastModifiedSync() => DateTime.fromMillisecondsSinceEpoch(0);
  int lengthSync() => 0;
}

class Directory extends FileSystemEntity {
  Directory(super.path);

  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<Directory> create({bool recursive = false}) async => this;
  List<FileSystemEntity> listSync() => const [];
}

class Platform {
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static Map<String, String> get environment => const {};
}

class InternetAddress {
  String get address => '127.0.0.1';
  static final InternetAddress anyIPv4 = InternetAddress();
}

class InternetAddressType {
  static const InternetAddressType IPv4 = InternetAddressType();
  const InternetAddressType();
}

class NetworkInterface {
  NetworkInterface(this.addresses);
  final List<InternetAddress> addresses;

  static Future<List<NetworkInterface>> list({
    InternetAddressType? type,
    bool includeLinkLocal = false,
    bool includeLoopback = false,
  }) async =>
      const [];
}

class WebSocket {
  static Future<WebSocket> connect(String url) {
    throw UnsupportedError('dart:io WebSocket is not available on web');
  }

  void add(dynamic data) {}

  StreamSubscription listen(
    void Function(dynamic event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    throw UnsupportedError('dart:io WebSocket is not available on web');
  }

  Future close() async {}
}

class StreamSubscription {
  Future cancel() async {}
}

class HttpServer {
  static Future<HttpServer> bind(Object address, int port) {
    throw UnsupportedError('HttpServer is not available on web');
  }
}

class WebSocketTransformer {
  static bool isUpgradeRequest(Object request) => false;
}

class HttpHeaders {
  void set(String name, Object value) {}
}

class HttpClientRequest {
  final HttpHeaders headers = HttpHeaders();

  void write(Object? object) {}

  Future<HttpClientResponse> close() async {
    throw UnsupportedError('HttpClient is not available on web');
  }
}

class HttpClientResponse {
  int get statusCode => 500;

  Stream<List<int>> transform(Object decoder) => const Stream.empty();
}

class HttpClient {
  set connectionTimeout(Duration value) {}
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw UnsupportedError('HttpClient is not available on web');
  }
  Future<HttpClientRequest> postUrl(Uri url) async {
    throw UnsupportedError('HttpClient is not available on web');
  }

  void close() {}
}

