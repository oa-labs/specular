# macOS release guide

Specular is distributed directly as a Developer ID-signed and notarized DMG.
The release build uses `com.specular.app`, macOS 11+, an app sandbox, outgoing
network access, user-selected read-only files, and microphone input. Do not add
camera permission unless native camera capture is implemented.

## Build and sign

On a release Mac with the Developer ID Application certificate installed:

```bash
make build-macos-release
codesign --force --deep --options runtime --sign "Developer ID Application: YOUR TEAM" \
  flutter_app/build/macos/Build/Products/Release/Specular.app
codesign --verify --deep --strict --verbose=2 \
  flutter_app/build/macos/Build/Products/Release/Specular.app
```

Use a separate, protected App Store Connect API key or keychain profile to
notarize. Never put certificates, private keys, app-specific passwords, or API
keys in this repository or CI logs.

```bash
xcrun notarytool submit Specular.dmg --keychain-profile "specular-notary" --wait
xcrun stapler staple Specular.dmg
xcrun stapler validate Specular.dmg
shasum -a 256 Specular.dmg
```

Create the DMG only after signing the app, for example with `hdiutil create`
using a staging folder containing `Specular.app`. Upload the stapled DMG and its
SHA-256 checksum to GitHub Releases.

## Release checklist

- Test the release-sandboxed app on clean Apple Silicon and Intel Macs.
- Verify Keychain persistence, private-repository pull/push/conflicts, image
  import/cancellation, microphone grant/deny/re-enable, external links, and
  sleep/resume.
- Confirm scheduled-sync copy says it is best effort while Specular is open;
  it must not claim to run after quit.
- Install the DMG without developer overrides, then test an in-place upgrade.
