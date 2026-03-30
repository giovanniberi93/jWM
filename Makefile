SCHEME = jwm
PROJECT = jwm.xcodeproj
BUILD_DIR = build

.PHONY: build
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(BUILD_DIR) build

.PHONY: run
run: build
	open $(BUILD_DIR)/Build/Products/Debug/$(SCHEME).app

.PHONY: dev
dev: build
	$(BUILD_DIR)/Build/Products/Debug/$(SCHEME).app/Contents/MacOS/$(SCHEME)

APP_NAME = jWM

.PHONY: install
install: build
	rm -rf /Applications/$(APP_NAME).app
	ditto $(BUILD_DIR)/Build/Products/Debug/$(SCHEME).app /Applications/$(APP_NAME).app
	# TCC caches stale code signatures after rebuild, causing Accessibility to silently fail
	@if command -v tccutil >/dev/null 2>&1; then \
		tccutil reset Accessibility giober.jwm; \
	else \
		echo "WARNING: tccutil not found, skipping TCC reset"; \
	fi

.PHONY: uninstall
uninstall:
	pkill -x jwm || true
	rm -rf /Applications/$(APP_NAME).app

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -rf ~/Library/Developer/Xcode/DerivedData/$(SCHEME)-*
