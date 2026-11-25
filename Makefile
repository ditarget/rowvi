APP := .build/Rowvi.app
CONTENTS := $(APP)/Contents
MACOS := $(CONTENTS)/MacOS
SWIFTC := xcrun --sdk macosx swiftc
CLANG := xcrun --sdk macosx clang
TARGET := $(shell uname -m)-apple-macosx27.0
CACHE := .build/module-cache
ICONSET := .build/Rowvi.iconset
ICON := .build/Rowvi.icns
SPARKLE_VERSION := 2.10.1
SPARKLE_SHA256 := 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR := .build/sparkle-$(SPARKLE_VERSION)
SPARKLE_ARCHIVE := .build/downloads/Sparkle-$(SPARKLE_VERSION).tar.xz

.PHONY: build check open sparkle-keys release
.DELETE_ON_ERROR:
build: $(MACOS)/Rowvi

$(MACOS)/Rowvi: $(wildcard Sources/*.swift) Sources/NativeSpaces.h $(CACHE)/NativeSpaces.o Resources/Info.plist $(ICON) LICENSE $(SPARKLE_DIR)/.ready Makefile
	mkdir -p "$(MACOS)" "$(CONTENTS)/Resources" "$(CACHE)"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp "$(ICON)" "$(CONTENTS)/Resources/Rowvi.icns"
	cp LICENSE "$(CONTENTS)/Resources/LICENSE.txt"
	cp "$(SPARKLE_DIR)/LICENSE" "$(CONTENTS)/Resources/Sparkle-LICENSE.txt"
	mkdir -p "$(CONTENTS)/Frameworks"
	rm -rf "$(CONTENTS)/Frameworks/Sparkle.framework"
	ditto "$(SPARKLE_DIR)/Sparkle.framework" "$(CONTENTS)/Frameworks/Sparkle.framework"
	$(SWIFTC) -swift-version 6 -target $(TARGET) -module-cache-path "$(CACHE)" -O -F "$(SPARKLE_DIR)" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -import-objc-header Sources/NativeSpaces.h Sources/*.swift "$(CACHE)/NativeSpaces.o" -o "$@"
	codesign --force --sign - "$(APP)"
	codesign --verify --deep --strict "$(APP)"

$(SPARKLE_ARCHIVE):
	mkdir -p "$(@D)"
	curl --fail --silent --show-error --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/$(@F)" -o "$@.tmp"
	echo "$(SPARKLE_SHA256)  $@.tmp" | shasum -a 256 -c -
	mv "$@.tmp" "$@"

$(SPARKLE_DIR)/.ready: $(SPARKLE_ARCHIVE) Makefile
	echo "$(SPARKLE_SHA256)  $<" | shasum -a 256 -c -
	mkdir -p "$(@D)"
	tar -xJf "$<" -C "$(@D)" ./bin ./Sparkle.framework ./LICENSE
	touch "$@"

$(ICON): Resources/Rowvi.png Makefile
	mkdir -p "$(ICONSET)"
	set -e; for size in 16 32 128 256 512; do \
		sips -z "$$size" "$$size" "$<" --out "$(ICONSET)/icon_$${size}x$$size.png" >/dev/null; \
		double=$$((size * 2)); \
		sips -z "$$double" "$$double" "$<" --out "$(ICONSET)/icon_$${size}x$$size@2x.png" >/dev/null; \
	done
	iconutil -c icns "$(ICONSET)" -o "$@"

$(CACHE)/NativeSpaces.o: Sources/NativeSpaces.m Sources/NativeSpaces.h Makefile
	mkdir -p "$(CACHE)"
	$(CLANG) -target $(TARGET) -fobjc-arc -Wall -Wextra -c Sources/NativeSpaces.m -o "$@"

check:
	mkdir -p "$(CACHE)"
	$(SWIFTC) -swift-version 6 -target $(TARGET) -module-cache-path "$(CACHE)" Sources/Layout.swift Sources/ProfileLibrary.swift Sources/PanelMetrics.swift Sources/WindowInventory.swift Tests/LayoutChecks.swift -o .build/layout-checks
	.build/layout-checks
	plutil -lint Resources/Info.plist

open: build
	open "$(APP)"

sparkle-keys: $(SPARKLE_DIR)/.ready
	"$(SPARKLE_DIR)/bin/generate_keys" --account rowvi

release: build
	bash Scripts/package-release.sh "$(APP)" "$(SPARKLE_DIR)/bin"
