import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:encargalo/app/theme.dart';
import 'package:encargalo/core/domain/models.dart';
import 'package:encargalo/features/requests/presentation/request_editor_screen.dart';
import 'package:encargalo/core/storage/local_database.dart';
import 'package:encargalo/app/app_state.dart';

void main() {
  sqfliteFfiInit();
  for (final width in [360.0, 390.0, 430.0, 720.0]) {
    testWidgets(
      'Formulario con 50 borradores fixture, ancho $width y texto ampliado',
      (tester) async {
        await tester.runAsync(() async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = await databaseFactoryFfi.openDatabase(
            inMemoryDatabasePath,
            options: OpenDatabaseOptions(
              version: 2,
              onCreate: LocalDatabase.create,
            ),
          );
          final local = LocalDatabase(db);
          final watch = Stopwatch()..start();
          // Solo fixtures locales de test, sin cuentas ni publicación prefabricadas.
          await db.transaction((tx) async {
            for (var i = 0; i < 50; i++) {
              final d = RequestDraft(
                id: uuid.v4(),
                ownerId: 'fixture-owner',
                title: 'Borrador de prueba $i',
              );
              await tx.insert('drafts', {
                'id': d.id,
                'owner': d.ownerId,
                'payload': jsonEncode(d.toLocal()),
                'updated': '2026-11-23',
              });
            }
          });
          expect((await local.drafts('fixture-owner')).length, 50);
          watch.stop();
          final app =
              AppState()
                ..local = local
                ..categories = [
                  Category.fromJson({'id': 'estampado', 'name': 'Estampado'}),
                ];
          final draft = RequestDraft(id: uuid.v4(), ownerId: 'fixture-owner');
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: app,
              child: MaterialApp(
                theme: appTheme(Brightness.light),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 900),
                    textScaler: TextScaler.linear(1.3),
                  ),
                  child: RequestEditorScreen(draft),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).first,
            'Polos para la UNP',
          );
          await tester.pumpAndSettle();
          expect(draft.title, 'Polos para la UNP');
          expect(tester.takeException(), null);
          // ignore: avoid_print
          print(
            'FORMULARIO_FIXTURE: ancho=$width; 50 borradores SQLite FFI insertados/consultados en ${watch.elapsedMilliseconds} ms; edición sin excepción. No es medición en Android.',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          app.dispose();
          await db.close();
        });
      },
    );
  }
}
