PROJECT = jwm.xcodeproj
BUILD_DIR = build
APP_NAME = jWM

INSTALLED_BUNDLE_ID = com.giovanniberi93.jwm
TEST_BUNDLE_ID = $(INSTALLED_BUNDLE_ID).debug
TEST_NAME = jwm-debug
TEST_BUILD_DIR = $(BUILD_DIR)/test-bundle

.PHONY: build
build:
	xcodebuild -project $(PROJECT) -scheme jwm -configuration Debug \
		-derivedDataPath $(BUILD_DIR) build

.PHONY: build-test
build-test:
	xcodebuild -project $(PROJECT) -scheme jwm -configuration Debug \
		-derivedDataPath $(TEST_BUILD_DIR) \
		PRODUCT_BUNDLE_IDENTIFIER=$(TEST_BUNDLE_ID) \
		PRODUCT_NAME=$(TEST_NAME) \
		INFOPLIST_KEY_CFBundleDisplayName=$(TEST_NAME) \
		build

.PHONY: dev
dev: build
	$(BUILD_DIR)/Build/Products/Debug/jwm.app/Contents/MacOS/jwm

.PHONY: reset-tutorial
reset-tutorial:
	defaults delete $(INSTALLED_BUNDLE_ID) hasCompletedFirstRunTutorial 2>/dev/null || true

.PHONY: install
install: build reset-accessibility-permissions
	rm -rf /Applications/$(APP_NAME).app
	ditto $(BUILD_DIR)/Build/Products/Debug/jwm.app /Applications/$(APP_NAME).app

.PHONY: kill
kill:
	pkill -x jwm || true

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
	xcodebuild -project $(PROJECT) -scheme jwmTests -configuration Debug -derivedDataPath $(BUILD_DIR) test

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
	@SRC="$$HOME/Library/Application Support/jwm/usage-stats.json"; \
	if [ -f "$$SRC" ]; then \
		printf 'window.JWM_DATA = ' > scripts/usage-stats.js; \
		cat "$$SRC" >> scripts/usage-stats.js; \
		printf ';\n' >> scripts/usage-stats.js; \
	else \
		echo 'window.JWM_DATA = {"hourly":{}};' > scripts/usage-stats.js; \
	fi
	@open scripts/viz.html

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -rf ~/Library/Developer/Xcode/DerivedData/jwm-*
