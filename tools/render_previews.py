#!/usr/bin/env python3
"""Export and validate real onchain tokenURI output, using the local test-only VRF word.
No network, keys, wallet, FFI, test environment access, or Solidity filesystem permissions.
Run: python3 tools/render_previews.py
"""
import base64
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/previews'
# README thumbnails stay larger than the 200 px trait-readability target. The
# linked SVG files preserve the complete, unmodified onchain artwork.
PREVIEW_WIDTH = 300
OUT.mkdir(parents=True,exist_ok=True)
result = subprocess.run(['forge','test','--match-contract','PreviewExport','--match-test','testExport','-vv'],cwd=ROOT,text=True,capture_output=True)
if result.returncode:
    print(result.stdout);print(result.stderr);raise SystemExit(result.returncode)
entries=[]
for line in result.stdout.splitlines():
    match=re.search(r'(PREVIEW|MOON)\|(\d+)\|(data:application/json;base64,\S+)',line)
    if not match: continue
    kind,token_id,uri=match.groups()
    encoded=uri.split(',',1)[1]
    metadata=json.loads(base64.b64decode(encoded,validate=True))
    assert metadata['name']==f'NIGHT FROGS #{token_id}'
    assert metadata['image'].startswith('data:image/svg+xml;base64,')
    svg=base64.b64decode(metadata['image'].split(',',1)[1],validate=True)
    root=ET.fromstring(svg)
    assert root.attrib['viewBox']=='0 0 1000 1000'
    # All image references are internal. No network-dependent image or font assets.
    ids={e.attrib['id'] for e in root.iter() if 'id' in e.attrib}
    for e in root.iter():
        for key,value in e.attrib.items():
            if key.endswith('href'):
                assert value.startswith('#') and value[1:] in ids, value
            for ref in re.findall(r'url\(#([^)]*)\)',value): assert ref in ids,ref
    stem='moon' if kind=='MOON' else f'frog-{int(token_id):03d}'
    (OUT/f'{stem}.svg').write_bytes(svg)
    (OUT/f'{stem}.json').write_text(json.dumps(metadata,indent=2)+'\n')
    subprocess.run(['node','tools/svg_to_png.mjs',str(OUT/f'{stem}.svg'),str(OUT/f'{stem}.png'),str(PREVIEW_WIDTH)],cwd=ROOT,check=True)
    if kind=='PREVIEW':
        attrs={a['trait_type']:a['value'] for a in metadata['attributes']}
        assert len(attrs)==9
        entries.append({'tokenId':int(token_id),'svg':f'{stem}.svg','png':f'{stem}.png','attributes':attrs,'svgSha256':hashlib.sha256(svg).hexdigest()})
assert len(entries)==16,len(entries)
catalog=json.loads((ROOT/'art/catalog.json').read_text())
expected={(group['category'],t['name']) for group in catalog for t in group['traits']}
covered={(category,value) for entry in entries for category,value in entry['attributes'].items() if category in {g['category'] for g in catalog}}
assert covered==expected, ('Missing trait previews',expected-covered)
(OUT/'index.json').write_text(json.dumps({'demoWord':20261016,'source':'NightFrogs.tokenURI after local mock VRF fulfillment; not production traits','tokens':entries},indent=2)+'\n')
# The saved SVG references sibling previews instead of duplicating all PNGs as
# base64. Inline images only in memory to produce a self-contained contact PNG.
fragments=[]
inline_fragments=[]
for n,entry in enumerate(entries):
    # Embed rendered PNGs: nested SVG font lookup differs between rendering engines.
    data=base64.b64encode((OUT/entry['png']).read_bytes()).decode()
    image=f'<image x="{(n%4)*200}" y="{(n//4)*200}" width="200" height="200" href="{{}}"/>'
    fragments.append(image.format(entry['png']))
    inline_fragments.append(image.format(f'data:image/png;base64,{data}'))
header='<svg xmlns="http://www.w3.org/2000/svg" width="800" height="800" viewBox="0 0 800 800">'
(OUT/'contact-sheet.svg').write_text(header+''.join(fragments)+'</svg>\n')
sheet=header+''.join(inline_fragments)+'</svg>'
subprocess.run(['node','tools/svg_to_png.mjs','-',str(OUT/'contact-sheet.png'),'800'],input=sheet,text=True,cwd=ROOT,check=True)
print(f'Exported {len(entries)} authentic contract previews + unrevealed moon to docs/previews')
