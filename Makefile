PROJECT := render/render.xcodeproj
SCHEME := render
CONFIGURATION := Debug
DESTINATION := generic/platform=iOS Simulator
SIMULATOR_NAME := iPhone 17

TAP := kavisek/render
TAP_URL := git@github.com:kavisek/kavi-ios-render.git
FORMULA := $(TAP)/render

.PHONY: start build clean install

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

# Installs the macOS build of this app via Homebrew, tapping and building from
# source straight off this private repo over SSH. Requires your SSH key to
# already have access to $(TAP_URL).
install:
	brew tap $(TAP) $(TAP_URL)
	brew install --HEAD --build-from-source $(FORMULA)
