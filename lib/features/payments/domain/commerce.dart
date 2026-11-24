class PaymentEntry {
  final String id, kind, status;
  final int amount;
  final DateTime createdAt;
  PaymentEntry.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      kind = j['kind'],
      status = j['status'],
      amount = (j['amount_cents'] as num).toInt(),
      createdAt = DateTime.parse(j['created_at']);
}

class CancellationEntry {
  final String id, requester, reason, status;
  final int retained;
  CancellationEntry.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      requester = j['requested_by'],
      reason = j['reason'],
      status = j['status'],
      retained = (j['retained_cents'] as num).toInt();
}

class CommerceLedger {
  final List<PaymentEntry> payments;
  final List<CancellationEntry> cancellations;
  const CommerceLedger(this.payments, this.cancellations);
  CancellationEntry? get pending {
    for (final entry in cancellations) {
      if (entry.status == 'pending') return entry;
    }
    return null;
  }
}

abstract interface class CommerceGateway {
  Future<CommerceLedger> ledger(String order);
  Future<void> pay(String order, int amount, bool approved, int version);
  Future<void> cancel(String order, String reason, int retained, int version);
  Future<void> resolve(String cancellation, String decision);
}
