"""Verifica archivos locales. No reemplaza pruebas cloud ni de hardware Android."""
from pathlib import Path
import hashlib
import json
import zipfile

root=Path(__file__).resolve().parent.parent
evidence=root.parent/'encargalo_documentacion/evidencias/compilacion'
manifest=json.loads((evidence/'MANIFIESTO.json').read_text(encoding='utf-8-sig'))
for artifact in manifest['artifacts']:
    path=root/'apk'/artifact['file']
    with path.open('rb') as stream:
        digest=hashlib.file_digest(stream,'sha256').hexdigest().upper()
    assert path.stat().st_size==artifact['bytes'], f'Tamano diferente: {path.name}'
    assert digest==artifact['sha256'], f'Hash diferente: {path.name}'
    print(f'{path.name}: {artifact["bytes"]} bytes, SHA-256 correcto')
sources=json.loads((evidence/'FUENTES_COMPILADAS.json').read_text(encoding='utf-8'))
if 'version' in sources:
    assert sources['version']==manifest['version'], 'Version de fuentes/artefactos diferente'
for source in sources['files']:
    digest=hashlib.sha256((root/source['file']).read_bytes()).hexdigest().upper()
    assert digest==source['sha256'], f'Fuente cambiada desde compilacion: {source["file"]}'
print(f'Fuentes/configuracion coincidentes: {len(sources["files"])}')
forbidden=[]
private_account=root/'.secrets/fcm-service-account.json'
if private_account.exists():
    account=json.loads(private_account.read_text(encoding='utf-8-sig'))
    forbidden.extend([account['private_key'].encode(),account['private_key'].splitlines()[1].encode(),account['private_key_id'].encode()])
edge=root/'.secrets/edge.env'
if edge.exists():
    for line in edge.read_text(encoding='utf-8-sig').splitlines():
        if line.startswith('PUSH_DISPATCH_SECRET='):
            forbidden.append(line.split('=',1)[1].encode())
for artifact in manifest['artifacts']:
    path=root/'apk'/artifact['file']
    if path.suffix not in ('.apk','.aab'):
        continue
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            assert '.secrets/' not in name and not name.endswith(('.jks','.keystore','key.properties','service-account.json')), 'Archivo privado incluido'
            if not name.endswith('/'):
                data=archive.read(name)
                assert not any(value in data for value in forbidden), 'Material secreto incluido en artefacto'
    print(f'{path.name}: sin archivos privados ni material FCM/despacho de servidor')
print('Configuracion cloud declarada:',manifest['cloudConfigured'])
print('Despliegue declarado:',manifest['deployed'])
