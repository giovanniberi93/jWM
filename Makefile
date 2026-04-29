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

.PHONY: install
install: build reset-accessibility-permissions
	rm -rf /Applications/$(APP_NAME).app
	ditto $(BUILD_DIR)/Build/Products/Debug/jwm.app /Applications/$(APP_NAME).app

.PHONY: reset-accessibility-permissions
reset-accessibility-permissions:
	@if command -v tccutil >/dev/null 2>&1; then \
		pkill -x jwm || true; \
		tccutil reset Accessibility $(INSTALLED_BUNDLE_ID); \
	else \
		echo "WARNING: tccutil not found, skipping TCC reset"; \
	fi

.PHONY: uninstall
uninstall:
	pkill -x jwm || true
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

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -rf ~/Library/Developer/Xcode/DerivedData/jwm-*
