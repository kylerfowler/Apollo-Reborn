#!/usr/bin/env python3
"""Upload a clean, pushed personal build without exposing the upload key."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
os.chdir(root)
ipa = Path(sys.argv[1]).resolve()
title, notes = sys.argv[2:4]
record = json.loads(ipa.with_name('provenance.json').read_text())
if subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip():
    raise SystemExit('Commit changes before sharing a build')
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
if record['commit'] != head:
    raise SystemExit('Build is from another commit; rebuild first')
subprocess.run(['git', 'merge-base', '--is-ancestor', head, '@{u}'], check=True)
with ipa.open('rb') as file:
    if hashlib.file_digest(file, 'sha256').hexdigest() != record['sha256']:
        raise SystemExit('IPA checksum differs from build provenance')

env = dict(os.environ)
config = root / '.env.speedflight'
if config.exists():
    for line in config.read_text().splitlines():
        if line.strip() and not line.lstrip().startswith('#'):
            key, value = line.removeprefix('export ').split('=', 1)
            parsed = shlex.split(value)
            env.setdefault(key.strip(), parsed[0] if parsed else '')
secret = env['SPEEDFLIGHT_SECRET']
bundle = 'com.kylefowler.apolloreborn'
output = ipa.parent

def request(method, path, source, destination):
    result = subprocess.run([
        'curl', '--config', '-', '--silent', '--show-error', '--http1.1',
        '--request', method, '--header', 'Content-Type: application/json'
        if method == 'POST' else 'Content-Type: application/octet-stream',
        '--data-binary', '@' + str(source), '--output', str(destination),
        '--write-out', '%{http_code}', '--connect-timeout', '15', '--max-time', '180',
    ], input=f'url = "https://speedflight.dev{path}"\n', capture_output=True, text=True)
    if result.returncode or not result.stdout.startswith('2'):
        raise SystemExit(f'Speedflight request failed (HTTP {result.stdout})')
    return json.loads(destination.read_text())

metadata = {
    'title': title, 'notes': notes, 'deepLink': 'apollo://',
    'branch': record['branch'], 'commit': head, 'author': 'kylerfowler',
    'repoUrl': record['repoUrl'],
}
metadata_path = output / 'speedflight-metadata.json'
metadata_path.write_text(json.dumps(metadata))
api = f'/api/apps/{secret}/{bundle}/builds'
created_path = output / 'speedflight-created.json'
if created_path.exists():
    created = json.loads(created_path.read_text())
else:
    created = request('POST', api, metadata_path, created_path)
result = request('PUT', f"{api}/{created['buildId']}/app.ipa", ipa,
                 output / 'speedflight-upload.json')
print(json.dumps(result, indent=2))
print('Build page:', created['pageUrl'])
