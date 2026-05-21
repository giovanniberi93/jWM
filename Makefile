PROJECT = janzowm.xcodeproj
BUILD_DIR = build
APP_NAME = janzoWM

INSTALLED_BUNDLE_ID = com.giovanniberi93.janzowm
TEST_BUNDLE_ID = $(INSTALLED_BUNDLE_ID).debug
TEST_NAME = janzowm-debug
TEST_BUILD_DIR = $(BUILD_DIR)/test-bundle

.PHONY: build
build:
	xcodebuild -project $(PROJECT) -scheme janzowm -configuration Debug \
		-derivedDataPath $(BUILD_DIR) build

.PHONY: release
release:
	xcodebuild -project $(PROJECT) -scheme janzowm -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

.PHONY: build-test
build-test:
	xcodebuild -project $(PROJECT) -scheme janzowm -configuration Debug \
		-derivedDataPath $(TEST_BUILD_DIR) \
		PRODUCT_BUNDLE_IDENTIFIER=$(TEST_BUNDLE_ID) \
		PRODUCT_NAME=$(TEST_NAME) \
		INFOPLIST_KEY_CFBundleDisplayName=$(TEST_NAME) \
		build

.PHONY: dev
dev: build
	$(BUILD_DIR)/Build/Products/Debug/janzowm.app/Contents/MacOS/janzowm

.PHONY: reset-tutorial
reset-tutorial:
	defaults delete $(INSTALLED_BUNDLE_ID) hasCompletedFirstRunTutorial 2>/dev/null || true

.PHONY: reset-prefs
reset-prefs: kill
	defaults delete $(INSTALLED_BUNDLE_ID) 2>/dev/null || true
	rm -f ~/Library/Preferences/$(INSTALLED_BUNDLE_ID).plist

.PHONY: install
install: build reset-accessibility-permissions
	rm -rf /Applications/$(APP_NAME).app
	ditto $(BUILD_DIR)/Build/Products/Debug/janzowm.app /Applications/$(APP_NAME).app

.PHONY: installed-app-logs
installed-app-logs:
	log stream --style compact --level debug --predicate 'subsystem == "$(INSTALLED_BUNDLE_ID)"'

.PHONY: kill
kill:
	pkill -x janzowm || true

.PHONY: reset-accessibility-permissions
reset-accessibility-permissions: kill
	@if command -v tccutil >/dev/null 2>&1; then \
		tccutil reset Accessibility $(INSTALLED_BUNDLE_ID); \
	else \
		echo "WARNING: tccutil not found, skipping TCC reset"; \
	fi

.PHONY: uninstall
uninstall: kill
	rm -rf /Applications/$(APP_NAME).app

.PHONY: test
test:
	xcodebuild -project $(PROJECT) -scheme janzowmTests -configuration Debug -derivedDataPath $(BUILD_DIR) test

.PHONY: build-test-stubs
build-test-stubs:
	./integration-tests/stubs/build.sh

.PHONY: test-integration
test-integration: build-test build-test-stubs
	./integration-tests/test-integration.sh $(TEST)

.PHONY: test-all
test-all: test test-integration

.PHONY: stats
stats:
	@SRC="$$HOME/Library/Application Support/janzowm/usage-stats.json"; \
	if [ -f "$$SRC" ]; then \
		printf 'window.JANZOWM_DATA = ' > scripts/usage-stats.js; \
		cat "$$SRC" >> scripts/usage-stats.js; \
		printf ';\n' >> scripts/usage-stats.js; \
	else \
		echo 'window.JANZOWM_DATA = {"hourly":{}};' > scripts/usage-stats.js; \
	fi
	@open scripts/viz.html

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -rf ~/Library/Developer/Xcode/DerivedData/janzowm-*
