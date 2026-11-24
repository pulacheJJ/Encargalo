import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/config.dart';
import '../../../core/domain/models.dart';
import '../../../app/app_state.dart';
import '../../../core/widgets/common.dart';
import '../../marketplace/presentation/market_screens.dart';
import '../../locations/presentation/location_selector.dart';
import '../../locations/domain/location_entry.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController name, district, description, phone;
  late TextEditingController contactName,
      address,
      businessAddress,
      hours,
      website;
  LocationEntry? location;
  bool contactLoaded = false;
  int locationRevision = 0;
  late Set<String> categories;
  final form = GlobalKey<FormState>();
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final app = context.read<AppState>();
    final p = app.profile!;
    name = TextEditingController(text: p.name);
    district = TextEditingController(text: p.district);
    description = TextEditingController(text: p.description);
    phone = TextEditingController();
    contactName = TextEditingController(text: p.name);
    address = TextEditingController();
    businessAddress = TextEditingController(text: p.businessAddress);
    hours = TextEditingController(text: p.businessHours);
    website = TextEditingController(text: p.website);
    categories = p.categories.toSet();
    loadPhone();
  }

  Future<void> loadPhone() async {
    try {
      final app = context.read<AppState>();
      final contact = await app.profiles!.privateContact(app.owner!);
      if (mounted) {
        setState(() {
          phone.text = contact['phone'] ?? '';
          contactName.text = contact['contact_name'] ?? app.profile!.name;
          address.text = contact['address_reference'] ?? '';
          contactLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) message(context, 'No se pudo cargar el contacto: $e');
    }
  }

  @override
  void dispose() {
    for (final c in [
      name,
      district,
      description,
      phone,
      contactName,
      address,
      businessAddress,
      hours,
      website,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.profile!;
    return PageBody(
      maxWidth: 760,
      children: [
        SectionTitle(
          p.isBusiness ? 'Tu negocio en Encárgalo' : 'Tu perfil',
          subtitle:
              '${p.isBusiness ? 'Negocio' : 'Cliente'} · ${app.repository!.cloud.auth.currentUser?.email ?? ''}',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    p.isBusiness
                        ? Icons.storefront_outlined
                        : Icons.person_outline,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        p.isBusiness
                            ? 'Negocio · ${p.district}'
                            : 'Cliente · ${p.district}',
                      ),
                      const SizedBox(height: 4),
                      const Text('Cuenta protegida con acceso personal'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle(
          'Datos para tus encargos',
          subtitle:
              'La región y distrito se validan con el catálogo territorial. El teléfono y la referencia personal no se muestran en el feed.',
        ),
        if (!contactLoaded) ...[
          const LinearProgressIndicator(),
          TextButton(
            onPressed: loadPhone,
            child: const Text('Reintentar carga de datos privados'),
          ),
        ],
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: name,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: p.isBusiness ? 'Nombre comercial' : 'Nombre',
                ),
                validator:
                    (v) =>
                        (v?.trim().length ?? 0) < 2
                            ? 'Ingrese al menos dos caracteres'
                            : null,
              ),
              const SizedBox(height: 12),
              LocationSelector(
                key: ValueKey(locationRevision),
                initialCode: p.locationCode,
                initialDistrict: p.district,
                onChanged: (value) {
                  location = value;
                  district.text = value.district;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: contactName,
                enabled: contactLoaded,
                decoration: InputDecoration(
                  labelText:
                      p.isBusiness
                          ? 'Persona responsable'
                          : 'Nombre de contacto',
                ),
                validator:
                    (v) =>
                        (v?.trim().length ?? 0) < 2
                            ? 'Indica la persona de contacto'
                            : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: address,
                enabled: contactLoaded,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Referencia personal o de entrega (privada)',
                  helperText: 'Cada solicitud puede usar un punto distinto.',
                ),
              ),
              if (p.isBusiness) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: description,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Descripción pública del negocio',
                  ),
                ),
                const SectionTitle(
                  'Categorías que atiendes',
                  subtitle:
                      'El feed utiliza estas categorías para mostrar oportunidades.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in app.categories)
                      FilterChip(
                        label: Text(c.name),
                        selected: categories.contains(c.id),
                        onSelected:
                            (selected) => setState(() {
                              if (selected) {
                                categories.add(c.id);
                              } else {
                                categories.remove(c.id);
                              }
                            }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: businessAddress,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Dirección de atención o recojo (pública)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: hours,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Horario de atención',
                    hintText: 'Lunes a sábado, 9:00 a 18:00',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: website,
                  keyboardType: TextInputType.url,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Web o catálogo público (opcional)',
                    hintText: 'https://...',
                  ),
                  validator:
                      (v) =>
                          (v ?? '').trim().isEmpty ||
                                  Uri.tryParse(v!.trim())?.scheme == 'https'
                              ? null
                              : 'Usa un enlace HTTPS válido',
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                enabled: contactLoaded,
                maxLength: 30,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono de contacto privado',
                  helperText: 'No se incluye en el perfil público.',
                ),
                validator:
                    (v) =>
                        RegExp(r'^\+?[0-9 ()-]{7,20}$').hasMatch(v ?? '')
                            ? null
                            : 'Ingresa un teléfono válido',
              ),
              const SizedBox(height: 12),
              TaskButton(
                'Guardar perfil',
                action:
                    !contactLoaded
                        ? null
                        : () async {
                          if (!form.currentState!.validate()) return;
                          if (p.isBusiness && categories.isEmpty) {
                            throw const FormatException(
                              'Seleccione al menos una categoría.',
                            );
                          }
                          if (location == null) {
                            throw const FormatException(
                              'Selecciona la ubicación.',
                            );
                          }
                          await app.profiles!.save({
                            'name': name.text.trim(),
                            'location_code': location!.code,
                            'description': description.text.trim(),
                            'categories': categories.toList(),
                            'phone': phone.text.trim(),
                            'contact_name': contactName.text.trim(),
                            'address_reference': address.text.trim(),
                            'business_address': businessAddress.text.trim(),
                            'business_hours': hours.text.trim(),
                            'website': website.text.trim(),
                          });
                          await app.refreshProfile();
                          if (context.mounted) {
                            message(
                              context,
                              'La nube confirmó los cambios del perfil.',
                            );
                          }
                        },
              ),
              TextButton(
                onPressed:
                    () => setState(() {
                      name.text = p.name;
                      district.text = p.district;
                      description.text = p.description;
                      categories = p.categories.toSet();
                      businessAddress.text = p.businessAddress;
                      hours.text = p.businessHours;
                      website.text = p.website;
                      locationRevision++;
                      location = null;
                      loadPhone();
                    }),
                child: const Text('Cancelar cambios'),
              ),
            ],
          ),
        ),
        const SectionTitle('A tu manera'),
        DropdownButtonFormField<ThemeMode>(
          value: app.themeMode,
          decoration: const InputDecoration(labelText: 'Apariencia'),
          items: const [
            DropdownMenuItem(
              value: ThemeMode.system,
              child: Text('Según el dispositivo'),
            ),
            DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('Oscuro')),
          ],
          onChanged: (mode) {
            if (mode != null) app.setTheme(mode);
          },
        ),
        const SizedBox(height: 12),
        TaskButton(
          'Activar o comprobar notificaciones',
          icon: Icons.notifications_outlined,
          action:
              !AppConfig.pushConfigured
                  ? null
                  : () async {
                    final enabled = await app.push!.enable();
                    if (context.mounted) {
                      message(
                        context,
                        enabled
                            ? 'Permiso concedido y dispositivo registrado.'
                            : 'El permiso no está concedido; los eventos siguen en la bandeja.',
                      );
                    }
                  },
        ),
        if (!AppConfig.pushConfigured)
          const Text(
            'El proyecto gratuito de mensajería todavía no está configurado en esta compilación.',
          ),
        TextButton(
          onPressed: () async {
            await app.prefs!.setBool('push_enabled', false);
            try {
              await app.push?.detach();
            } finally {
              if (context.mounted) {
                message(context, 'Avisos desactivados en este dispositivo.');
              }
            }
          },
          child: const Text('Desactivar avisos en este dispositivo'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sync_outlined),
          title: const Text('Estado de sincronización'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openPage(context, const SyncScreen()),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: const Text('Licencias y fuentes del catálogo'),
          onTap:
              () => showLicensePage(
                context: context,
                applicationName: 'Encargalo',
                applicationVersion: '1.1.0',
              ),
        ),
        TaskButton(
          'Cerrar sesión',
          icon: Icons.logout,
          action: () async {
            final pending = await app.local!.pending(app.owner!);
            if (!context.mounted) return;
            if (!await confirm(
              context,
              'Cerrar sesión',
              pending.isNotEmpty
                  ? 'Hay ${pending.length} operaciones pendientes. Permanecerán en este teléfono, ligadas a esta cuenta; se detendrán sus trabajos y podrán continuarse al volver a iniciar sesión.'
                  : 'Se detendrán las suscripciones y avisos de esta cuenta.',
            )) {
              return;
            }
            await app.signOut();
          },
        ),
      ],
    );
  }
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  int refresh = 0;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: PageBody(
        children: [
          const SectionTitle(
            'Lo que falta por enviar',
            subtitle:
                'Una operación pendiente no equivale a una solicitud publicada. Los errores no eliminan su borrador.',
          ),
          Text(
            'Última confirmación: ${app.prefs!.getString('last_sync_${app.owner}') ?? 'Aún no hay confirmaciones'}',
          ),
          const SizedBox(height: 16),
          TaskButton(
            'Intentar sincronizar',
            icon: Icons.sync,
            action: () async {
              for (final o in await app.local!.pending(app.owner!)) {
                await app.local!.retry(app.owner!, o['id']);
              }
              await app.synchronize();
              setState(() => refresh++);
            },
          ),
          DataView<List<Json>>(
            revision: app.revision + refresh,
            load: () => app.local!.pending(app.owner!),
            builder:
                (items) => Column(
                  children: [
                    if (items.isEmpty)
                      const EmptyState(
                        'No hay envíos pendientes',
                        'Los borradores que no se han publicado siguen en Mis solicitudes.',
                        icon: Icons.cloud_done_outlined,
                      ),
                    for (final o in items)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  o['action'] == 'delete'
                                      ? 'Cancelación pendiente'
                                      : o['action'] == 'quote'
                                      ? 'Cotización pendiente'
                                      : 'Publicación pendiente',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                Text('Intentos: ${o['attempts']}'),
                                if (o['error'] != null) Text(o['error']),
                                Text(
                                  'Próximo intento permitido: ${DateTime.fromMillisecondsSinceEpoch(o['next_run']).toLocal()}',
                                ),
                                TaskButton(
                                  'Reintentar esta operación',
                                  icon: Icons.refresh,
                                  action: () async {
                                    await app.local!.retry(app.owner!, o['id']);
                                    await app.synchronize();
                                    setState(() => refresh++);
                                  },
                                ),
                                TextButton(
                                  onPressed: () async {
                                    if (!await confirm(
                                      context,
                                      'Detener reintentos y revisar',
                                      'La solicitud puede haber llegado al servidor aunque se perdiera la respuesta. Se conservará el borrador y deberá comprobarse la nube antes de reenviar. No se deshace una publicación confirmada.',
                                    )) {
                                      return;
                                    }
                                    try {
                                      await app.local!.abandon(
                                        app.owner!,
                                        o['id'],
                                      );
                                      setState(() => refresh++);
                                    } catch (e) {
                                      if (context.mounted) {
                                        message(context, e.toString());
                                      }
                                    }
                                  },
                                  child: const Text(
                                    'Detener reintentos y conservar borrador',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Android decide cuándo ejecutar el trabajo diferido según red, batería y restricciones. El cierre forzado puede impedirlo hasta abrir la app. Al volver a primer plano también se revisa la cola.',
          ),
        ],
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int offset = 0, refresh = 0;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: PageBody(
        children: [
          const SectionTitle(
            'Novedades de tus encargos',
            subtitle:
                'Esta bandeja conserva los eventos del servidor, incluso si no se recibió el push.',
          ),
          DataView<List<Notice>>(
            revision: app.revision + refresh,
            load: () => app.repository!.notifications(offset: offset),
            builder:
                (items) => Column(
                  children: [
                    if (items.isEmpty)
                      const EmptyState(
                        'Todo tranquilo por aquí',
                        'Los nuevos acuerdos y cambios de estado aparecerán en esta bandeja.',
                        icon: Icons.notifications_none,
                      ),
                    for (final n in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            leading: Icon(
                              n.read
                                  ? Icons.notifications_none
                                  : Icons.notifications_active_outlined,
                            ),
                            title: Text(
                              n.title,
                              style: TextStyle(
                                fontWeight:
                                    n.read
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${n.body}\n${n.createdAt.toLocal()}',
                            ),
                            isThreeLine: true,
                            onTap: () async {
                              try {
                                await app.repository!.api.rpc(
                                  'mark_notification_read',
                                  {'p_id': n.id},
                                );
                                setState(() => refresh++);
                                if (!context.mounted) return;
                                if (n.orderId != null) {
                                  await openPage(
                                    context,
                                    OrderDetailScreen(n.orderId!),
                                  );
                                } else if (n.requestId != null) {
                                  await openPage(
                                    context,
                                    RequestDetailScreen(n.requestId!),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  message(context, e.toString());
                                }
                              }
                            },
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
      ),
    );
  }
}
