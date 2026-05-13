import 'app_database.dart';
import 'leccy_repository.dart';
import 'leccy_store.dart';

class NativeLeccyStore extends LeccyRepository {
  NativeLeccyStore._(this._database) : super(_database.database);

  final AppDatabase _database;

  static Future<LeccyStore> open() async {
    final database = await AppDatabase.open();
    return NativeLeccyStore._(database);
  }

  @override
  Future<void> close() => _database.close();
}
