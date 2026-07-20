APP_NAME = MaxNits
BUILD_DIR = .build/release
APP_BUNDLE = dist/$(APP_NAME).app
PREFIX ?= $(HOME)/.local

.PHONY: build app run install uninstall clean

build:
	swift build -c release

app: build
	rm -rf dist
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

install: app
	mkdir -p $(PREFIX)/bin
	ln -sf $(abspath $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)) $(PREFIX)/bin/maxnits
	@echo "Installed $(PREFIX)/bin/maxnits -> $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"

uninstall:
	rm -f $(PREFIX)/bin/maxnits

clean:
	rm -rf .build dist
