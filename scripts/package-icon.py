#!/usr/bin/env python3
"""Package PNG representations in the documented ICNS chunk container."""
from pathlib import Path
import struct
import sys
root, destination = map(Path, sys.argv[1:])
chunks = []
for kind, name in [(b'icp4', 'icon_16x16.png'), (b'icp5', 'icon_32x32.png'), (b'icp6', 'icon_32x32@2x.png'), (b'ic07', 'icon_128x128.png'), (b'ic08', 'icon_256x256.png'), (b'ic09', 'icon_512x512.png'), (b'ic10', 'icon_512x512@2x.png')]:
    data = (root / name).read_bytes()
    chunks.append(kind + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
destination.write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
