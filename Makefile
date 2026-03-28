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

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -rf ~/Library/Developer/Xcode/DerivedData/$(SCHEME)-*
