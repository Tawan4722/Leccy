import 'leccy_store.dart';
import 'memory_leccy_store.dart';

Future<LeccyStore> openLeccyStore() async => MemoryLeccyStore();
