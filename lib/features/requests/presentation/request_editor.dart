import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/domain/models.dart';
import '../../../core/device/hardware_services.dart';
import '../../../core/storage/local_database.dart';

class RequestEditor extends ChangeNotifier {
  RequestDraft draft;
  final LocalDatabase local;
  final PhotoGateway camera;
  final LocationGateway location;
  bool busy = false;
  String? error;
  RequestEditor(
    this.draft,
    this.local, {
    PhotoGateway? camera,
    LocationGateway? location,
  }) : camera = camera ?? CameraService(),
       location = location ?? LocationService();
  Future<void> save() async {
    await local.saveDraft(draft);
  }

  Future<void> addPhoto(ImageSource source) async {
    if (busy) return;
    if (draft.photos.length >= 3) {
      error = 'Solo se admiten tres fotos.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await save();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('camera_draft', draft.id);
      await prefs.setString('camera_owner', draft.ownerId);
      final photo = await camera.pick(source);
      if (photo != null) {
        draft.photos.add(photo);
        await save();
      }
      await prefs.remove('camera_draft');
      await prefs.remove('camera_owner');
    } catch (e) {
      error = 'No se pudo agregar la foto: $e. Puede reintentar o elegir otra.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Delivery?> locate() async {
    if (busy) return null;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await save();
      return await location.locate();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> confirmLocation(Delivery point) async {
    point.reference = draft.delivery.reference;
    draft.delivery = point;
    await save();
    notifyListeners();
  }

  Future<void> removePhoto(Photo photo) async {
    draft.photos.removeWhere((p) => p.id == photo.id);
    await save();
    notifyListeners();
  }
}
