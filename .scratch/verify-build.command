#!/bin/bash
cd "$(dirname "$0")/.."
set -euo pipefail
xcodegen generate
rm -rf /tmp/MailGent-VerifyDD
if xcodebuild -project MailGent.xcodeproj -scheme MailGent \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/MailGent-VerifyDD \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES build \
  2>&1 | tee /tmp/mailgent-verify-build.log | rg "error:|BUILD SUCCEEDED|BUILD FAILED" | grep -v ObservableMacro | grep -v PreviewsMacros | grep -v SimService | head -40
then
  echo OK > /tmp/mailgent-verify-done.txt
else
  echo FAIL > /tmp/mailgent-verify-done.txt
fi
echo EXIT:$? >> /tmp/mailgent-verify-done.txt
# Keep window open briefly for visibility
sleep 2
