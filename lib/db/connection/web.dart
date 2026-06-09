import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor openConnection(String uid) {
  return WebDatabase('ledgy_$uid');
}
