# Personal Liquid Glass builds

This fork's `kyle/personal-build` branch starts at the official 4.0.1 release
commit `d364ce68631a125a3c6a6cefbe59b5f711d75c91`. The first personal tweak
version is `4.0.1+kyle.1`, visible in Apollo Reborn's About section.

The build compiles this fork, replaces the tweak inside an existing injected
Apollo IPA, applies the upstream Liquid Glass executable patch, and signs the
app and extensions. It retains the base IPA's icon catalog to fit Speedflight's
upload limit. The app ID stays `com.kylefowler.apolloreborn` for in-place updates.

## Local setup

Install Theos at `~/theos`, its submodules, and Homebrew `make`, `ldid`, and
`dpkg`. Run `git submodule update --init --recursive` in this checkout.

Create a gitignored `.env.personal-build` with these local settings:

```bash
THEOS=/Users/kylefowler/theos
DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
APOLLO_DEVICE_SDK=26.5
APOLLO_DEVICE_DEPLOY=15.0
SIGNING_IDENTITY='your existing Apple signing identity'
PROVISIONING_PROFILE='/absolute/path/to/existing.mobileprovision'
```

This personal build uses the installed iOS 26.5 SDK and an iOS 15 deployment
floor. Upstream's default release SDK and deployment floor remain unchanged.
The provisioning profile must cover this app, its extensions, and the phone.
Certificates and profiles remain outside the repository.

## Build and share

Commit the changes to build, then push the personal branch to `origin`.
Use an already-injected Apollo IPA as the base and increase the build number:

```bash
bash scripts/build-personal-ipa.sh /absolute/path/to/Apollo-base.ipa 303.2
```

Keep the existing app's `SPEEDFLIGHT_SECRET` in gitignored `.env.speedflight`.
Then upload the signed IPA from the clean, pushed checkout:

```bash
python3 scripts/share-personal-build.py packages/personal-303.2/signed.ipa \
  'Apollo Reborn — Kyle build 1' \
  'Built from the personal fork. Check Liquid Glass and the About version.'
```

Build output and provenance live under gitignored `packages/`. Never commit
IPAs, credentials, provisioning profiles, or the private install-page URL.

Verify nested signatures, provisioning, the embedded source commit, and the
hosted IPA checksum before handing off. Those checks prove artifact integrity;
installation, launch, and interaction checks on the phone are separate.
