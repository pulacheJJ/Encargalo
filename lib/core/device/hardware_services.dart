import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';

abstract interface class PhotoGateway {
  Future<Photo?> pick(ImageSource source);
  Future<List<Photo>> recover();
}

Uint8List prepareReferenceImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('El archivo no es una imagen compatible.');
  }
  final baked = img.bakeOrientation(decoded);
  final resized =
      baked.width > 1600 || baked.height > 1600
          ? img.copyResize(
            baked,
            width: baked.width >= baked.height ? 1600 : null,
            height: baked.height > baked.width ? 1600 : null,
          )
          : baked;
  resized.exif.clear();
  return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
}

class CameraService implements PhotoGateway {
  final ImagePicker picker;
  CameraService({ImagePicker? picker}) : picker = picker ?? ImagePicker();
  Future<Photo> _persist(XFile file) async {
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException(
        'La imagen original supera los 20 MB. Elija otra.',
      );
    }
    final bytes = await compute(
      prepareReferenceImage,
      await file.readAsBytes(),
    );
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException(
        'La imagen supera los 2 MB después de reducirla.',
      );
    }
    final id = uuid.v4();
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/references',
    );
    await dir.create(recursive: true);
    final target = File('${dir.path}/$id.jpg');
    await target.writeAsBytes(bytes, flush: true);
    return Photo(id: id, localPath: target.path, bytes: bytes.length);
  }

  @override
  Future<Photo?> pick(ImageSource source) async {
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return file == null ? null : _persist(file);
  }

  @override
  Future<List<Photo>> recover() async {
    if (!Platform.isAndroid) return [];
    final response = await picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final photos = <Photo>[];
    for (final file in response.files ?? <XFile>[]) {
      photos.add(await _persist(file));
    }
    return photos;
  }

  Future<void> cleanOrphans(Set<String> referenced) async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/references',
    );
    if (!await dir.exists()) return;
    await for (final file in dir.list()) {
      if (file is File &&
          !referenced.contains(file.path) &&
          (await file.lastModified()).isBefore(
            DateTime.now().subtract(const Duration(days: 7)),
          )) {
        await file.delete();
      }
    }
  }
}

class LocationProblem implements Exception {
  final String message;
  final bool settings, service;
  LocationProblem(this.message, {this.settings = false, this.service = false});
  @override
  String toString() => message;
}

abstract interface class LocationGateway {
  Future<Delivery> locate();
}

class LocationService implements LocationGateway {
  @override
  Future<Delivery> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationProblem(
        'La ubicación está desactivada. Actívela o escriba una referencia.',
        settings: true,
        service: true,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationProblem(
        'El acceso está bloqueado. Puede habilitarlo en Ajustes o continuar sin GPS.',
        settings: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw LocationProblem(
        'No se concedió acceso. Puede reintentar o escribir una referencia.',
      );
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      final accuracy = await Geolocator.getLocationAccuracy();
      return Delivery(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        capturedAt: p.timestamp,
        approximate: accuracy == LocationAccuracyStatus.reduced,
      );
    } on TimeoutException {
      throw LocationProblem(
        'No se obtuvo una lectura reciente a tiempo. Reintente al aire libre o use una referencia manual.',
      );
    }
  }
}
