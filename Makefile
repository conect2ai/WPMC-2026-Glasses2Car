CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_TESTLIB := /Library/Developer/CommandLineTools/Library/Developer/usr/lib

# Runs today with Command Line Tools only (no Xcode needed):
# deterministic tests for the Conect2AI API client and trip formatter.
test-core:
	cd Conect2AICore && swift test \
		-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
		-Xlinker -F$(CLT_FRAMEWORKS) \
		-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) \
		-Xlinker -rpath -Xlinker $(CLT_TESTLIB)

# Requires full Xcode (for the iOS SDK + Meta Wearables DAT package).
project:
	xcodegen generate

# Picks the first available iPhone simulator; override with SIM_NAME="iPhone 17".
SIM_NAME ?= $(shell xcrun simctl list devices available 2>/dev/null | grep -oE 'iPhone [0-9][0-9A-Za-z ]*[0-9A-Za-z]' | head -1)

test-ios: project
	@test -n "$(SIM_NAME)" || { echo "Nenhum simulador de iPhone encontrado. Abra o Xcode uma vez para instalar a plataforma iOS."; exit 1; }
	xcodebuild test \
		-project RayBanTripApp.xcodeproj \
		-scheme RayBanTripApp \
		-destination 'platform=iOS Simulator,name=$(SIM_NAME)'

# One-time setup after installing Xcode from the App Store.
xcode-setup:
	sudo xcode-select -s /Applications/Xcode.app
	sudo xcodebuild -license accept
	xcodebuild -downloadPlatform iOS

.PHONY: test-core project test-ios xcode-setup
