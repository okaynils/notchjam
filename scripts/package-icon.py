#!/usr/bin/env python3
"""Pack the generated PNG representations into the public ICNS container format."""
import struct
import sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
representations = {'icp4': '16x16', 'icp5': '32x32', 'icp6': '32x32@2x',
                   'ic07': '128x128', 'ic08': '256x256', 'ic09': '512x512', 'ic10': '512x512@2x',
                   'ic11': '16x16@2x', 'ic12': '32x32@2x', 'ic13': '128x128@2x', 'ic14': '256x256@2x'}
chunks = []
for kind, name in representations.items():
    data = (source / f'icon_{name}.png').read_bytes()
    chunks.append(kind.encode() + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
destination.write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
