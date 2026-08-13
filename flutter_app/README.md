# Specular Flutter migration

Flutter/Dart replacement for the existing Android Compose client. It preserves
the `com.specular.android` application ID, legacy `files/notes` Markdown
mirror, and `databases/reflect.db` compatibility schema for an in-place update.

## Local checks

From the repository root, use the shared build commands:

```bash
make build-debug
make install-debug
make clean
```

For additional Flutter checks, run from this directory:

```bash
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

To build a production update, copy `android/key.properties.example` to
`android/key.properties` and point it at the same keystore used by the legacy
application. Release tasks intentionally fail without those properties.

## macOS desktop app

The committed `macos/` runner targets macOS 11 or later and uses bundle ID
`com.specular.app`. Build it from the repository root with:

```bash
make build-macos-debug
make build-macos-release
```

Or run it directly during development:

```bash
flutter run -d macos
flutter build macos --debug
```

The sandbox permits outgoing network requests, user-selected image files, and
microphone input for optional voice capture. macOS image import is intentionally
file-chooser-only; desktop sync is best effort while the app is running and is
not a post-quit background service. See `../docs/macos-release.md` before
making a signed distribution build.
