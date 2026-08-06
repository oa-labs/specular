#!/bin/sh
#
# Standard Gradle wrapper script — uses class-path entry point (no Main-Class in manifest)
#
APP_NAME="Gradle"
APP_BASE_NAME=$(basename "$0")
GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
# Fallback to /tmp if home not writable (sandbox)
if [ ! -w "$HOME" ]; then
  GRADLE_USER_HOME="/tmp/gradle-home"
fi
mkdir -p "$GRADLE_USER_HOME" 2>/dev/null

CLASSPATH="gradle/wrapper/gradle-wrapper.jar"
exec java -classpath "$CLASSPATH" org.gradle.wrapper.GradleWrapperMain "$@"
