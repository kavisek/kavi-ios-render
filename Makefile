PROJECT := render/render.xcodeproj
SCHEME := render
CONFIGURATION := Debug
DESTINATION := generic/platform=iOS Simulator
SIMULATOR_NAME := iPhone 17

TAP := kavisek/render
TAP_URL := git@github.com:kavisek/kavi-ios-render.git
FORMULA := $(TAP)/render
RELEASE_APP := $(CURDIR)/build-release/Build/Products/Release/render.app

.PHONY: start build build-release clean install

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

# Builds the macOS Release .app directly (unsandboxed). Homebrew's own build
# sandbox can't compile this project itself: Xcode's Swift macro plugin server
# (used by SwiftUI's #Preview macro) tries to sandbox itself too, and macOS
# refuses that nested sandbox_apply. So Homebrew never runs xcodebuild here —
# it just packages a build made outside of it.
build-release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath build-release CODE_SIGNING_ALLOWED=NO build

# Installs the macOS build of this app via Homebrew. Taps this private repo
# over SSH (requires your SSH key to already have access to $(TAP_URL)) and
# has the formula copy the app built by `build-release` into the Homebrew
# prefix, rather than building from source itself.
install: build-release
	brew tap $(TAP) $(TAP_URL)
	@echo "$(RELEASE_APP)" > /tmp/kavi-render-prebuilt-app-path
	brew install --HEAD --build-from-source $(FORMULA)
