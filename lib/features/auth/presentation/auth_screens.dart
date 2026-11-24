import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/app_state.dart';
import '../../../core/widgets/common.dart';
import '../../locations/domain/location_entry.dart';
import '../../locations/presentation/location_selector.dart';

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Encárgalo')),
    body: const PageBody(
      children: [
        EmptyState(
          'Conexión cloud pendiente',
          'Esta compilación todavía no tiene un proyecto Supabase Free configurado. No se habilita una sesión ficticia.',
          icon: Icons.cloud_off_outlined,
        ),
        SectionTitle(
          'Presupuesto S/ 0',
          subtitle:
              'El backend utiliza Supabase Free y el push utiliza Firebase Spark. No se requiere tarjeta ni facturación.',
        ),
        Text(
          'La configuración pública se incorpora al compilar mediante config/public.json. Los pasos y accesos pendientes están documentados en docs/DESPLIEGUE_GRATUITO.md.',
        ),
      ],
    ),
  );
}

class AuthScreen extends StatefulWidget {
  final bool initialRegister;
  final LocationCatalog? locationCatalog;
  const AuthScreen({
    super.key,
    this.initialRegister = false,
    this.locationCatalog,
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      district = TextEditingController(text: 'Piura');
  bool register = false, hidden = true;
  String role = 'cliente';
  final phone = TextEditingController(),
      contact = TextEditingController(),
      confirmation = TextEditingController();
  LocationEntry? location;
  bool agreed = false;
  @override
  void initState() {
    super.initState();
    register = widget.initialRegister;
  }

  @override
  void dispose() {
    for (final c in [
      email,
      password,
      name,
      district,
      phone,
      contact,
      confirmation,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: PageBody(
        maxWidth: 520,
        children: [
          const SizedBox(height: 36),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Encárgalo',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tus ideas, en manos de negocios de Piura.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SectionTitle(
            register
                ? 'Una cuenta para crear oportunidades'
                : 'Qué gusto tenerte de vuelta',
            subtitle:
                register
                    ? 'Elige cómo quieres participar.'
                    : 'Solicita, compara y sigue tus productos personalizados.',
          ),
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (register) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'cliente',
                        icon: Icon(Icons.person_outline),
                        label: Text('Cliente'),
                      ),
                      ButtonSegment(
                        value: 'negocio',
                        icon: Icon(Icons.storefront_outlined),
                        label: Text('Negocio'),
                      ),
                    ],
                    selected: {role},
                    onSelectionChanged: (s) => setState(() => role = s.single),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      role == 'cliente'
                          ? 'Publica lo que necesitas y compara propuestas.'
                          : 'Encuentra encargos de tus categorías y envía cotizaciones.',
                    ),
                  ),
                  TextFormField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText:
                          role == 'negocio'
                              ? 'Nombre comercial'
                              : 'Nombres y apellidos',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator:
                        (v) =>
                            (v?.trim().length ?? 0) < 2
                                ? 'Ingrese al menos dos caracteres'
                                : null,
                  ),
                  const SizedBox(height: 12),
                  if (role == 'negocio') ...[
                    TextFormField(
                      controller: contact,
                      decoration: const InputDecoration(
                        labelText: 'Persona responsable del negocio',
                      ),
                      validator:
                          (v) =>
                              (v?.trim().length ?? 0) < 2
                                  ? 'Indica la persona de contacto'
                                  : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono de contacto privado',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator:
                        (v) =>
                            RegExp(r'^\+?[0-9 ()-]{7,20}$').hasMatch(v ?? '')
                                ? null
                                : 'Ingresa un teléfono válido',
                  ),
                  const SizedBox(height: 12),
                  LocationSelector(
                    catalog: widget.locationCatalog,
                    initialDistrict: district.text,
                    onChanged: (value) {
                      location = value;
                      district.text = value.district;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator:
                      (v) =>
                          RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(v ?? '')
                              ? null
                              : 'Ingrese un correo válido',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: password,
                  obscureText: hidden,
                  autofillHints: [
                    register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip:
                          hidden ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      onPressed: () => setState(() => hidden = !hidden),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator:
                      (v) =>
                          (v?.length ?? 0) < 8
                              ? 'Use al menos ocho caracteres'
                              : null,
                ),
                const SizedBox(height: 20),
                if (register) ...[
                  TextFormField(
                    controller: confirmation,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar contraseña',
                    ),
                    validator:
                        (v) =>
                            v == password.text
                                ? null
                                : 'Las contraseñas no coinciden',
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: agreed,
                    onChanged:
                        (value) => setState(() => agreed = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Acepto las condiciones de uso y privacidad',
                    ),
                    subtitle: const Text(
                      'Datos privados protegidos. Los pagos de esta versión son simulados; no se mueve dinero real.',
                    ),
                  ),
                ],
                TaskButton(
                  register ? 'Crear cuenta' : 'Ingresar',
                  icon: Icons.arrow_forward,
                  action: () async {
                    if (!form.currentState!.validate()) return;
                    if (register) {
                      if (!agreed || location == null) {
                        message(
                          context,
                          'Acepta las condiciones y selecciona tu ubicación.',
                        );
                        return;
                      }
                      final result = await app.registerAccount(
                        email: email.text.trim(),
                        password: password.text,
                        metadata: {
                          'name': name.text.trim(),
                          'district': district.text.trim(),
                          'role': role,
                          'location_code': location!.code,
                          'phone': phone.text.trim(),
                          'contact_name':
                              role == 'negocio'
                                  ? contact.text.trim()
                                  : name.text.trim(),
                        },
                      );
                      if (result.confirmationRequired && context.mounted) {
                        message(
                          context,
                          'El proveedor requiere confirmar el correo. Revise su bandeja; si no llega, revise las restricciones documentadas del correo gratuito.',
                        );
                      }
                    } else {
                      await app.signIn(email.text.trim(), password.text);
                    }
                  },
                ),
                if (!register)
                  TextButton(
                    onPressed: () => openPage(context, const RecoveryScreen()),
                    child: const Text('Olvidé mi contraseña'),
                  ),
                TextButton(
                  onPressed:
                      register
                          ? () => Navigator.pop(context)
                          : () => openPage(
                            context,
                            const AuthScreen(initialRegister: true),
                          ),
                  child: Text(
                    register
                        ? 'Ya tengo cuenta · Ingresar'
                        : '¿Primera vez? Crear cuenta',
                  ),
                ),
              ],
            ),
          ),
          if (app.error != null)
            Text(
              app.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 24),
          const Text(
            'Las fotos y la ubicación se solicitan únicamente al usarlas. La ubicación de entrega no se publica en el feed.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class RecoveryScreen extends StatefulWidget {
  final bool update;
  const RecoveryScreen({super.key, this.update = false});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.update ? 'Nueva contraseña' : 'Recuperar acceso'),
    ),
    body: PageBody(
      children: [
        SectionTitle(
          widget.update ? 'Protege tu cuenta' : 'Un enlace para volver',
          subtitle:
              widget.update
                  ? 'El enlace de recuperación fue recibido por la app.'
                  : 'El correo depende del servicio de envío configurado en Supabase.',
        ),
        Form(
          key: form,
          child: TextFormField(
            controller: controller,
            obscureText: widget.update,
            keyboardType:
                widget.update
                    ? TextInputType.visiblePassword
                    : TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText:
                  widget.update ? 'Nueva contraseña' : 'Correo electrónico',
            ),
            validator:
                (v) =>
                    widget.update
                        ? ((v?.length ?? 0) >= 8
                            ? null
                            : 'Use al menos ocho caracteres')
                        : ((v ?? '').contains('@')
                            ? null
                            : 'Ingrese un correo válido'),
          ),
        ),
        const SizedBox(height: 20),
        TaskButton(
          widget.update ? 'Guardar contraseña' : 'Solicitar enlace',
          action: () async {
            if (!form.currentState!.validate()) return;
            final app = context.read<AppState>();
            if (widget.update) {
              await app.repository!.cloud.auth.updateUser(
                UserAttributes(password: controller.text),
              );
              app.recovering = false;
              await app.refreshProfile();
            } else {
              await app.repository!.cloud.auth.resetPasswordForEmail(
                controller.text.trim(),
                redirectTo: 'encargalo://auth',
              );
              if (context.mounted) {
                message(
                  context,
                  'Solicitud aceptada por el proveedor. Revise el correo; la entrega depende de sus límites y configuración.',
                );
              }
            }
          },
        ),
      ],
    ),
  );
}
