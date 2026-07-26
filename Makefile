CONFIG ?= release
APP_NAME := StatsMenu
BUILD_DIR := .build/$(CONFIG)
OUTPUT_DIR := build
APP_BUNDLE := $(OUTPUT_DIR)/$(APP_NAME).app
ZIP_FILE := $(OUTPUT_DIR)/$(APP_NAME).zip

.PHONY: all build app zip run restart format clean

all: zip

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	printf 'APPL????' > $(APP_BUNDLE)/Contents/PkgInfo
	codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true

zip: app
	rm -f $(ZIP_FILE)
	ditto -c -k --keepParent $(APP_BUNDLE) $(ZIP_FILE)
	@echo "Done → $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

restart: app
	-pkill -x $(APP_NAME)
	sleep 1
	open $(APP_BUNDLE)

format:
	swift format --in-place --recursive Sources Package.swift

clean:
	swift package clean
	rm -rf $(OUTPUT_DIR)
