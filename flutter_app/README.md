# Specular Flutter migration

Flutter/Dart replacement for the existing Android Compose client. It preserves
the `com.specular.android` application ID, legacy `files/notes` Markdown
mirror, and `databases/reflect.db` compatibility schema for an in-place update.

## Local checks

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
