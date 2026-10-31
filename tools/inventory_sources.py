#!/usr/bin/env python3
"""Developer-only inventory; never used by the Bash installer."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def inventory(ref):
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', ref], cwd=ROOT, text=True).splitlines()
    entries = []
    for path in paths:
        if not (path.endswith('.sh') or path == 'README.md' or path.startswith('src/') or path.startswith('include/ois.')):
            continue
        try:
            raw = subprocess.check_output(['git', 'show', f'{ref}:{path}'], cwd=ROOT)
            body = raw.decode('utf-8')
        except UnicodeDecodeError:
            entries.append({'consumer': path, 'type': 'bundled-binary', 'sha256': hashlib.sha256(raw).hexdigest(),
                            'platform': path.rsplit('.', 1)[-1], 'libc': 'unknown',
                            'policy': 'project blob identified; independent publisher/build provenance review required'})
            continue
        if path.startswith('src/'):
            entries.append({'consumer': path, 'type': 'bundled-file', 'policy': 'version-controlled patch/key; no implied publisher authentication'})
        for line, text in enumerate(body.splitlines(), 1):
            if re.search(r'\b(?:src_url=|wget |curl |Download_src|git clone)', text) and not text.lstrip().startswith('#'):
                entries.append({'consumer': path, 'line': line, 'expression': text.strip(),
                                'type': 'request' if 'curl ' in text else 'artifact',
                                'policy': 'review catalog or retain only non-artifact protocol request'})
    return entries


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ref', default='0a663e78bd3ece6d2a4f05812f129b4d46246d63')
    parser.add_argument('--output', default='docs/source-inventory.json')
    args = parser.parse_args()
    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({'baseline': args.ref, 'entries': inventory(args.ref)}, indent=2) + '\n', encoding='utf-8')
