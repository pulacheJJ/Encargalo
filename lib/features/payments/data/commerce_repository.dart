import 'dart:convert';
import '../../../core/domain/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_database.dart';
import '../domain/commerce.dart';

class CommerceRepository implements CommerceGateway {
  final ApiClient api;
  final LocalDatabase local;
  final String Function() actor;
  CommerceRepository(this.api, this.local, this.actor);
  @override
  Future<CommerceLedger> ledger(String order) async {
    final rows = await Future.wait([
      api.select(
        'order_payments',
        query: {
          'order_id': 'eq.$order',
          'order': 'created_at.desc',
          'limit': 100,
        },
      ),
      api.select(
        'order_cancellations',
        query: {
          'order_id': 'eq.$order',
          'order': 'created_at.desc',
          'limit': 30,
        },
      ),
    ]);
    return CommerceLedger(
      rows[0].map(PaymentEntry.fromJson).toList(),
      rows[1].map(CancellationEntry.fromJson).toList(),
    );
  }

  Future<void> _execute(String rpc, String intent, Json arguments) async {
    final owner = actor();
    final key = 'commerce-operation:$owner:$rpc:$intent';
    final operation = await local.operationFor(key);
    try {
      await api.rpc(rpc, {
        ...arguments,
        'p_operation': operation,
      }, expectedSubject: owner);
    } on ApiFailure catch (e) {
      if (e.retryable) {
        throw ApiFailure(
          'No se confirmó la respuesta. Revisa los movimientos y reintenta la misma operación; se conserva su identificador para no duplicarla.',
          retryable: true,
        );
      }
      rethrow;
    }
    // Only a confirmed server response permits creating another intent.
    await local.completeOperation(key, operation);
  }

  @override
  Future<void> pay(String order, int amount, bool approved, int version) =>
      _execute('simulate_order_payment', '$order:$amount:$approved', {
        'p_order': order,
        'p_amount': amount,
        'p_approved': approved,
        'p_expected_version': version,
      });
  @override
  Future<void> cancel(String order, String reason, int retained, int version) =>
      _execute(
        'request_order_cancellation',
        jsonEncode([order, reason.trim(), retained]),
        {
          'p_order': order,
          'p_reason': reason.trim(),
          'p_retained': retained,
          'p_expected_version': version,
        },
      );
  @override
  Future<void> resolve(String cancellation, String decision) => _execute(
    'resolve_order_cancellation',
    '$cancellation:$decision',
    {'p_cancellation': cancellation, 'p_decision': decision},
  );
}
