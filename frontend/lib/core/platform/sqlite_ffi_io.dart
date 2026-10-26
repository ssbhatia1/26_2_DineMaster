import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initSqliteFfiIfDesktop() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
