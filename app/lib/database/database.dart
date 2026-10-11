import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'tables.dart';

part 'database.g.dart';

/// Base de datos local del dispositivo (local-first).
///
/// Toda la información del vehículo vive aquí, en el dispositivo del dueño.
/// No hay servidor central de datos — esta DB es la copia autoritativa.
@DriftDatabase(tables: [
  Vehiculos,
  PlanesMantenimiento,
  RegistrosMantenimiento,
  SesionesMecanico,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'carmain.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        // Optimización para SQLite en móvil.
        db.execute('PRAGMA journal_mode = WAL;');
        db.execute('PRAGMA foreign_keys = ON;');
      },
    );
  });
}
