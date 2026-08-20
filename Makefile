SCHEME := MailGent
PROJECT := MailGent.xcodeproj
DESTINATION := platform=macOS,arch=arm64
DERIVED_DATA := .build/DerivedData

.DEFAULT_GOAL := test

.PHONY: generate test run xcode prototype-accounts prototype-draft

generate:
	xcodegen generate

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES test

xcode: generate
	open $(PROJECT)

run: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES build
	@killall MailGent >/dev/null 2>&1 || true
	@sleep 0.2
	@echo "Menu bar app — no Dock icon. Click the tray icon, then Open Companion."
	open '$(DERIVED_DATA)/Build/Products/Debug/MailGent.app'

prototype-draft: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES build
	@killall MailGent >/dev/null 2>&1 || true
	@sleep 0.2
	@echo "PROTOTYPE draft outbound — tray icon → Open draft prototype. Switch A/B at bottom."
	open '$(DERIVED_DATA)/Build/Products/Debug/MailGent.app'

prototype-accounts: generate
	xcodebuild -project $(PROJECT) -scheme AccountIdentityPrototype -destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES build
	@echo "PROTOTYPE — account names from Accounts4.sqlite or header inference"
	DYLD_FRAMEWORK_PATH='$(DERIVED_DATA)/Build/Products/Debug' '$(DERIVED_DATA)/Build/Products/Debug/AccountIdentityPrototype'
