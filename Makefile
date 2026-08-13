FLUTTER ?= flutter
ADB ?= adb
FLUTTER_APP := flutter_app
DEBUG_APK := $(FLUTTER_APP)/build/app/outputs/flutter-apk/app-debug.apk
DEBUG_MACOS_APP := $(FLUTTER_APP)/build/macos/Build/Products/Debug/Specular.app
RELEASE_MACOS_APP := $(FLUTTER_APP)/build/macos/Build/Products/Release/Specular.app

.DEFAULT_GOAL := help

.PHONY: help build build-debug build-macos-debug build-macos-release clean install install-debug

help:
	@echo "Specular Flutter commands:"
	@echo "  make build-debug    Build the Android debug APK"
	@echo "  make install-debug  Build and install the debug APK on a connected device"
	@echo "  make build-macos-debug    Build the macOS debug app"
	@echo "  make build-macos-release  Build the macOS release app"
	@echo "  make clean          Remove Flutter build artifacts"

# These aliases keep the everyday commands short while the explicit variants
# make the build type clear in automation and documentation.
build: build-debug

install: install-debug

build-debug:
	cd "$(FLUTTER_APP)" && "$(FLUTTER)" build apk --debug

install-debug: build-debug
	# Preserve app data on an in-place update; a signing mismatch fails safely.
	$(ADB) install -r "$(DEBUG_APK)"

build-macos-debug:
	cd "$(FLUTTER_APP)" && "$(FLUTTER)" build macos --debug

build-macos-release:
	cd "$(FLUTTER_APP)" && "$(FLUTTER)" build macos --release

clean:
	cd "$(FLUTTER_APP)" && "$(FLUTTER)" clean
