"""Downloads pinned MIT-licensed territorial data; never executes remote code."""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
REVISION = '39045c1c8ad624a5ab2f5c125b5e37c30e54c648'
BASE = f'https://raw.githubusercontent.com/peru-code-dev/ubigeo-peru/{REVISION}/'

def download(path):
    with urlopen(BASE + path, timeout=40) as response:
        return response.read()

regions = json.loads(download('src/data/regions.json'))
provinces = json.loads(download('src/data/provinces.json'))
districts = json.loads(download('src/data/districts.json'))
rows = []
for region in regions:
    for province in provinces[str(region['id'])]:
        for district in districts[str(province['id'])]:
            code = district['ineiCode']
            assert len(code) == 6 and code.startswith(province['ineiCode']) and code.startswith(region['ineiCode'])
            rows.append({'code': code, 'region': region['name'].title(), 'province': province['name'].title(), 'district': district['name'].title()})
assert len(regions) == 25 and len({r['code'] for r in rows}) == len(rows) and len(rows) > 1800
target = ROOT/'assets/locations'
target.mkdir(parents=True, exist_ok=True)
data = json.dumps({'source': 'peru-code-dev/ubigeo-peru', 'revision': REVISION, 'code_system': 'INEI', 'locations': rows}, ensure_ascii=False, separators=(',', ':')).encode()
path = target/'peru.json'
if path.exists() and path.read_bytes() != data:
    raise SystemExit('Dataset existente distinto: no se sobrescribe sin revisar.')
path.write_bytes(data)
(target/'LICENSE.txt').write_bytes(download('LICENSE'))
print(f'Catálogo territorial: {len(rows)} distritos reales, 25 regiones. SHA-256 {hashlib.sha256(data).hexdigest()}')
