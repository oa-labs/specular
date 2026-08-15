# Specular contributor guidance

## Platform scope

Specular supports Android and macOS. Unless the user explicitly limits a
feature to one platform, treat every new product capability and capability
upgrade as an Android-and-macOS requirement.

- Prefer shared Flutter and Dart implementations so behavior, data formats, and
  tests remain consistent on both platforms.
- When platform-specific code is necessary, implement equivalent user-facing
  behavior on both platforms or document the supported limitation before
  shipping it.
- Verify affected Android and macOS paths in proportion to the change; do not
  describe a feature as complete for one platform when the other is unsupported.
