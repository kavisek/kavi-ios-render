PROJECT := render/render.xcodeproj
SCHEME := render
CONFIGURATION := Debug
DESTINATION := platform=macOS

TAP := kavisek/render
TAP_URL := git@github.com:kavisek/kavi-ios-render.git
FORMULA := $(TAP)/render
RELEASE_APP := $(CURDIR)/build-release/Build/Products/Release/render.app

# Simulators for the iOS / iPadOS targets; override e.g. `make start-ios IOS_SIM="iPhone 18 Pro"`.
IOS_SIM ?= iPhone 17
IPAD_SIM ?= iPad Pro 13-inch (M5)
BUNDLE_ID := kavi.render
SIM_DERIVED_DATA := $(CURDIR)/build-sim
SIM_APP := $(SIM_DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/render.app

.PHONY: start start-ios start-ipad add-video build test build-release clean install

# Builds for macOS and opens the resulting .app directly (no simulator).
start: build
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' -showBuildSettings 2>/dev/null | \
		awk -F' = ' '/ BUILT_PRODUCTS_DIR /{bp=$$2} / FULL_PRODUCT_NAME /{fn=$$2} END{print bp"/"fn}'); \
	echo "Opening $$APP_PATH..."; \
	open "$$APP_PATH"

# Builds for the iOS Simulator, boots the device, installs and launches.
start-ios:
	@$(MAKE) --no-print-directory run-sim SIM="$(IOS_SIM)"

start-ipad:
	@$(MAKE) --no-print-directory run-sim SIM="$(IPAD_SIM)"

run-sim:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath $(SIM_DERIVED_DATA) build
	xcrun simctl bootstatus "$(SIM)" -b
	@open -a Simulator 2>/dev/null || echo "Open the Simulator app to see the device."
	xcrun simctl install "$(SIM)" "$(SIM_APP)"
	xcrun simctl launch "$(SIM)" $(BUNDLE_ID)

# Adds a video to a simulator's Photos library so the app's Photos button
# can open it: `make add-video VIDEO=~/Movies/clip.mp4 [SIM="iPad Pro 13-inch (M5)"]`.
SIM ?= $(IOS_SIM)
add-video:
	@test -n "$(VIDEO)" || (echo "usage: make add-video VIDEO=path/to/video.mp4 [SIM=\"$(IOS_SIM)\"]" && exit 1)
	xcrun simctl bootstatus "$(SIM)" -b
	xcrun simctl addmedia "$(SIM)" "$(VIDEO)"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' build

# Runs the unit tests (model, CLI, view rendering) and the end-to-end UI
# tests, which drive the real open panel to load a generated .mp4.
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' test

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
# prefix, rather than building from source itself. Re-taps and reinstalls
# each run so the freshly built app and the latest formula always win.
install: build-release
	@echo "$(RELEASE_APP)" > /tmp/kavi-render-prebuilt-app-path
	-brew untap $(TAP) 2>/dev/null
	brew tap $(TAP) $(TAP_URL)
	-brew uninstall $(FORMULA) 2>/dev/null
	brew install --HEAD --build-from-source --yes $(FORMULA)
