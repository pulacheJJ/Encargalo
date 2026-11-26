# Encargalo · Android, Flutter y Supabase Free

Aplicación Android nueva para conectar clientes de Piura con negocios de productos personalizados. Presupuesto requerido: **S/ 0, sin tarjeta ni facturación**.

## Estado real de esta entrega

**APK actual: 1.1.0+4**, ubicación local `apk/Encargalo.apk`, 60.603.604 bytes (57,80 MiB). Compilada solo en release, con conexión cloud y firma original comprobadas. Instalar encima de la versión anterior, sin desinstalar ni borrar datos. Validación: 51 pruebas Flutter, 15 PostgreSQL y 54 comprobaciones cloud aprobadas; análisis sin incidencias. SHA-256: `C5BAC3FDB49622D1D2AB342315F65A1B9526C26929DFBAFAABE27FC8E9E3EBC7`.

En GitHub, descarga la APK desde [Releases · v1.1.0](https://github.com/pulacheJJ/Encargalo/releases/tag/v1.1.0). El binario no se añade al historial Git; `apk/Encargalo.apk` es su ubicación en la entrega local. No desinstales la app anterior ni borres sus datos para actualizar.

El backend ya está desplegado en Supabase: Auth, perfiles, solicitudes, imágenes privadas, cotizaciones, pedidos, historial, RLS y Realtime. FCM opera desde una Edge Function cloud con identidad de servicio exclusiva y cron; su permiso de envío está validado, pero no se confunde con recepción en un teléfono. Los usuarios y sus perfiles se conservan en la nube; no se almacenan contraseñas en SQLite. La nueva versión protege la sesión del SDK con Android Keystore y migra la persistencia anterior sin borrar borradores.

Se conservan Supabase **Free** y Firebase **Spark**, sin tarjeta ni facturación. No se emplean Firebase Auth, Firestore, Realtime Database, Firebase Storage, Cloud Functions, localhost ni túneles como backend.

Los pagos son una **simulación explícita**, con registro persistente, idempotencia, adelanto, saldo, rechazos y devoluciones. No se conecta una billetera ni se piden tarjetas o claves bancarias. El servidor controla los estados: antes de producir se cancela con devolución completa; después se requiere acuerdo de ambas partes y una retención limitada al adelanto pagado. Un pago o una cancelación no se consideran confirmados hasta recibir respuesta del servidor.

## Estructura

- `lib/app/`: composición, sesión, configuración y sistema visual Material 3.
- `lib/core/`: red, consultas agrupadas, almacenamiento, cámara/GPS, notificaciones, tareas Android y componentes compartidos.
- `lib/features/auth/`: contrato de acceso, adaptador Supabase, persistencia segura y pantallas de ingreso/registro.
- `lib/features/profile/`: contrato, repositorio y edición de datos propios, públicos y privados.
- `lib/features/locations/`: catálogo territorial, API y selección dependiente región → provincia → distrito.
- `lib/features/home/`: resumen agregado real y navegación por rol, conservando cada pestaña después de visitarla.
- `lib/features/requests/`: controlador de borrador, especificaciones, adjuntos y entrega.
- `lib/features/marketplace/`: consultas de mercado, comparación, cotizaciones y seguimiento.
- `lib/features/payments/`: contratos, repositorio e interfaz del registro de pagos/cancelaciones simuladas.
- `supabase/migrations/`: esquema, restricciones, RLS, RPC, Storage privado, Realtime y caché de geocodificación.
- `supabase/functions/`: emisor FCM HTTP v1 y proxy restringido a distritos de Piura.
- `backend-tests/`: PostgreSQL WASM aislado para seguridad; no es un servidor del producto.
- `test/`: pruebas unitarias y de widgets, más `test/support/` (backend Supabase simulado y arnés de sesión) y `test/walkthrough_manual.dart`, el recorrido funcional completo que se ejecuta manualmente mientras termina de estabilizarse.
- `assets/locations/`: 1.893 distritos, 25 regiones y licencia MIT del conjunto versionado; no son ubicaciones inventadas. La API del catálogo se consulta sin enviar direcciones personales a terceros.
- `apk/`: APK instalable; no se mezclan informes o binarios de versiones anteriores.
- `tools/`: scripts reproducibles de compilación, pruebas y despliegue, sin secretos incrustados.
- `.github/workflows/ci.yml`: análisis y pruebas automáticas en GitHub con Flutter 3.29.3 y PostgreSQL aislado.

La documentación académica, informes, evidencias, registros de ejecución y versiones anteriores se conservan **fuera del proyecto**, en `../encargalo_documentacion/`. Su separación no elimina los requisitos del `.txt`, incluida la prioridad de cámara/GPS y los cinco aportes opcionales del equipo. Las capas se organizan por capacidad; los límites de Auth, perfiles, catálogo y pagos tienen interfaces sustituibles en pruebas, y las reglas comerciales autoritativas se ejecutan en transacciones SQL, no en botones.

Esa carpeta externa no se publica en este repositorio. Tampoco se publican sesiones, cuentas de prueba, configuración local o firma privada. Al clonar, prepara `config/public.json` a partir de `config/public.example.json` con los valores públicos de tus proyectos y configura tu entorno autorizado por separado. La firma original del equipo debe conservarse privadamente: no se comparte en GitHub ni se regenera para actualizar la aplicación existente.

## Entorno utilizado

Windows 10, Flutter 3.29.3 / Dart 3.7.2; Java Corretto 21.0.8; Android SDK en `D:/desarrollo/android-sdk`; plataforma 35; NDK 27.0.12077973; Git 2.51.0; Node 20.15.1. Las versiones resueltas se conservan en `pubspec.lock` y `backend-tests/package-lock.json`.

La máquina tiene 8 GB de RAM y cuatro procesadores lógicos; Gradle se limita a 3 GB y dos workers en la configuración del proyecto para no reservar los 8 GB de la plantilla. Supabase CLI 3.3.0 y Deno 2.2.7 fueron comprobados sin instalar un servidor local del producto.

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
```

Pruebas PostgreSQL aisladas (desde `backend-tests/`):

```powershell
npm ci
npm test
```

## Pruebas automatizadas

`flutter test` ejecuta las 51 pruebas unitarias y de widgets existentes. Además, `test/walkthrough_manual.dart` contiene cinco recorridos de integración que montan la app real (`EncargaloApp`) contra `test/support/fake_backend.dart`: un backend Supabase simulado con Auth, PostgREST y RPC, SQLite en memoria y preferencias en memoria. No requiere emulador, cuentas ni claves. Se ejecuta con:

```powershell
flutter test test/walkthrough_manual.dart --reporter expanded
```

Los recorridos cubren:

1. Acceso, publicación de una solicitud y cierre de sesión del cliente.
2. Cotización de una solicitud publicada por un negocio.
3. Aceptación del acuerdo, pago simulado del adelanto, cancelación y devolución.
4. Producción, saldo final, entrega y confirmación de recepción.
5. Publicación sin respuesta del servidor: queda en cola local y se reintenta.

El escenario 5 ya pasa; los otros cuatro están en estabilización (esperas del binding en vivo) y todavía no forman parte del workflow, para no bloquear los cambios mientras se corrigen.

El workflow `.github/workflows/ci.yml` repite en cada `push`, `pull request` o ejecución manual: `flutter analyze`, `flutter test` y `npm test` de `backend-tests/` sobre PostgreSQL aislado.

Estas pruebas no sustituyen la verificación física: cámara, GPS, notificaciones push, tareas en segundo plano, empaquetado Android y latencia real se comprueban en un dispositivo. Las reglas comerciales autoritativas siguen validándose con las pruebas PostgreSQL del backend.

## Compilación y firma

`pe.edu.unp.encargalo`, fuentes `1.1.0+4`, Android 7.0/API 24 o superior. La firma original se conserva para actualizaciones sin desinstalar. **No regenerar la firma existente.** `.secrets/`, la configuración pública local y `android/key.properties` quedan fuera de Git; las claves privadas no pertenecen a la APK ni a una distribución de fuentes. El manifiesto externo indica qué versión corresponde realmente al archivo APK disponible.

Después del despliegue y de copiar `config/public.example.json` a `config/public.json` con los identificadores públicos reales:

```powershell
flutter build apk --debug --dart-define-from-file=config/public.json
flutter build apk --release --dart-define-from-file=config/public.json
flutter build appbundle --release --dart-define-from-file=config/public.json
```

Sin esos parámetros puede compilarse una APK de diagnóstico del estado pendiente, **no una entrega funcional conectada**. El modo release no utiliza la firma debug.

En esta máquina el compilador nativo de shaders no admite la tilde de la ruta. Para generar solo la APK final, sin repetir debug/AAB:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build-android.ps1 -ReleaseOnly -PublicConfig config/public.json
powershell -NoProfile -ExecutionPolicy Bypass -File tools/package-delivery.ps1 -ReleaseOnly -Configured -Deployed
python tools/verify-delivery.py
```

El script usa una copia ASCII aprobada, sin cambiar la configuración global ni mover el proyecto. Los registros y manifiestos se escriben en la carpeta externa de documentación. `apk/Encargalo.apk` se puede transferir e instalar manualmente encima de la versión anterior, sin USB ni desinstalación.

El script utiliza una copia temporal protegida de la misma firma original para evitar el problema de rutas Unicode al empaquetar. No la sustituye por una firma debug ni genera otra identidad.

## Verificación y límites

La revisión cuenta con pruebas automatizadas del primer ingreso sin esperar FCM, agrupación de sesión/consultas, migración segura, SQLite, colas, roles y comercio. El recorrido cloud comprueba también pago simulado, adelanto y cancelación con devolución. Estas pruebas no sustituyen cámara/GPS, push visible, otra red y ejecución diferida en un Android real. Confirmación/recuperación por correo sigue dependiendo del SMTP gratuito autorizado y no se da por verificada por tener usuarios de prueba confirmados administrativamente.

La trazabilidad completa, los resultados y el material de sustentación están en la carpeta externa local `../encargalo_documentacion/`, no incluida en GitHub. No se fabrican commits, integrantes, métricas, reseñas ni evidencia de pruebas físicas. Free/Spark tienen cuotas y no garantizan disponibilidad ilimitada.

El sílabo original no fue adjuntado a esta carpeta. La cobertura semanal se tomó del prompt y queda pendiente contrastarla con el documento docente. El repositorio público es `pulacheJJ/Encargalo`, rama `main`. No se atribuyen contribuciones a integrantes sin aportes verificables ni se inventan reseñas o evidencias de teléfonos.
