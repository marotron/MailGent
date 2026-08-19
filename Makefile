SCHEME := MailGent
PROJECT := MailGent.xcodeproj
DESTINATION := platform=macOS,arch=arm64
DERIVED_DATA := .build/DerivedData

.DEFAULT_GOAL := test

.PHONY: generate test run

generate:
	xcodegen generate

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES test

run: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES build
	@echo "Menu bar app — no Dock icon. Click the tray icon, then Open Companion. Arrow keys flip A/B/C."
	open '$(DERIVED_DATA)/Build/Products/Debug/MailGent.app'
