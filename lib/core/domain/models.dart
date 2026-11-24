import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
const uuid = Uuid();
String dateOnly(DateTime date) => date.toIso8601String().substring(0, 10);
String money(int cents) =>
    'S/ ${(cents ~/ 100)}.${(cents % 100).toString().padLeft(2, '0')}';
int parseMoney(String input, {bool allowZero = false}) {
  final text = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text)) {
    throw const FormatException('Ingrese soles con hasta dos decimales');
  }
  final parts = text.split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if ((!allowZero && cents <= 0) || cents > 100000000) {
    throw const FormatException(
      'El total debe estar entre S/ 0.01 y S/ 1000000.00',
    );
  }
  return cents;
}

String statusLabel(String status) =>
    const {
      'open': 'Publicada',
      'awarded': 'Con pedido',
      'deleted': 'Cancelada',
      'draft': 'Borrador',
      'pending': 'Pendiente de nube',
      'synced': 'Confirmada en nube',
      'confirmed': 'Confirmado',
      'production': 'En producción',
      'ready': 'Listo',
      'delivered': 'Entregado',
      'sent': 'Enviada',
      'accepted': 'Aceptada',
      'not_selected': 'No seleccionada',
      'cancelled': 'Cancelado',
    }[status] ??
    status;

class Profile {
  final String id, role, name, district, description;
  final List<String> categories;
  final String? locationCode;
  final String businessAddress, businessHours, website;
  Profile.fromJson(Json j)
    : id = j['id'],
      role = j['role'],
      name = j['name'],
      district = j['district'],
      description = j['description'],
      categories = List<String>.from(j['categories']),
      locationCode = j['location_code'],
      businessAddress = j['business_address'] ?? '',
      businessHours = j['business_hours'] ?? '',
      website = j['website'] ?? '';
  bool get isBusiness => role == 'negocio';
  Json toJson() => {
    'id': id,
    'role': role,
    'name': name,
    'district': district,
    'description': description,
    'categories': categories,
    'location_code': locationCode,
    'business_address': businessAddress,
    'business_hours': businessHours,
    'website': website,
  };
}

class Category {
  final String id, name;
  Category.fromJson(Json j) : id = j['id'], name = j['name'];
  Json toJson() => {'id': id, 'name': name};
}

class Delivery {
  String reference;
  double? latitude, longitude, accuracy;
  DateTime? capturedAt;
  bool approximate;
  Delivery({
    this.reference = '',
    this.latitude,
    this.longitude,
    this.accuracy,
    this.capturedAt,
    this.approximate = false,
  });
  Delivery.fromJson(Json j)
    : reference = j['reference'] ?? '',
      latitude = (j['latitude'] as num?)?.toDouble(),
      longitude = (j['longitude'] as num?)?.toDouble(),
      accuracy = (j['accuracy'] as num?)?.toDouble(),
      capturedAt = DateTime.tryParse(j['captured_at'] ?? ''),
      approximate = j['approximate'] ?? false;
  bool get hasPoint => latitude != null && longitude != null;
  Json toJson() => {
    'reference': reference,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'captured_at': capturedAt?.toUtc().toIso8601String(),
    'approximate': approximate,
  };
}

class Photo {
  final String id;
  String? localPath, objectPath;
  final int bytes;
  final String mime;
  Photo({
    required this.id,
    this.localPath,
    this.objectPath,
    required this.bytes,
    this.mime = 'image/jpeg',
  });
  Photo.fromJson(Json j)
    : id = j['id'],
      localPath = j['local_path'],
      objectPath = j['object_path'],
      bytes = j['bytes'],
      mime = j['mime'];
  Json toRemote() => {
    'id': id,
    'object_path': objectPath,
    'bytes': bytes,
    'mime': mime,
  };
  Json toLocal() => {...toRemote(), 'local_path': localPath};
}

class RequestItem {
  final String id, ownerId, title, detail, categoryId, district, status;
  final int quantity, version, quoteCount;
  final DateTime desiredDate;
  final List<Photo> photos;
  final String? locationCode;
  final Json specifications;
  RequestItem.fromJson(Json j)
    : id = j['id'],
      ownerId = j['owner_id'],
      title = j['title'],
      detail = j['detail'],
      categoryId = j['category_id'],
      district = j['district'],
      status = j['status'],
      quantity = j['quantity'],
      version = j['version'],
      quoteCount = j['quote_count'] ?? 0,
      desiredDate = DateTime.parse(j['desired_date']),
      locationCode = j['location_code'],
      specifications = Map<String, dynamic>.from(j['specifications'] ?? {}),
      photos =
          (j['request_photos'] as List? ?? [])
              .map((p) => Photo.fromJson(Map<String, dynamic>.from(p)))
              .toList();
}

class RequestDraft {
  final String id, ownerId;
  String title, detail, categoryId, district, syncState;
  String? operation;
  int quantity, remoteVersion;
  DateTime desiredDate;
  Delivery delivery;
  List<Photo> photos;
  String? locationCode;
  Json specifications;
  RequestDraft({
    required this.id,
    required this.ownerId,
    this.title = '',
    this.detail = '',
    this.categoryId = '',
    this.district = 'Piura',
    this.quantity = 1,
    DateTime? desiredDate,
    Delivery? delivery,
    List<Photo>? photos,
    this.remoteVersion = 0,
    this.syncState = 'draft',
    this.operation,
    this.locationCode,
    Json? specifications,
  }) : desiredDate = desiredDate ?? DateTime.now().add(const Duration(days: 7)),
       delivery = delivery ?? Delivery(),
       photos = photos ?? [],
       specifications = specifications ?? {};
  factory RequestDraft.fromLocal(Json j) => RequestDraft(
    id: j['id'],
    ownerId: j['owner_id'],
    title: j['title'],
    detail: j['detail'],
    categoryId: j['category_id'],
    district: j['district'],
    quantity: j['quantity'],
    desiredDate: DateTime.parse(j['desired_date']),
    delivery: Delivery.fromJson(Map<String, dynamic>.from(j['delivery'])),
    photos:
        (j['photos'] as List)
            .map((p) => Photo.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
    remoteVersion: j['remote_version'] ?? 0,
    syncState: j['sync_state'] ?? 'draft',
    operation: j['operation'],
    locationCode: j['location_code'],
    specifications: Map<String, dynamic>.from(j['specifications'] ?? {}),
  );
  Json toRemote() => {
    'id': id,
    'title': title.trim(),
    'detail': detail.trim(),
    'category_id': categoryId,
    'district': district.trim(),
    'quantity': quantity,
    'desired_date': dateOnly(desiredDate),
    'delivery': delivery.toJson(),
    'photos': photos.map((p) => p.toRemote()).toList(),
    'location_code': locationCode,
    'specifications': specifications,
  };
  Json toLocal() => {
    ...toRemote(),
    'owner_id': ownerId,
    'photos': photos.map((p) => p.toLocal()).toList(),
    'remote_version': remoteVersion,
    'sync_state': syncState,
    'operation': operation,
  };
  String? validate() {
    if (title.trim().length < 3 || title.trim().length > 120) {
      return 'El título debe tener entre 3 y 120 caracteres';
    }
    if (detail.trim().length < 10 || detail.trim().length > 5000) {
      return 'Las especificaciones deben tener entre 10 y 5000 caracteres';
    }
    if (categoryId.isEmpty) return 'Seleccione una categoría';
    if (quantity < 1 || quantity > 100000) {
      return 'La cantidad debe estar entre 1 y 100000';
    }
    if (district.trim().length < 2) return 'Ingrese el distrito';
    if (dateOnly(desiredDate).compareTo(dateOnly(DateTime.now())) < 0) {
      return 'Elija una fecha actual o futura';
    }
    if (photos.length > 3) return 'Solo se admiten tres fotos';
    return null;
  }
}

class Quote {
  final String id, requestId, businessId, conditions, status;
  final int totalCents, quantity, version;
  final DateTime promisedDate, expiresAt;
  final int depositCents;
  Quote.fromJson(Json j)
    : id = j['id'],
      requestId = j['request_id'],
      businessId = j['business_id'],
      conditions = j['conditions'],
      status = j['status'],
      totalCents = (j['total_cents'] as num).toInt(),
      quantity = j['quantity'],
      version = j['version'],
      promisedDate = DateTime.parse(j['promised_date']),
      expiresAt = DateTime.parse(j['expires_at']),
      depositCents = (j['deposit_cents'] as num?)?.toInt() ?? 0;
}

class OrderItem {
  final String id,
      requestId,
      clientId,
      businessId,
      businessName,
      title,
      conditions,
      status;
  final int totalCents, quantity, version;
  final DateTime promisedDate;
  final int depositCents, paidCents;
  final bool paymentsRequired;
  OrderItem.fromJson(Json j)
    : id = j['id'],
      requestId = j['request_id'],
      clientId = j['client_id'],
      businessId = j['business_id'],
      businessName = j['business_name'],
      title = j['title'],
      conditions = j['conditions'],
      status = j['status'],
      totalCents = (j['total_cents'] as num).toInt(),
      quantity = j['quantity'],
      version = j['version'],
      promisedDate = DateTime.parse(j['promised_date']),
      depositCents = (j['deposit_cents'] as num?)?.toInt() ?? 0,
      paidCents = (j['paid_cents'] as num?)?.toInt() ?? 0,
      paymentsRequired = j['payments_required'] ?? false;
  int get balanceCents => status == 'cancelled' ? 0 : totalCents - paidCents;
  String? advanceBlockReason(bool business) {
    if (!paymentsRequired) return null;
    if (business && status == 'confirmed' && paidCents < depositCents) {
      return 'Para iniciar producción falta ${money(depositCents - paidCents)} del adelanto simulado.';
    }
    if (!business && status == 'ready' && paidCents < totalCents) {
      return 'Completa el saldo simulado de ${money(totalCents - paidCents)} antes de confirmar la recepción.';
    }
    return null;
  }

  String? nextStatus(bool business) =>
      business
          ? (status == 'confirmed'
              ? 'production'
              : status == 'production'
              ? 'ready'
              : null)
          : (status == 'ready' ? 'delivered' : null);
}

class Notice {
  final String id, title, body;
  final String? requestId, orderId;
  final bool read;
  final DateTime createdAt;
  Notice.fromJson(Json j)
    : id = j['id'],
      title = j['title'],
      body = j['body'],
      requestId = j['request_id'],
      orderId = j['order_id'],
      read = j['read_at'] != null,
      createdAt = DateTime.parse(j['created_at']);
}
