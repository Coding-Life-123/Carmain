import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  /// [executor] permite inyectar una conexión distinta — en tests, una
  /// base en memoria (`NativeDatabase.memory()`). En producción se usa
  /// el archivo local del dispositivo.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

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
