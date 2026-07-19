APP_NAME = Overbright
BUILD_DIR = .build/release
APP_BUNDLE = dist/$(APP_NAME).app

.PHONY: build app run clean

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

clean:
	rm -rf .build dist
