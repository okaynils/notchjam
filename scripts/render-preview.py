#!/usr/bin/env python3
"""Compile and render the actual SwiftUI lyrics view without opening a desktop window."""
from pathlib import Path
import subprocess
import os
root = Path(__file__).resolve().parent.parent
os.chdir(root)
(root / 'build/qa').mkdir(parents=True, exist_ok=True)
sources = sorted(str(p) for p in Path('notchjam').rglob('*.swift') if p.name != 'NotchjamApp.swift')
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6',
                '-module-cache-path', '/tmp/notchjam-module-cache', '-Xfrontend', '-disable-sandbox',
                *sources, 'scripts/RenderPreview.swift', '-o', 'build/qa/render'], check=True)
subprocess.run(['build/qa/render'], check=True)
print(root / 'build/qa/panel.png')
