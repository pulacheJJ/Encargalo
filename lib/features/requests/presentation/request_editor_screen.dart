import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/domain/models.dart';
import '../../../core/device/hardware_services.dart';
import '../../../app/app_state.dart';
import 'request_editor.dart';
import '../../../core/widgets/common.dart';
import '../../locations/presentation/location_selector.dart';

class LocationScreen extends StatelessWidget {
  final Delivery point;
  final bool review;
  const LocationScreen(this.point, {super.key, this.review = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(review ? 'Revisar punto de entrega' : 'Punto de entrega'),
    ),
    body: PageBody(
      children: [
        const EmptyState(
          'Una ubicación, no una dirección exacta',
          'La precisión indica incertidumbre. La referencia escrita complementa el punto.',
          icon: Icons.location_on_outlined,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Latitud: ${point.latitude?.toStringAsFixed(6)}'),
                Text('Longitud: ${point.longitude?.toStringAsFixed(6)}'),
                Text('Precisión: ±${point.accuracy?.toStringAsFixed(0)} m'),
                Text(
                  point.approximate
                      ? 'Permiso de ubicación aproximada'
                      : 'Lectura del servicio de ubicación',
                ),
                Text('Lectura: ${point.capturedAt?.toLocal()}'),
                Text(
                  'Referencia: ${point.reference.isEmpty ? 'Sin referencia' : point.reference}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            if (!await confirm(
              context,
              'Abrir un mapa externo',
              'Se compartirán estas coordenadas con la aplicación de mapas elegida o con OpenStreetMap. ¿Continuar?',
            )) {
              return;
            }
            final geo = Uri.parse(
              'geo:${point.latitude},${point.longitude}?q=${point.latitude},${point.longitude}',
            );
            if (!await launchUrl(geo, mode: LaunchMode.externalApplication)) {
              final url = Uri.parse(
                'https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=17/${point.latitude}/${point.longitude}',
              );
              if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
                  context.mounted) {
                message(context, 'No hay aplicación para abrir el mapa.');
              }
            }
          },
          icon: const Icon(Icons.map_outlined),
          label: const Text('Verificar en aplicación de mapas'),
        ),
        const Text(
          'Cartografía web alternativa: © OpenStreetMap contributors.',
          textAlign: TextAlign.center,
        ),
        if (review) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Confirmar este punto'),
          ),
        ],
      ],
    ),
  );
}

class RequestEditorScreen extends StatefulWidget {
  final RequestDraft draft;
  const RequestEditorScreen(this.draft, {super.key});
  @override
  State<RequestEditorScreen> createState() => _RequestEditorScreenState();
}

class _RequestEditorScreenState extends State<RequestEditorScreen>
    with WidgetsBindingObserver {
  late RequestEditor vm;
  late TextEditingController title, detail, quantity, district, reference;
  int step = 0;
  final Set<int> attemptedSteps = {};
  bool get invalidProduct =>
      title.text.trim().length < 3 ||
      detail.text.trim().length < 10 ||
      vm.draft.categoryId.isEmpty;
  bool get invalidQuantity =>
      (int.tryParse(quantity.text) ?? 0) < 1 ||
      (int.tryParse(quantity.text) ?? 0) > 100000;
  bool leaving = false;
  Future<void> saveTail = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vm = RequestEditor(widget.draft, context.read<AppState>().local!);
    title = TextEditingController(text: vm.draft.title);
    detail = TextEditingController(text: vm.draft.detail);
    quantity = TextEditingController(text: '${vm.draft.quantity}');
    district = TextEditingController(text: vm.draft.district);
    reference = TextEditingController(text: vm.draft.delivery.reference);
    persist();
  }

  void persist() {
    vm.draft.title = title.text;
    vm.draft.detail = detail.text;
    vm.draft.quantity = int.tryParse(quantity.text) ?? 0;
    vm.draft.district = district.text;
    vm.draft.delivery.reference = reference.text;
    saveTail = saveTail.then((_) => vm.save()).catchError((Object e) {
      if (mounted) message(context, 'No se pudo guardar el borrador: $e');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      persist();
    }
    if (state == AppLifecycleState.resumed) {
      Geolocator.isLocationServiceEnabled().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [title, detail, quantity, district, reference]) {
      c.dispose();
    }
    vm.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    persist();
    await saveTail;
    if (mounted) {
      setState(() => leaving = true);
      Navigator.pop(context);
    }
  }

  Future<void> geocode() async {
    if (!await confirm(
      context,
      'Buscar una referencia',
      'Se enviará el distrito escrito a Nominatim (OpenStreetMap), a través del servidor de Encárgalo. No se enviará su punto GPS ni se sustituirá su distrito automáticamente.',
    )) {
      return;
    }
    if (!mounted) return;
    final app = context.read<AppState>();
    final query = '${district.text.trim()}, Piura, Perú';
    final key = 'geocode:$query';
    final cached = await app.local!.cached(key);
    final result =
        cached == null
            ? await app.repository!.api.send(
              'GET',
              'functions/v1/geocode',
              query: {'q': query},
            )
            : jsonDecode(cached);
    if (cached == null) {
      await app.local!.cache(key, jsonEncode(result), const Duration(days: 7));
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Referencias encontradas'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final place in result as List)
                      ListTile(
                        title: Text(place['display_name']),
                        subtitle: Text('${place['lat']}, ${place['lon']}'),
                        onTap: () {
                          reference.text = place['display_name'];
                          persist();
                          Navigator.pop(c);
                        },
                      ),
                    if (result.isEmpty)
                      const Text(
                        'Sin resultados. Se puede escribir una referencia manual.',
                      ),
                    const Text('© OpenStreetMap contributors · Nominatim'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListenableBuilder(
      listenable: vm,
      builder:
          (c, _) => PopScope(
            canPop: leaving,
            onPopInvokedWithResult: (didPop, result) async {
              if (!didPop && !vm.busy) await finish();
            },
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Tu solicitud'),
                leading: IconButton(
                  tooltip: 'Guardar y volver',
                  onPressed: vm.busy ? null : finish,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              body: PageBody(
                children: [
                  Text(
                    'PASO ${step + 1} DE 4',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: (step + 1) / 4),
                  SectionTitle(
                    [
                      'Dale forma a tu idea',
                      'Cantidad, lugar y fecha',
                      'Fotos y punto de entrega',
                      'Revisa antes de publicar',
                    ][step],
                    subtitle:
                        [
                          'Cuenta qué necesitas a los negocios de Piura.',
                          'Un encargo claro facilita una buena cotización.',
                          'Hasta tres referencias. La ubicación es opcional.',
                          'El borrador es local. Solo estará publicada cuando la nube lo confirme.',
                        ][step],
                  ),
                  if (step == 0) ...[
                    TextField(
                      controller: title,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: 'Título del producto',
                        errorText:
                            attemptedSteps.contains(0) &&
                                    title.text.trim().length < 3
                                ? 'Ingrese al menos tres caracteres'
                                : null,
                        hintText: 'Polos para una actividad',
                      ),
                      onChanged: (_) => persist(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detail,
                      maxLines: 5,
                      maxLength: 5000,
                      decoration: InputDecoration(
                        labelText: 'Especificaciones',
                        errorText:
                            attemptedSteps.contains(0) &&
                                    detail.text.trim().length < 10
                                ? 'Describa el producto con al menos diez caracteres'
                                : null,
                        hintText:
                            'Tallas, colores, material, medidas y acabado…',
                      ),
                      onChanged: (_) => persist(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          app.categories.any((c) => c.id == vm.draft.categoryId)
                              ? vm.draft.categoryId
                              : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        errorText:
                            attemptedSteps.contains(0) &&
                                    vm.draft.categoryId.isEmpty
                                ? 'Seleccione una categoría'
                                : null,
                      ),
                      items:
                          app.categories
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            vm.draft.categoryId = v;
                            persist();
                          });
                        }
                      },
                    ),
                    const SectionTitle(
                      'Detalles para una cotización precisa',
                      subtitle:
                          'Completa lo que aplique a tu producto. Evita compartir datos personales en estas especificaciones.',
                    ),
                    for (final field
                        in const <String, String>{
                          'material': 'Material o tipo de producto',
                          'color': 'Colores y cantidades por color',
                          'dimensions': 'Tallas, medidas o dimensiones',
                          'design': 'Diseño y zona de personalización',
                          'finish': 'Técnica, acabado y empaque',
                        }.entries) ...[
                      TextFormField(
                        key: ValueKey(field.key),
                        initialValue: vm.draft.specifications[field.key] ?? '',
                        maxLength: 500,
                        decoration: InputDecoration(labelText: field.value),
                        onChanged: (value) {
                          vm.draft.specifications[field.key] = value;
                          persist();
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (step == 1) ...[
                    TextField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Cantidad de unidades',
                        errorText:
                            attemptedSteps.contains(1) && invalidQuantity
                                ? 'Ingrese una cantidad entre 1 y 100000'
                                : null,
                      ),
                      onChanged: (_) => persist(),
                    ),
                    const SizedBox(height: 12),
                    LocationSelector(
                      initialCode: vm.draft.locationCode,
                      initialDistrict: district.text,
                      allowedRegion: 'Piura',
                      onChanged: (location) {
                        vm.draft.locationCode = location.code;
                        district.text = location.district;
                        persist();
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          vm.draft.specifications['delivery_mode'] ??
                          'coordinar',
                      decoration: const InputDecoration(
                        labelText: 'Forma de entrega',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'coordinar',
                          child: Text('Coordinar al confirmar el acuerdo'),
                        ),
                        DropdownMenuItem(
                          value: 'recojo',
                          child: Text('Recojo en el negocio'),
                        ),
                        DropdownMenuItem(
                          value: 'entrega',
                          child: Text('Entrega en el punto acordado'),
                        ),
                      ],
                      onChanged: (value) {
                        vm.draft.specifications['delivery_mode'] =
                            value ?? 'coordinar';
                        persist();
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              vm.draft.desiredDate.isBefore(DateTime.now())
                                  ? DateTime.now()
                                  : vm.draft.desiredDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 730),
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            vm.draft.desiredDate = picked;
                            persist();
                          });
                        }
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        'Fecha deseada: ${dateOnly(vm.draft.desiredDate)}',
                      ),
                    ),
                  ],
                  if (step == 2) ...[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final photo in vm.draft.photos)
                          SizedBox(
                            width: 140,
                            child: Column(
                              children: [
                                PhotoView(photo, height: 120),
                                TextButton.icon(
                                  onPressed:
                                      vm.busy
                                          ? null
                                          : () => vm.removePhoto(photo),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Quitar'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (vm.draft.photos.isEmpty)
                      const EmptyState(
                        'Una imagen ayuda a explicar',
                        'Toma una foto del diseño o elige una referencia de tu galería.',
                        icon: Icons.add_photo_alternate_outlined,
                      ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              vm.busy || vm.draft.photos.length >= 3
                                  ? null
                                  : () async {
                                    persist();
                                    await saveTail;
                                    await vm.addPhoto(ImageSource.camera);
                                  },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Tomar foto'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              vm.busy || vm.draft.photos.length >= 3
                                  ? null
                                  : () async {
                                    persist();
                                    await saveTail;
                                    await vm.addPhoto(ImageSource.gallery);
                                  },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Elegir imagen'),
                        ),
                      ],
                    ),
                    Text(
                      '${vm.draft.photos.length}/3 imágenes · hasta 2 MB por imagen preparada',
                    ),
                    if (vm.error != null) ...[
                      Text(
                        vm.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: Geolocator.openAppSettings,
                        child: const Text('Revisar permisos en Ajustes'),
                      ),
                    ],
                    const SectionTitle(
                      'Entrega',
                      subtitle:
                          'La dirección precisa solo se comparte con el negocio elegido al confirmar el pedido.',
                    ),
                    TextField(
                      controller: reference,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Dirección o referencia manual',
                      ),
                      onChanged: (_) => persist(),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          vm.busy
                              ? null
                              : () async {
                                persist();
                                await saveTail;
                                try {
                                  final point = await vm.locate();
                                  if (point == null || !context.mounted) return;
                                  final accepted = await openPage<bool>(
                                    context,
                                    LocationScreen(point, review: true),
                                  );
                                  if (accepted == true) {
                                    await vm.confirmLocation(point);
                                  }
                                } on LocationProblem catch (e) {
                                  if (!context.mounted) return;
                                  message(context, e.message);
                                  if (e.settings &&
                                      await confirm(
                                        context,
                                        'Revisar Ajustes',
                                        'Se abrirán los ajustes. El borrador está guardado y se puede continuar con referencia manual.',
                                      )) {
                                    if (e.service) {
                                      await Geolocator.openLocationSettings();
                                    } else {
                                      await Geolocator.openAppSettings();
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    message(
                                      context,
                                      'No se pudo obtener la ubicación: $e',
                                    );
                                  }
                                }
                              },
                      icon: const Icon(Icons.my_location),
                      label: Text(
                        vm.busy ? 'Obteniendo…' : 'Usar mi ubicación',
                      ),
                    ),
                    if (vm.draft.delivery.hasPoint) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Punto confirmado · ±${vm.draft.delivery.accuracy?.round()} m',
                        ),
                        subtitle: Text(
                          '${vm.draft.delivery.latitude?.toStringAsFixed(5)}, ${vm.draft.delivery.longitude?.toStringAsFixed(5)}',
                        ),
                        onTap:
                            () => openPage(
                              context,
                              LocationScreen(vm.draft.delivery),
                            ),
                      ),
                      TextButton(
                        onPressed:
                            () => setState(() {
                              vm.draft.delivery = Delivery(
                                reference: reference.text,
                              );
                              persist();
                            }),
                        child: const Text(
                          'Quitar punto y usar solo referencia',
                        ),
                      ),
                    ],
                    TaskButton(
                      'Buscar referencia del distrito',
                      icon: Icons.search,
                      action: geocode,
                    ),
                  ],
                  if (step == 3) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.text,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(detail.text),
                            const Divider(),
                            Text(
                              '${quantity.text} unidades · ${district.text}',
                            ),
                            Text(
                              'Fecha deseada: ${dateOnly(vm.draft.desiredDate)}',
                            ),
                            Text(
                              '${vm.draft.photos.length} fotos de referencia',
                            ),
                            Text(reference.text),
                            if (vm.draft.delivery.hasPoint)
                              Text(
                                'Punto de entrega confirmado · ±${vm.draft.delivery.accuracy?.round()} m',
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TaskButton(
                      'Publicar solicitud',
                      icon: Icons.cloud_upload_outlined,
                      action: () async {
                        persist();
                        await saveTail;
                        final error = vm.draft.validate();
                        if (error != null) throw FormatException(error);
                        if (!context.mounted) return;
                        if (!await confirm(
                          context,
                          'Publicar solicitud',
                          'Los negocios de la categoría podrán consultar las especificaciones y fotos, pero no el punto de entrega.',
                        )) {
                          return;
                        }
                        setState(() => vm.busy = true);
                        try {
                          await app.local!.enqueue(vm.draft);
                          await app.synchronize();
                        } finally {
                          if (mounted) setState(() => vm.busy = false);
                        }
                        if (!context.mounted) return;
                        final d = await app.local!.draft(
                          vm.draft.id,
                          vm.draft.ownerId,
                        );
                        if (!context.mounted) return;
                        message(
                          context,
                          d?.syncState == 'synced'
                              ? 'La nube confirmó la publicación.'
                              : 'La solicitud está pendiente de nube. Puede revisar y reintentar en Sincronización.',
                        );
                        setState(() => leaving = true);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                  if (vm.busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      if (step > 0)
                        OutlinedButton(
                          onPressed:
                              vm.busy ? null : () => setState(() => step--),
                          child: const Text('Anterior'),
                        ),
                      if (step < 3)
                        FilledButton.icon(
                          onPressed:
                              vm.busy
                                  ? null
                                  : () {
                                    persist();
                                    if ((step == 0 && invalidProduct) ||
                                        (step == 1 &&
                                            (invalidQuantity ||
                                                district.text.trim().length <
                                                    2))) {
                                      setState(() => attemptedSteps.add(step));
                                      return;
                                    }
                                    setState(() => step++);
                                  },
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Continuar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: vm.busy ? null : finish,
                    child: const Text('Guardar borrador y salir'),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Descartar este borrador local'),
                    onPressed:
                        vm.busy
                            ? null
                            : () async {
                              if (!await confirm(
                                context,
                                'Descartar borrador',
                                'Se quitará únicamente esta copia local. Una solicitud ya publicada no se cancela con esta acción.',
                              )) {
                                return;
                              }
                              persist();
                              await saveTail;
                              await app.local!.removeDraft(
                                vm.draft.id,
                                vm.draft.ownerId,
                              );
                              if (!context.mounted) return;
                              setState(() => leaving = true);
                              Navigator.pop(context);
                            },
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
