import 'leccy_store.dart';
import 'native_leccy_store.dart';

Future<LeccyStore> openLeccyStore() => NativeLeccyStore.open();
