#!/bin/bash
# Build this fork and update an existing Apollo IPA, retaining its icon catalog.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env.personal-build ]]; then
    set -a
    source .env.personal-build
    set +a
fi

BASE_IPA="${1:?usage: build-personal-ipa.sh base.ipa build-number}"
BUILD_NUMBER="${2:?provide a build number newer than the installed app}"
: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY in .env.personal-build}"
: "${PROVISIONING_PROFILE:?set PROVISIONING_PROFILE in .env.personal-build}"
[[ -f "$BASE_IPA" && -f "$PROVISIONING_PROFILE" ]] || {
    echo "Missing base IPA or provisioning profile" >&2
    exit 1
}
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
    echo "Build number must contain one to three numeric components" >&2
    exit 1
}
export THEOS="${THEOS:-$HOME/theos}"
OUT="$PWD/packages/personal-$BUILD_NUMBER"
mkdir -p "$OUT"

MAKE=make
if command -v gmake >/dev/null; then MAKE=gmake; fi
"$MAKE" -j6 package FINALPACKAGE=1 \
    APOLLO_DEVICE_SDK="${APOLLO_DEVICE_SDK:-26.0}" \
    APOLLO_DEVICE_DEPLOY="${APOLLO_DEVICE_DEPLOY:-14.0}"
DEB="$(ls -t packages/*.deb | head -1)"
bash build-ipa.sh --ipa "$BASE_IPA" --deb "$DEB" -o "$OUT/injected.ipa"

WORK="$(mktemp -d /tmp/apollo-personal-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$OUT/injected.ipa" -d "$WORK"
APP="$WORK/Payload/Apollo.app"
source scripts/modules/liquid-glass-binary.sh
patch_liquid_glass_binary_in_app "$APP"

python3 - "$APP" "$BUILD_NUMBER" <<'PY'
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
old_id = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
new_id = 'com.kylefowler.apolloreborn'
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
for bundle in [app, *sorted((app / 'PlugIns').glob('*.appex'))]:
    path = bundle / 'Info.plist'
    info = plistlib.loads(path.read_bytes())
    bundle_id = info['CFBundleIdentifier']
    if bundle_id != old_id and not bundle_id.startswith(old_id + '.'):
        raise SystemExit(f'Unexpected extension bundle ID: {bundle_id}')
    info['CFBundleIdentifier'] = new_id + bundle_id[len(old_id):]
    info['CFBundleVersion'] = sys.argv[2]
    if bundle == app:
        info['CFBundleDisplayName'] = 'Apollo Reborn'
        info['ARPersonalGitCommit'] = commit
        info['ARPersonalRepository'] = 'https://github.com/kylerfowler/Apollo-Reborn'
    path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
PY

(cd "$WORK" && zip -qry "$OUT/unsigned.ipa" Payload)
bash scripts/resign-ipa-codesign.sh "$OUT/unsigned.ipa" "$SIGNING_IDENTITY" \
    --profile "$PROVISIONING_PROFILE" -o "$OUT/signed.ipa"

python3 - "$OUT" "$BASE_IPA" "$DEB" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

out = pathlib.Path(sys.argv[1])
def digest(path):
    return hashlib.file_digest(open(path, 'rb'), 'sha256').hexdigest()
record = {
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'branch': subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip(),
    'repoUrl': 'https://github.com/kylerfowler/Apollo-Reborn',
    'sha256': digest(out / 'signed.ipa'),
    'baseSha256': digest(sys.argv[2]),
    'debSha256': digest(sys.argv[3]),
}
(out / 'provenance.json').write_text(json.dumps(record, indent=2) + '\n')
print('Signed personal build:', out / 'signed.ipa')
PY
