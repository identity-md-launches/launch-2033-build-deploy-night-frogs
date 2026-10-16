#!/usr/bin/env python3
"""Offline integrity check of human-readable SVG masters against generated SSTORE2 payloads."""
import json
import re
from pathlib import Path

root=Path(__file__).resolve().parents[1]
art=root/'art'
catalog=json.loads((art/'catalog.json').read_text())
banks=json.loads((art/'banks.json').read_text())
expected=[(art/f'{name}.svg').read_text().rstrip('\n') for name in ['common','finish','placeholder','captain']]
for group in catalog:
    category=group['category'].lower()
    for item in group['traits']:
        assert item['nameRecord']==len(expected)
        expected += [item['name'],(art/category/f'{item["index"]:02}.svg').read_text().rstrip('\n')]
actual=[]
for bank in banks:
    source=(root/'src/art'/f'{bank["contract"]}.sol').read_text()
    payload=bytes.fromhex(''.join(re.findall(r'hex"([0-9a-f]+)"',source)))
    assert len(payload)==bank['bytes'] and len(payload)<24576
    count=int.from_bytes(payload[:2],'big')
    assert count==bank['count'] and bank['start']==len(actual)
    offsets=[int.from_bytes(payload[2+i*2:4+i*2],'big') for i in range(count+1)]
    assert offsets[0]==2+(count+1)*2 and offsets[-1]==len(payload)
    actual.extend(payload[offsets[i]:offsets[i+1]].decode() for i in range(count))
assert actual==expected,'Generated contracts differ from art master records'
assert [len(c['traits']) for c in catalog]==[6,6,8,6,8,8,6]
for layer,group in enumerate(catalog):
    weighted=group['traits'][:5] if layer==0 else group['traits']
    assert sum(t['weight'] for t in weighted)==100
print(f'Validated {len(actual)} immutable records; all 48 trait names, fragments and rarity weights match.')
