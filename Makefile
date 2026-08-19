SCHEME := MailGent
PROJECT := MailGent.xcodeproj
DESTINATION := platform=macOS,arch=arm64

.DEFAULT_GOAL := test

.PHONY: generate test

generate:
	xcodegen generate

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES test
