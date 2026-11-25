APP := .build/Rowvi.app
CONTENTS := $(APP)/Contents
MACOS := $(CONTENTS)/MacOS
SWIFTC := xcrun --sdk macosx swiftc
CLANG := xcrun --sdk macosx clang
TARGET := $(shell uname -m)-apple-macosx27.0
CACHE := .build/module-cache
ICONSET := .build/Rowvi.iconset
ICON := .build/Rowvi.icns

.PHONY: build check open
.DELETE_ON_ERROR:
build: $(MACOS)/Rowvi

$(MACOS)/Rowvi: $(wildcard Sources/*.swift) Sources/NativeSpaces.h $(CACHE)/NativeSpaces.o Resources/Info.plist $(ICON) Makefile
	mkdir -p "$(MACOS)" "$(CONTENTS)/Resources" "$(CACHE)"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp "$(ICON)" "$(CONTENTS)/Resources/Rowvi.icns"
	$(SWIFTC) -swift-version 6 -target $(TARGET) -module-cache-path "$(CACHE)" -O -import-objc-header Sources/NativeSpaces.h Sources/*.swift "$(CACHE)/NativeSpaces.o" -o "$@"
	codesign --force --sign - "$(APP)"

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
