import 'package:flutter_test/flutter_test.dart';
import 'package:encargalo/core/domain/models.dart';

void main() {
  test('Adelanto o retención admite cero decimal sin permitir total cero', () {
    expect(parseMoney('0.00', allowZero: true), 0);
    expect(parseMoney('0,0', allowZero: true), 0);
    expect(() => parseMoney('0.00'), throwsFormatException);
  });
  test('Moneda exacta sin punto flotante', () {
    expect(parseMoney('12,30'), 1230);
    expect(parseMoney('0.01'), 1);
    expect(money(1230), 'S/ 12.30');
    for (final v in ['0', '-1', '1.999', 'NaN', '1e3']) {
      expect(() => parseMoney(v), throwsFormatException);
    }
  });
  test(
    'Contrato local conserva fotos y GPS, remoto no expone rutas del teléfono',
    () {
      final d = RequestDraft(
        id: uuid.v4(),
        ownerId: uuid.v4(),
        title: 'Polos UNP',
        detail: 'Treinta polos morados con estampado',
        categoryId: 'estampado',
        quantity: 30,
        delivery: Delivery(
          latitude: -5.19,
          longitude: -80.63,
          accuracy: 12,
          capturedAt: DateTime.utc(2026, 11, 23),
          approximate: true,
        ),
        photos: [
          Photo(id: uuid.v4(), localPath: 'privado/foto.jpg', bytes: 1200),
        ],
      );
      final copy = RequestDraft.fromLocal(d.toLocal());
      expect(copy.photos.single.localPath, 'privado/foto.jpg');
      expect(copy.delivery.latitude, -5.19);
      expect(copy.delivery.approximate, true);
      expect(
        (d.toRemote()['photos'] as List).single.containsKey('local_path'),
        false,
      );
      expect(d.validate(), null);
      d.photos = List.generate(4, (_) => Photo(id: uuid.v4(), bytes: 10));
      expect(d.validate(), 'Solo se admiten tres fotos');
    },
  );
  test('Transiciones por rol no permiten saltos en la interfaz', () {
    final j = {
      'id': 'a',
      'request_id': 'b',
      'client_id': 'c',
      'business_id': 'd',
      'business_name': 'Taller',
      'title': 'Polos',
      'conditions': 'Prueba',
      'total_cents': 1000,
      'quantity': 1,
      'version': 1,
      'promised_date': '2026-12-01',
      'status': 'confirmed',
    };
    final o = OrderItem.fromJson(j);
    expect(o.nextStatus(true), 'production');
    expect(o.nextStatus(false), null);
    j['status'] = 'ready';
    expect(OrderItem.fromJson(j).nextStatus(false), 'delivered');
    expect(OrderItem.fromJson(j).nextStatus(true), null);
  });
}
