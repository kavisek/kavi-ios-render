PROJECT := render/render.xcodeproj
SCHEME := render
CONFIGURATION := Debug
DESTINATION := generic/platform=iOS Simulator
SIMULATOR_NAME := iPhone 17

.PHONY: start build clean

start: build
	@echo "Booting simulator '$(SIMULATOR_NAME)'..."
	@xcrun simctl boot "$(SIMULATOR_NAME)" 2>/dev/null || true
	@open -a Simulator
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-sdk iphonesimulator -showBuildSettings 2>/dev/null | \
		awk -F' = ' '/ BUILT_PRODUCTS_DIR /{bp=$$2} / FULL_PRODUCT_NAME /{fn=$$2} END{print bp"/"fn}'); \
	echo "Installing $$APP_PATH..."; \
	xcrun simctl install "$(SIMULATOR_NAME)" "$$APP_PATH"; \
	BUNDLE_ID=$$(defaults read "$$APP_PATH/Info" CFBundleIdentifier); \
	echo "Launching $$BUNDLE_ID..."; \
	xcrun simctl launch "$(SIMULATOR_NAME)" "$$BUNDLE_ID"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-sdk iphonesimulator build

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) clean
