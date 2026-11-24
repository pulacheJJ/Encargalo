import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/domain/models.dart';
import '../../../core/domain/json_codec.dart';
import '../../../app/app_state.dart';
import '../../../core/widgets/common.dart';
import '../../requests/presentation/request_editor_screen.dart';
import '../../payments/presentation/order_commerce_panel.dart';

Future<void> createRequest(BuildContext context) async {
  final app = context.read<AppState>();
  final d = RequestDraft(
    id: uuid.v4(),
    ownerId: app.owner!,
    district: app.profile!.district,
    locationCode: app.profile!.locationCode,
  );
  await app.local!.saveDraft(d);
  if (context.mounted) await openPage(context, RequestEditorScreen(d));
  app.changed();
}

class RequestListScreen extends StatefulWidget {
  final bool business;
  final String? initialCategory;
  const RequestListScreen({
    super.key,
    required this.business,
    this.initialCategory,
  });
  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  final search = TextEditingController(), district = TextEditingController();
  String query = '';
  String? category, status;
  int refresh = 0, offset = 0;
  @override
  void initState() {
    super.initState();
    category = widget.initialCategory;
  }

  @override
  void dispose() {
    search.dispose();
    district.dispose();
    super.dispose();
  }

  void reload() => setState(() {
    offset = 0;
    refresh++;
    query = search.text.trim();
  });
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PageBody(
      children: [
        SectionTitle(
          widget.business
              ? 'Encuentra tu próximo encargo'
              : 'Tus ideas, en marcha',
          subtitle:
              widget.business
                  ? 'Oportunidades de tus categorías. La dirección precisa no se muestra.'
                  : 'Los borradores permanecen en este teléfono hasta publicarlos.',
        ),
        if (!widget.business) ...[
          FilledButton.icon(
            onPressed: () => createRequest(context),
            icon: const Icon(Icons.add),
            label: const Text('Crear solicitud'),
          ),
          const SizedBox(height: 12),
          DataView<List<RequestDraft>>(
            revision: app.revision,
            load: () => app.local!.drafts(app.owner!),
            builder:
                (drafts) => Column(
                  children: [
                    for (final d in drafts.where(
                      (d) =>
                          d.syncState != 'synced' && d.syncState != 'deleted',
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.edit_note),
                            title: Text(
                              d.title.isEmpty
                                  ? 'Solicitud sin título'
                                  : d.title,
                            ),
                            subtitle: Text(statusLabel(d.syncState)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              if (d.syncState == 'pending') {
                                message(
                                  context,
                                  'La publicación está pendiente. Revísela en Sincronización.',
                                );
                                return;
                              }
                              await openPage(context, RequestEditorScreen(d));
                              if (mounted) setState(() => refresh++);
                              app.changed();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
          ),
        ],
        TextField(
          controller: search,
          decoration: InputDecoration(
            labelText: 'Buscar por título',
            suffixIcon: IconButton(
              tooltip: 'Buscar',
              onPressed: reload,
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) => reload(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todas las categorías'),
              selected: category == null,
              onSelected: (_) {
                category = null;
                reload();
              },
            ),
            for (final c in app.categories)
              ChoiceChip(
                label: Text(c.name),
                selected: category == c.id,
                onSelected: (_) {
                  category = c.id;
                  reload();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.business)
          TextField(
            controller: district,
            decoration: InputDecoration(
              labelText: 'Distrito (coincidencia exacta)',
              suffixIcon: IconButton(
                tooltip: 'Filtrar distrito',
                onPressed: reload,
                icon: const Icon(Icons.filter_alt_outlined),
              ),
            ),
            onSubmitted: (_) => reload(),
          ),
        if (!widget.business)
          DropdownButtonFormField<String>(
            value: status ?? 'all',
            decoration: const InputDecoration(labelText: 'Estado'),
            items: [
              const DropdownMenuItem(
                value: 'all',
                child: Text('Todos los estados'),
              ),
              for (final s in ['open', 'awarded', 'deleted'])
                DropdownMenuItem(value: s, child: Text(statusLabel(s))),
            ],
            onChanged: (v) {
              status = v == 'all' ? null : v;
              reload();
            },
          ),
        const SizedBox(height: 16),
        DataView<List<RequestItem>>(
          revision: app.revision + refresh,
          load:
              () => app.repository!.requests(
                business: widget.business,
                search: query,
                category: category,
                status: status,
                district: widget.business ? district.text.trim() : null,
                offset: offset,
              ),
          builder:
              (items) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    const EmptyState(
                      'No hay solicitudes aquí',
                      'Prueba otros filtros o vuelve cuando haya nuevos encargos.',
                    ),
                  for (final item in items)
                    RequestCard(
                      item,
                      onTap:
                          () => openPage(context, RequestDetailScreen(item.id)),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed:
                            offset == 0
                                ? null
                                : () => setState(() {
                                  offset -= 30;
                                  refresh++;
                                }),
                        child: const Text('Anterior'),
                      ),
                      Text('Página ${offset ~/ 30 + 1}'),
                      TextButton(
                        onPressed:
                            items.length < 30
                                ? null
                                : () => setState(() {
                                  offset += 30;
                                  refresh++;
                                }),
                        child: const Text('Siguiente'),
                      ),
                    ],
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

class RequestDetailScreen extends StatefulWidget {
  final String id;
  const RequestDetailScreen(this.id, {super.key});
  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  int refresh = 0;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(app.isBusiness ? 'Oportunidad' : 'Detalle de solicitud'),
      ),
      body: PageBody(
        children: [
          DataView<RequestItem>(
            revision: app.revision + refresh,
            load: () => app.repository!.request(widget.id),
            builder:
                (r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatusChip(r.status),
                    SectionTitle(
                      r.title,
                      subtitle:
                          '${r.quantity} unidades · ${r.district} · ${dateOnly(r.desiredDate)}',
                    ),
                    for (final p in r.photos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PhotoView(p),
                      ),
                    if (r.photos.isEmpty)
                      const EmptyState(
                        'Sin fotos de referencia',
                        'Las especificaciones escritas describen este encargo.',
                        icon: Icons.image_outlined,
                      ),
                    const SectionTitle('Lo que se necesita'),
                    Text(r.detail),
                    if (r.specifications.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in r.specifications.entries
                                  .where(
                                    (e) => e.value.toString().trim().isNotEmpty,
                                  ))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        const {
                                              'material': 'Material',
                                              'color': 'Colores',
                                              'dimensions': 'Tallas y medidas',
                                              'design': 'Diseño',
                                              'finish': 'Acabado y empaque',
                                              'delivery_mode':
                                                  'Forma de entrega',
                                            }[entry.key] ??
                                            entry.key,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                      ),
                                      Text(
                                        const {
                                              'coordinar': 'Por coordinar',
                                              'recojo': 'Recojo en negocio',
                                              'entrega':
                                                  'Entrega en punto acordado',
                                            }[entry.value] ??
                                            entry.value.toString(),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    DataView<Delivery?>(
                      revision: app.revision,
                      load: () => app.repository!.delivery(r.id),
                      builder:
                          (d) =>
                              d == null
                                  ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Text(
                                      'El punto y la referencia de entrega se comparten solo con el negocio elegido.',
                                    ),
                                  )
                                  : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SectionTitle('Entrega privada'),
                                      Text(
                                        d.reference.isEmpty
                                            ? 'Sin referencia escrita'
                                            : d.reference,
                                      ),
                                      if (d.hasPoint)
                                        OutlinedButton.icon(
                                          onPressed:
                                              () => openPage(
                                                context,
                                                LocationScreen(d),
                                              ),
                                          icon: const Icon(
                                            Icons.location_on_outlined,
                                          ),
                                          label: const Text(
                                            'Ver punto confirmado',
                                          ),
                                        ),
                                    ],
                                  ),
                    ),
                    const SizedBox(height: 16),
                    if (app.isBusiness && r.status == 'open')
                      DataView<List<Quote>>(
                        revision: app.revision + refresh,
                        load: () => app.repository!.quotes(request: r.id),
                        builder:
                            (quotes) => TaskButton(
                              quotes.isEmpty
                                  ? 'Cotizar este encargo'
                                  : 'Revisar mi cotización',
                              icon: Icons.request_quote_outlined,
                              action: () async {
                                await openPage(
                                  context,
                                  QuoteEditorScreen(
                                    r,
                                    existing:
                                        quotes.isEmpty ? null : quotes.first,
                                  ),
                                );
                                setState(() => refresh++);
                              },
                            ),
                      ),
                    if (!app.isBusiness && r.status == 'open') ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          final qs = await app.repository!.quotes(
                            request: r.id,
                          );
                          if (!context.mounted) return;
                          if (qs.isNotEmpty) {
                            message(
                              context,
                              'Ya hay cotizaciones. Se puede cancelar, pero no cambiar el acuerdo solicitado.',
                            );
                            return;
                          }
                          final pending = await app.local!.pending(app.owner!);
                          if (pending.any((o) => o['entity'] == r.id)) {
                            if (context.mounted) {
                              message(
                                context,
                                'Resuelva la operación pendiente antes de editar.',
                              );
                            }
                            return;
                          }
                          final d = await app.repository!.delivery(r.id);
                          if (!context.mounted) return;
                          final draft = RequestDraft(
                            id: r.id,
                            ownerId: r.ownerId,
                            title: r.title,
                            detail: r.detail,
                            categoryId: r.categoryId,
                            district: r.district,
                            quantity: r.quantity,
                            desiredDate: r.desiredDate,
                            delivery: d,
                            photos: r.photos,
                            remoteVersion: r.version,
                            locationCode: r.locationCode,
                            specifications: r.specifications,
                          );
                          await openPage(context, RequestEditorScreen(draft));
                          setState(() => refresh++);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar solicitud'),
                      ),
                      TaskButton(
                        'Cancelar solicitud',
                        icon: Icons.cancel_outlined,
                        action: () async {
                          if (!await confirm(
                            context,
                            'Cancelar solicitud',
                            'Las cotizaciones dejarán de estar disponibles. Una solicitud con pedido confirmado no se puede cancelar.',
                          )) {
                            return;
                          }
                          final d =
                              await app.local!.draft(r.id, r.ownerId) ??
                              RequestDraft(
                                id: r.id,
                                ownerId: r.ownerId,
                                title: r.title,
                                detail: r.detail,
                                quantity: r.quantity,
                                categoryId: r.categoryId,
                                district: r.district,
                                desiredDate: r.desiredDate,
                                photos: r.photos,
                                remoteVersion: r.version,
                              );
                          d.remoteVersion = r.version;
                          await app.local!.enqueue(d, action: 'delete');
                          await app.synchronize();
                          if (mounted) setState(() => refresh++);
                        },
                      ),
                    ],
                    if (!app.isBusiness) ...[
                      const SectionTitle(
                        'Cotizaciones para comparar',
                        subtitle:
                            'Se comparan importes totales, fecha de elaboración y condiciones reales.',
                      ),
                      QuoteComparison(request: r),
                    ],
                  ],
                ),
          ),
        ],
      ),
    );
  }
}

class QuoteComparison extends StatefulWidget {
  final RequestItem request;
  const QuoteComparison({super.key, required this.request});
  @override
  State<QuoteComparison> createState() => _QuoteComparisonState();
}

class _QuoteComparisonState extends State<QuoteComparison> {
  int offset = 0, refresh = 0;
  final operation = uuid.v4();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return DataView<List<Quote>>(
      revision: app.revision + refresh,
      load:
          () => app.repository!.quotes(
            request: widget.request.id,
            offset: offset,
          ),
      builder:
          (quotes) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (quotes.isEmpty)
                const EmptyState(
                  'Aún no hay propuestas',
                  'Las cotizaciones de los negocios aparecerán aquí en tiempo real.',
                  icon: Icons.request_quote_outlined,
                ),
              for (final q in quotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DataView<Profile>(
                            load: () => app.repository!.profile(q.businessId),
                            builder:
                                (business) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.storefront_outlined,
                                  ),
                                  title: Text(business.name),
                                  subtitle: Text(business.district),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap:
                                      () => openPage(
                                        context,
                                        BusinessProfileScreen(business),
                                      ),
                                ),
                          ),
                          Text(
                            money(q.totalCents),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text('Total por ${q.quantity} unidades'),
                          Text(
                            'Adelanto: ${money(q.depositCents)} · Saldo: ${money(q.totalCents - q.depositCents)}',
                          ),
                          const Text('Pagos de prueba, sin dinero real.'),
                          Text('Elaboración: ${dateOnly(q.promisedDate)}'),
                          Text('Vigente hasta ${q.expiresAt.toLocal()}'),
                          const SizedBox(height: 8),
                          Text(q.conditions),
                          StatusChip(q.status),
                          if (q.status == 'sent' &&
                              widget.request.status == 'open')
                            TaskButton(
                              'Aceptar cotización',
                              icon: Icons.handshake_outlined,
                              action:
                                  q.expiresAt.isBefore(DateTime.now())
                                      ? null
                                      : () async {
                                        if (!await confirm(
                                          context,
                                          'Confirmar acuerdo',
                                          '${money(q.totalCents)} por ${q.quantity} unidades.\nAdelanto simulado: ${money(q.depositCents)}\nSaldo simulado: ${money(q.totalCents - q.depositCents)}\nFecha: ${dateOnly(q.promisedDate)}\n${q.conditions}\n\nSolo se aceptará una propuesta y se compartirá la entrega con este negocio. Antes de producción se puede cancelar con devolución simulada íntegra; después requiere acuerdo y retención máxima del adelanto pagado.',
                                        )) {
                                          return;
                                        }
                                        final order = await app.repository!
                                            .accept(q.id, operation);
                                        app.changed();
                                        if (context.mounted) {
                                          await openPage(
                                            context,
                                            OrderDetailScreen(order.id),
                                          );
                                        }
                                      },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed:
                        offset == 0
                            ? null
                            : () => setState(() {
                              offset -= 30;
                              refresh++;
                            }),
                    child: const Text('Anterior'),
                  ),
                  Text('Página ${offset ~/ 30 + 1}'),
                  TextButton(
                    onPressed:
                        quotes.length < 30
                            ? null
                            : () => setState(() {
                              offset += 30;
                              refresh++;
                            }),
                    child: const Text('Siguiente'),
                  ),
                ],
              ),
            ],
          ),
    );
  }
}

class BusinessProfileScreen extends StatelessWidget {
  final Profile business;
  const BusinessProfileScreen(this.business, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conoce al negocio')),
    body: PageBody(
      children: [
        const Icon(Icons.storefront_outlined, size: 64),
        SectionTitle(business.name, subtitle: business.district),
        Text(
          business.description.isEmpty
              ? 'Este negocio todavía no agregó una descripción.'
              : business.description,
        ),
        const SectionTitle('Especialidades'),
        Wrap(
          spacing: 8,
          children: [
            for (final c in context.read<AppState>().categories.where(
              (c) => business.categories.contains(c.id),
            ))
              Chip(label: Text(c.name)),
          ],
        ),
        if (business.businessAddress.isNotEmpty) ...[
          const SectionTitle('Atención y recojo'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(business.businessAddress),
          ),
        ],
        if (business.businessHours.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(business.businessHours),
          ),
        if (business.website.isNotEmpty) ...[
          const SectionTitle('Catálogo o web'),
          SelectableText(business.website),
        ],
      ],
    ),
  );
}

class QuoteEditorScreen extends StatefulWidget {
  final RequestItem request;
  final Quote? existing;
  const QuoteEditorScreen(this.request, {super.key, this.existing});
  @override
  State<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _QuoteEditorScreenState extends State<QuoteEditorScreen> {
  final form = GlobalKey<FormState>();
  final total = TextEditingController(), conditions = TextEditingController();
  final deposit = TextEditingController(text: '0');
  late DateTime promised, expires;
  late String id, operation;
  bool restored = false, sending = false;
  String get cacheKey =>
      'quote-draft:${context.read<AppState>().owner}:${widget.request.id}';
  @override
  void initState() {
    super.initState();
    final q = widget.existing;
    id = q?.id ?? uuid.v4();
    operation = uuid.v4();
    promised = q?.promisedDate ?? widget.request.desiredDate;
    expires = q?.expiresAt ?? DateTime.now().add(const Duration(days: 2));
    if (q != null) {
      total.text =
          '${q.totalCents ~/ 100}.${(q.totalCents % 100).toString().padLeft(2, '0')}';
      conditions.text = q.conditions;
      deposit.text = (q.depositCents / 100).toStringAsFixed(2);
    }
    restore();
  }

  Future<void> restore() async {
    final app = context.read<AppState>();
    final raw = await app.local!.cached(cacheKey);
    if (raw != null && mounted) {
      final j = decodeJson(raw);
      setState(() {
        total.text = j['total'];
        conditions.text = j['conditions'];
        deposit.text = j['deposit'] ?? '0';
        promised = DateTime.parse(j['promised']);
        expires = DateTime.parse(j['expires']);
        id = j['id'];
        operation = j['operation'];
        restored = true;
      });
    }
  }

  Future<void> save() async {
    await context.read<AppState>().local!.cache(
      cacheKey,
      encodeJson({
        'total': total.text,
        'conditions': conditions.text,
        'deposit': deposit.text,
        'promised': promised.toIso8601String(),
        'expires': expires.toIso8601String(),
        'id': id,
        'operation': operation,
      }),
      const Duration(days: 30),
    );
  }

  Future<void> changedDraft() async {
    operation = uuid.v4();
    await save();
  }

  @override
  void dispose() {
    total.dispose();
    conditions.dispose();
    deposit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final canEdit =
        !sending &&
        widget.request.status == 'open' &&
        (widget.existing == null || widget.existing!.status == 'sent');
    return Scaffold(
      appBar: AppBar(title: const Text('Tu propuesta')),
      body: PageBody(
        children: [
          SectionTitle(
            widget.request.title,
            subtitle:
                '${widget.request.quantity} unidades · deseado para ${dateOnly(widget.request.desiredDate)}',
          ),
          if (restored)
            const Text('Se recuperó un borrador local. Aún no está enviado.'),
          Form(
            key: form,
            child: Column(
              children: [
                TextFormField(
                  controller: total,
                  enabled: canEdit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio TOTAL en soles',
                    prefixText: 'S/ ',
                    helperText:
                        'Incluye materiales, personalización y costos acordados.',
                  ),
                  validator: (v) {
                    try {
                      parseMoney(v ?? '');
                      return null;
                    } catch (e) {
                      return e.toString();
                    }
                  },
                  onChanged: (_) => changedDraft(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: deposit,
                  enabled: canEdit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Adelanto para iniciar',
                    prefixText: 'S/ ',
                    helperText:
                        'Entre 0 y 50% del total. Pago simulado, sin dinero real.',
                  ),
                  validator: (v) {
                    try {
                      final amount = parseMoney(v ?? '', allowZero: true);
                      return amount > parseMoney(total.text) ~/ 2
                          ? 'El adelanto máximo es el 50%'
                          : null;
                    } catch (_) {
                      return 'Ingresa 0 o un importe válido';
                    }
                  },
                  onChanged: (_) => changedDraft(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: conditions,
                  enabled: canEdit,
                  maxLines: 5,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: 'Condiciones del acuerdo',
                  ),
                  validator:
                      (v) =>
                          (v?.trim().length ?? 0) < 5
                              ? 'Describa las condiciones'
                              : null,
                  onChanged: (_) => changedDraft(),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed:
                !canEdit
                    ? null
                    : () async {
                      final today = DateTime.now();
                      if (widget.request.desiredDate.isBefore(
                        DateTime(today.year, today.month, today.day),
                      )) {
                        message(context, 'La fecha deseada ya venció.');
                        return;
                      }
                      final d = await showDatePicker(
                        context: context,
                        initialDate: promised,
                        firstDate: DateTime(today.year, today.month, today.day),
                        lastDate: widget.request.desiredDate,
                      );
                      if (d != null) {
                        setState(() => promised = d);
                        await changedDraft();
                      }
                    },
            icon: const Icon(Icons.event),
            label: Text('Elaboración: ${dateOnly(promised)}'),
          ),
          OutlinedButton.icon(
            onPressed:
                !canEdit
                    ? null
                    : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(
                          const Duration(days: 2),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (d != null) {
                        setState(
                          () =>
                              expires = DateTime(
                                d.year,
                                d.month,
                                d.day,
                                23,
                                59,
                              ),
                        );
                        await changedDraft();
                      }
                    },
            icon: const Icon(Icons.timer_outlined),
            label: Text('Vigencia: ${dateOnly(expires)}'),
          ),
          const SizedBox(height: 16),
          TaskButton(
            'Revisar y enviar cotización',
            icon: Icons.send_outlined,
            action:
                !canEdit
                    ? null
                    : () async {
                      if (!form.currentState!.validate()) return;
                      await save();
                      final cents = parseMoney(total.text);
                      if (!context.mounted) return;
                      if (!await confirm(
                        context,
                        'Enviar propuesta',
                        'Total: ${money(cents)}\nElaboración: ${dateOnly(promised)}\n${conditions.text}',
                      )) {
                        return;
                      }
                      final queuedOperation = operation;
                      setState(() => sending = true);
                      try {
                        await app.local!.enqueueQuote(
                          app.owner!,
                          {
                            'id': id,
                            'request_id': widget.request.id,
                            'total_cents': cents,
                            'deposit_cents': parseMoney(
                              deposit.text,
                              allowZero: true,
                            ),
                            'conditions': conditions.text.trim(),
                            'promised_date': dateOnly(promised),
                            'expires_at': expires.toUtc().toIso8601String(),
                          },
                          queuedOperation,
                          widget.existing?.version ?? 0,
                        );
                        await app.synchronize();
                      } finally {
                        if (mounted) setState(() => sending = false);
                      }
                      final pending = (await app.local!.pending(
                        app.owner!,
                      )).any((item) => item['id'] == queuedOperation);
                      app.changed();
                      if (context.mounted) {
                        message(
                          context,
                          pending
                              ? 'La cotización está pendiente de nube. Se reintentará con conexión; puede revisarla en Sincronización.'
                              : 'La nube confirmó el envío de la cotización.',
                        );
                        Navigator.pop(context);
                      }
                    },
          ),
          const Text(
            'Ante un error se conserva el borrador. La aceptación congela el importe y condiciones del acuerdo.',
          ),
        ],
      ),
    );
  }
}

class BusinessQuotesScreen extends StatefulWidget {
  const BusinessQuotesScreen({super.key});
  @override
  State<BusinessQuotesScreen> createState() => _BusinessQuotesScreenState();
}

class _BusinessQuotesScreenState extends State<BusinessQuotesScreen> {
  int offset = 0, refresh = 0;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PageBody(
      children: [
        const SectionTitle(
          'Tus propuestas',
          subtitle: 'Solo cotizaciones enviadas por este negocio.',
        ),
        DataView<List<Quote>>(
          revision: app.revision + refresh,
          load: () => app.repository!.quotes(offset: offset),
          builder:
              (items) => Column(
                children: [
                  if (items.isEmpty)
                    const EmptyState(
                      'Aún no has cotizado',
                      'Explora solicitudes de tus categorías y envía tu primera propuesta.',
                    ),
                  for (final q in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          title: Text(money(q.totalCents)),
                          subtitle: Text(
                            '${statusLabel(q.status)} · ${dateOnly(q.promisedDate)}\n${q.conditions}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap:
                              () => openPage(
                                context,
                                RequestDetailScreen(q.requestId),
                              ),
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed:
                            offset == 0
                                ? null
                                : () => setState(() {
                                  offset -= 30;
                                  refresh++;
                                }),
                        child: const Text('Anterior'),
                      ),
                      Text('Página ${offset ~/ 30 + 1}'),
                      TextButton(
                        onPressed:
                            items.length < 30
                                ? null
                                : () => setState(() {
                                  offset += 30;
                                  refresh++;
                                }),
                        child: const Text('Siguiente'),
                      ),
                    ],
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String? status;
  int offset = 0, refresh = 0;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PageBody(
      children: [
        SectionTitle(
          app.isBusiness ? 'Encargos que estás creando' : 'Tus pedidos',
          subtitle: 'Acuerdos confirmados y su avance real.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: status == null,
              onSelected:
                  (_) => setState(() {
                    status = null;
                    offset = 0;
                    refresh++;
                  }),
            ),
            for (final s in [
              'confirmed',
              'production',
              'ready',
              'delivered',
              'cancelled',
            ])
              ChoiceChip(
                label: Text(statusLabel(s)),
                selected: status == s,
                onSelected:
                    (_) => setState(() {
                      status = s;
                      offset = 0;
                      refresh++;
                    }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        DataView<List<OrderItem>>(
          revision: app.revision + refresh,
          load:
              () => app.repository!.orders(
                business: app.isBusiness,
                status: status,
                offset: offset,
              ),
          builder:
              (items) => Column(
                children: [
                  if (items.isEmpty)
                    const EmptyState(
                      'Sin pedidos en este estado',
                      'Un pedido aparece después de aceptar una cotización.',
                    ),
                  for (final order in items) OrderCard(order),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed:
                            offset == 0
                                ? null
                                : () => setState(() {
                                  offset -= 30;
                                  refresh++;
                                }),
                        child: const Text('Anterior'),
                      ),
                      Text('Página ${offset ~/ 30 + 1}'),
                      TextButton(
                        onPressed:
                            items.length < 30
                                ? null
                                : () => setState(() {
                                  offset += 30;
                                  refresh++;
                                }),
                        child: const Text('Siguiente'),
                      ),
                    ],
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

class OrderCard extends StatelessWidget {
  final OrderItem order;
  const OrderCard(this.order, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(order.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${order.businessName} · ${money(order.totalCents)}'),
            Text('Elaboración: ${dateOnly(order.promisedDate)}'),
            StatusChip(order.status),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openPage(context, OrderDetailScreen(order.id)),
      ),
    ),
  );
}

class OrderDetailScreen extends StatefulWidget {
  final String id;
  const OrderDetailScreen(this.id, {super.key});
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  int refresh = 0;
  final operations = <String, String>{};
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Seguimiento del pedido')),
      body: PageBody(
        children: [
          DataView<OrderItem>(
            revision: app.revision + refresh,
            load: () => app.repository!.order(widget.id),
            builder:
                (o) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatusChip(o.status),
                    SectionTitle(
                      o.title,
                      subtitle: '${o.businessName} · ${o.quantity} unidades',
                    ),
                    Text(
                      money(o.totalCents),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text('Fecha acordada: ${dateOnly(o.promisedDate)}'),
                    if (dateOnly(
                              o.promisedDate,
                            ).compareTo(dateOnly(DateTime.now())) <
                            0 &&
                        !['delivered', 'cancelled'].contains(o.status))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'La fecha comprometida ya pasó. Revisa el avance con la otra parte; puedes proponer una cancelación desde este pedido.',
                        ),
                      ),
                    const SectionTitle('Acuerdo confirmado'),
                    Text(o.conditions),
                    if (o.status != 'cancelled')
                      DataView<Json>(
                        revision: app.revision,
                        load:
                            () => app.repository!.api.rpcRecord(
                              'order_contact',
                              {'p_order': o.id},
                            ),
                        builder:
                            (contact) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.isBusiness
                                          ? 'Contacto del cliente'
                                          : 'Contacto del negocio',
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                    ),
                                    if ((contact['contact_name'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(contact['contact_name']),
                                    if ((contact['phone'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      SelectableText(contact['phone'])
                                    else
                                      const Text(
                                        'La otra parte aún no agregó teléfono.',
                                      ),
                                    const Text(
                                      'Visible solo entre participantes del acuerdo.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ),
                    OrderCommercePanel(o, key: ValueKey(o.id)),
                    const SectionTitle(
                      'Historial del pedido',
                      subtitle:
                          'Eventos registrados por el servidor, no porcentajes estimados.',
                    ),
                    DataView<List<Json>>(
                      revision: app.revision + refresh,
                      load: () => app.repository!.history(o.id),
                      builder:
                          (events) => Column(
                            children: [
                              for (final e in events)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    e['new_status'] == o.status
                                        ? Icons.radio_button_checked
                                        : Icons.check_circle_outline,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  title: Text(statusLabel(e['new_status'])),
                                  subtitle: Text(
                                    '${DateTime.parse(e['created_at']).toLocal()}\n${e['actor_id'] == o.clientId ? 'Cliente' : 'Negocio'}',
                                  ),
                                ),
                            ],
                          ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          () => openPage(
                            context,
                            RequestDetailScreen(o.requestId),
                          ),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Ver solicitud, fotos y entrega'),
                    ),
                    if (o.nextStatus(app.isBusiness) != null) ...[
                      const SizedBox(height: 12),
                      if (o.advanceBlockReason(app.isBusiness) != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(o.advanceBlockReason(app.isBusiness)!),
                        ),
                      TaskButton(
                        app.isBusiness
                            ? 'Marcar ${statusLabel(o.nextStatus(true)!)}'
                            : 'Confirmar recepción y entrega',
                        action:
                            o.advanceBlockReason(app.isBusiness) != null
                                ? null
                                : () async {
                                  final next = o.nextStatus(app.isBusiness)!;
                                  if (!await confirm(
                                    context,
                                    'Actualizar pedido',
                                    'El estado cambiará a ${statusLabel(next)}. La otra parte recibirá un evento. No se permite retroceder ni saltar estados.',
                                  )) {
                                    return;
                                  }
                                  await app.repository!.transition(
                                    o,
                                    next,
                                    operations.putIfAbsent(
                                      next,
                                      () => uuid.v4(),
                                    ),
                                  );
                                  operations.remove(next);
                                  if (mounted) setState(() => refresh++);
                                  app.changed();
                                },
                      ),
                    ],
                  ],
                ),
          ),
        ],
      ),
    );
  }
}
