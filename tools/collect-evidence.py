"""Conserva logs reales en texto UTF-8 para incluirlos en el repositorio."""
from pathlib import Path
from datetime import datetime, timezone

root=Path(__file__).resolve().parent.parent
target=root.parent/'encargalo_documentacion/evidencias'
target.mkdir(parents=True,exist_ok=True)
paths=['analyze-cierre.log','tests-cierre.log','backend-tests/tests-backend-final.log',
       'deno-push.log','deno-geocode.log','build-debug-ascii.log',
       'build-release-ascii.log','build-aab-ascii.log','firma-apk.log','firma-aab.log',
       'apk-badging.log','build-inicial.log','build-debug.log','build-debug-kotlin21.log',
       'build-release-ascii-firma.log']
for name in paths:
    source=root.parent/'encargalo_documentacion/registros'/Path(name).name
    if not source.exists(): continue
    data=source.read_bytes()
    if data.startswith((b'\xff\xfe',b'\xfe\xff')):
        text=data.decode('utf-16')
    else:
        text=data.decode('utf-8',errors='replace')
    out=target/(source.stem+'.txt')
    out.write_text('LOG REAL · '+name+'\n'+text,encoding='utf-8')
    print(out)
(target/'README.md').write_text('''# Evidencias disponibles

Estos archivos reproducen comandos realmente ejecutados. Las pruebas Flutter usan
dobles de hardware y fixtures explícitos; PostgreSQL WASM no es el backend cloud.
Los logs de compilación acreditan artefactos, no su instalación ni cámara/GPS/push
en teléfono. No hay capturas de sesiones cloud: faltan las cuentas autorizadas.

PowerShell registra algunas salidas stderr como NativeCommandError aunque el
proceso termine correctamente. Se distingue la línea final de éxito/fracaso;
una advertencia de un plugin no se interpreta como una prueba de la app.
''',encoding='utf-8')
