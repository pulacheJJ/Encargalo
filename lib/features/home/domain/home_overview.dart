import '../../../core/domain/models.dart';

class HomeOverview {
  final int requestsCount, quotesCount, ordersCount;
  final List<RequestItem> requests;
  final List<OrderItem> orders;
  HomeOverview.fromJson(Json j)
    : requestsCount = (j['requests_count'] as num).toInt(),
      quotesCount = (j['quotes_count'] as num).toInt(),
      ordersCount = (j['orders_count'] as num).toInt(),
      requests =
          (j['requests'] as List)
              .map((e) => RequestItem.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
      orders =
          (j['orders'] as List)
              .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
}
