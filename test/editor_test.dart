import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:encargalo/core/domain/models.dart';
import 'package:encargalo/core/device/hardware_services.dart';
import 'package:encargalo/core/storage/local_database.dart';
import 'package:encargalo/features/requests/presentation/request_editor.dart';

class TestCamera implements PhotoGateway {
  Photo? result;
  bool denied = false;
  @override
  Future<Photo?> pick(ImageSource source) async {
    if (denied) throw Exception('Permiso rechazado');
    return result;
  }

  @override
  Future<List<Photo>> recover() async => [];
}

class TestLocation implements LocationGateway {
  @override
  Future<Delivery> locate() async => Delivery(
    latitude: -5.2,
    longitude: -80.6,
    accuracy: 15,
    capturedAt: DateTime.utc(2026, 11, 23),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Dobles de hardware: cancelación, rechazo, tres fotos, confirmación GPS y reapertura',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: LocalDatabase.create,
        ),
      );
      final local = LocalDatabase(db);
      final camera = TestCamera();
      final d = RequestDraft(
        id: uuid.v4(),
        ownerId: 'owner',
        title: 'Mi borrador',
      );
      final vm = RequestEditor(
        d,
        local,
        camera: camera,
        location: TestLocation(),
      );
      await vm.addPhoto(ImageSource.camera);
      expect(d.photos, isEmpty);
      expect(d.title, 'Mi borrador');
      camera.denied = true;
      await vm.addPhoto(ImageSource.camera);
      expect(vm.error, contains('Permiso rechazado'));
      expect(d.title, 'Mi borrador');
      camera.denied = false;
      for (var i = 0; i < 3; i++) {
        camera.result = Photo(
          id: uuid.v4(),
          localPath: 'fixture/$i.jpg',
          bytes: 100,
        );
        await vm.addPhoto(ImageSource.gallery);
      }
      await vm.addPhoto(ImageSource.camera);
      expect(d.photos.length, 3);
      expect(vm.error, contains('tres fotos'));
      final point = await vm.locate();
      expect(d.delivery.hasPoint, false);
      await vm.confirmLocation(point!);
      final restored = await local.draft(d.id, 'owner');
      expect(restored!.photos.length, 3);
      expect(restored.delivery.latitude, -5.2);
      expect(restored.delivery.accuracy, 15);
      vm.dispose();
      await db.close();
    },
  );
}
