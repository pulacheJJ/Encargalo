import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:encargalo/core/device/hardware_services.dart';

void main() {
  test('Compresión medida con fixture generado, no fotografía real', () {
    final input = img.Image(width: 2400, height: 1800);
    for (var y = 0; y < input.height; y++) {
      for (var x = 0; x < input.width; x++) {
        input.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final original = Uint8List.fromList(img.encodeJpg(input, quality: 96));
    final bytes = prepareReferenceImage(original);
    final decoded = img.decodeJpg(bytes)!;
    expect(decoded.width, 1600);
    expect(decoded.height, 1200);
    expect(bytes.length, lessThan(2097152));
    expect(decoded.exif.isEmpty, true);
    expect(bytes.length, lessThan(original.length));
    // Registro reproducible de un fixture, sin atribuirlo a una captura de hardware.
    // ignore: avoid_print
    print(
      'IMAGEN_FIXTURE: original=${original.length} bytes 2400x1800; preparada=${bytes.length} bytes ${decoded.width}x${decoded.height} JPEG, sin EXIF',
    );
  });
}
