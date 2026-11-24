import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/widgets/common.dart';
import '../data/commerce_repository.dart';
import '../domain/commerce.dart';

class OrderCommercePanel extends StatefulWidget {
  final OrderItem order;
  final CommerceGateway? gateway;
  const OrderCommercePanel(this.order, {super.key, this.gateway});
  @override
  State<OrderCommercePanel> createState() => _OrderCommercePanelState();
}

class _OrderCommercePanelState extends State<OrderCommercePanel> {
  late CommerceGateway gateway;
  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    gateway =
        widget.gateway ??
        CommerceRepository(app.repository!.api, app.local!, () => app.owner!);
  }

  Future<void> _payment() async {
    final o = widget.order;
    final initial =
        o.paidCents < o.depositCents
            ? o.depositCents - o.paidCents
            : o.balanceCents;
    final amount = TextEditingController(
      text: (initial / 100).toStringAsFixed(2),
    );
    final form = GlobalKey<FormState>();
    var approved = true;
    try {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder:
            (sheet) => StatefulBuilder(
              builder:
                  (sheet, setSheet) => Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      24,
                      24,
                      MediaQuery.viewInsetsOf(sheet).bottom + 24,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionTitle(
                            'Registrar pago simulado',
                            subtitle:
                                'Prueba académica. No se cobra dinero ni se conecta una billetera. No ingreses datos bancarios.',
                          ),
                          Form(
                            key: form,
                            child: TextFormField(
                              controller: amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Importe de prueba',
                                prefixText: 'S/ ',
                              ),
                              validator: (value) {
                                try {
                                  final cents = parseMoney(value ?? '');
                                  return cents > o.balanceCents
                                      ? 'El importe supera el saldo pendiente'
                                      : null;
                                } catch (_) {
                                  return 'Ingresa un importe válido';
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<bool>(
                            value: approved,
                            decoration: const InputDecoration(
                              labelText: 'Resultado que deseas probar',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: true,
                                child: Text('Aprobado (simulado)'),
                              ),
                              DropdownMenuItem(
                                value: false,
                                child: Text('Rechazado (sin abono)'),
                              ),
                            ],
                            onChanged:
                                (value) =>
                                    setSheet(() => approved = value ?? true),
                          ),
                          const SizedBox(height: 20),
                          TaskButton(
                            'Confirmar simulación',
                            icon: Icons.science_outlined,
                            action: () async {
                              if (!form.currentState!.validate()) return;
                              await gateway.pay(
                                o.id,
                                parseMoney(amount.text),
                                approved,
                                o.version,
                              );
                              if (sheet.mounted) Navigator.pop(sheet);
                              if (mounted) context.read<AppState>().changed();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
      );
    } finally {
      amount.dispose();
    }
  }

  Future<void> _cancel() async {
    final o = widget.order;
    final reason = TextEditingController(),
        retained = TextEditingController(text: '0');
    final form = GlobalKey<FormState>();
    final maximum = math.min(o.paidCents, o.depositCents);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder:
            (sheet) => Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.viewInsetsOf(sheet).bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionTitle(
                        o.status == 'confirmed'
                            ? 'Cancelar antes de producción'
                            : 'Proponer cancelación',
                        subtitle:
                            o.status == 'confirmed'
                                ? 'Se devolverá íntegramente lo pagado en la simulación. Esta acción cierra el pedido.'
                                : 'El pedido no se cancela hasta que la otra parte acepte. La retención no puede superar el adelanto pagado.',
                      ),
                      TextFormField(
                        controller: reason,
                        maxLines: 3,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Motivo y propuesta de solución',
                        ),
                        validator:
                            (v) =>
                                (v?.trim().length ?? 0) < 10
                                    ? 'Explica el motivo con al menos 10 caracteres'
                                    : null,
                      ),
                      if (o.status != 'confirmed')
                        TextFormField(
                          controller: retained,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Retención propuesta (simulada)',
                            prefixText: 'S/ ',
                            helperText:
                                'Máximo ${money(maximum)}. El resto se devuelve al aceptar.',
                          ),
                          validator: (v) {
                            try {
                              final value = parseMoney(
                                v ?? '',
                                allowZero: true,
                              );
                              return value > maximum
                                  ? 'Supera la retención permitida'
                                  : null;
                            } catch (_) {
                              return 'Ingresa 0 o un importe válido';
                            }
                          },
                        ),
                      const SizedBox(height: 16),
                      TaskButton(
                        o.status == 'confirmed'
                            ? 'Confirmar cancelación'
                            : 'Enviar propuesta',
                        action: () async {
                          if (!form.currentState!.validate()) return;
                          final value =
                              o.status == 'confirmed'
                                  ? 0
                                  : parseMoney(retained.text, allowZero: true);
                          await gateway.cancel(
                            o.id,
                            reason.text,
                            value,
                            o.version,
                          );
                          if (sheet.mounted) Navigator.pop(sheet);
                          if (mounted) context.read<AppState>().changed();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
    } finally {
      reason.dispose();
      retained.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final o = widget.order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Pagos y condiciones',
          subtitle: 'Importes del acuerdo, adelanto y saldo.',
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.science_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'SIMULACIÓN · SIN DINERO REAL\nNo ingreses tarjetas, claves bancarias ni códigos de billeteras.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _Amount('Adelanto pactado', o.depositCents),
            _Amount('Pagado (simulado)', o.paidCents),
            _Amount('Saldo pendiente', o.balanceCents),
          ],
        ),
        if (!o.paymentsRequired)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Acuerdo anterior: no exige el nuevo flujo de pagos para sus transiciones.',
            ),
          ),
        DataView<CommerceLedger>(
          revision: app.revision,
          load: () => gateway.ledger(o.id),
          builder: (ledger) {
            final pending = ledger.pending;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending != null) ...[
                  SectionTitle(
                    'Cancelación pendiente de acuerdo',
                    subtitle: pending.reason,
                  ),
                  Text(
                    'Retención propuesta: ${money(pending.retained)} · Devolución: ${money(o.paidCents - pending.retained)} (simuladas)',
                  ),
                  const SizedBox(height: 12),
                  if (pending.requester != app.owner) ...[
                    TaskButton(
                      'Aceptar cancelación y devolución',
                      action: () async {
                        if (!await confirm(
                          context,
                          'Resolver cancelación',
                          'Aceptarás la retención y devolución indicadas. El pedido quedará cancelado.',
                        )) {
                          return;
                        }
                        await gateway.resolve(pending.id, 'accepted');
                        app.changed();
                      },
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await gateway.resolve(pending.id, 'rejected');
                          app.changed();
                        } catch (e) {
                          if (context.mounted) message(context, e.toString());
                        }
                      },
                      child: const Text('Rechazar y continuar el pedido'),
                    ),
                  ] else
                    TaskButton(
                      'Retirar mi propuesta de cancelación',
                      action: () async {
                        await gateway.resolve(pending.id, 'withdrawn');
                        app.changed();
                      },
                    ),
                ] else if (!['delivered', 'cancelled'].contains(o.status)) ...[
                  const SizedBox(height: 16),
                  if (!app.isBusiness && o.balanceCents > 0)
                    TaskButton(
                      'Registrar pago simulado',
                      icon: Icons.account_balance_wallet_outlined,
                      action: _payment,
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.block_outlined),
                    label: Text(
                      o.status == 'confirmed'
                          ? 'Cancelar pedido'
                          : 'Proponer cancelación',
                    ),
                  ),
                ],
                if (ledger.payments.isNotEmpty)
                  const SectionTitle('Movimientos de prueba'),
                for (final entry in ledger.payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry.status == 'declined'
                          ? Icons.error_outline
                          : entry.kind == 'refund'
                          ? Icons.undo
                          : Icons.check_circle_outline,
                    ),
                    title: Text(
                      '${entry.kind == 'refund' ? 'Devolución' : 'Pago'} · ${money(entry.amount)}',
                    ),
                    subtitle: Text(
                      '${entry.status == 'approved' ? 'Aprobado' : 'Rechazado'} · Simulado · ${dateOnly(entry.createdAt.toLocal())}',
                    ),
                  ),
                for (final c in ledger.cancellations.where(
                  (e) => e.status != 'pending',
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text(
                      'Cancelación: ${const {'accepted': 'aceptada', 'rejected': 'rechazada', 'withdrawn': 'retirada'}[c.status] ?? c.status}',
                    ),
                    subtitle: Text(c.reason),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Amount extends StatelessWidget {
  final String label;
  final int value;
  const _Amount(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(money(value), style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}
