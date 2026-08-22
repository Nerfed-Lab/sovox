#!/bin/bash
# Sovox verification suite.
#
# Source level checks live here rather than in XCTest, because the test host
# runs sandboxed in the simulator and cannot read the source tree. A test that
# reads its own repo silently passes on an empty string.
set -uo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

fail=0
note() { printf "%-46s %s\n" "$1" "$2"; }
# Comment lines are excluded. Several of these names appear in comments that
# explain why the API is not used, and banning the explanation would be silly.
must_be_absent() {
  local label="$1"; shift
  local hits
  hits=$(grep -rnE "$1" --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ 2>/dev/null \
         | grep -vE ':[0-9]+: *(//|///|\*)' \
         | grep -vE ':[0-9]+:[^"]*//.*' \
         | wc -l | tr -d ' ')
  if [ "$hits" = "0" ]; then note "$label" "PASS"; else
    note "$label" "FAIL ($hits)"
    grep -rnE "$1" --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ 2>/dev/null \
      | grep -vE ':[0-9]+: *(//|///|\*)' | grep -vE ':[0-9]+:[^"]*//.*' | head -3 | sed 's/^/    /'
    fail=1
  fi
}

echo "== parse =="
if find . -name '*.swift' -not -path './build/*' | xargs swiftc -parse 2>&1 | grep -q "error:"; then
  note "swiftc -parse" "FAIL"; fail=1
else
  note "swiftc -parse ($(find . -name '*.swift' -not -path './build/*' | wc -l | tr -d ' ') files)" "PASS"
fi

echo "== plists =="
if [ "$(plutil -lint Sovox/Info.plist SovoxWidget/Info.plist Sovox/Sovox.entitlements \
        SovoxWidget/SovoxWidget.entitlements Sovox/PrivacyInfo.xcprivacy ExportOptions.plist \
        | grep -c OK)" = "6" ]; then note "plutil -lint" "PASS"; else note "plutil -lint" "FAIL"; fail=1; fi

echo "== project =="
if [ "$(xcodebuild -list -project Sovox.xcodeproj 2>&1 | grep -cE '^        (Sovox|SovoxWidget|SovoxTests)$')" -ge 3 ]; then
  note "pbxproj resolves 3 targets" "PASS"; else note "pbxproj" "FAIL"; fail=1; fi

echo "== D1 to D28 =="
must_be_absent "D1  no AVAudioRecorder"            "AVAudioRecorder\("
must_be_absent "D5  no beginBackgroundTask"        "beginBackgroundTask"
must_be_absent "D6  no Timer driven clock"         "Timer\(|Timer\.scheduled"
must_be_absent "D23 no urlQueryAllowed"            "\.urlQueryAllowed"
must_be_absent "D25 no network or third party"     "URLSession|import Network|http"
must_be_absent "D25 no EventKit or Contacts"       "EventKit|CNContact|import Contacts"

echo "== D26 Info.plist keys =="
missing=0
for k in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription UIBackgroundModes \
         UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace CFBundleURLSchemes \
         LSApplicationQueriesSchemes NSSupportsLiveActivities NSAppTransportSecurity CFBundleIconName; do
  grep -q "<key>$k</key>" Sovox/Info.plist || { echo "  MISSING $k"; missing=1; }
done
if [ $missing = 0 ]; then note "all 10 keys present" "PASS"; else note "Info.plist keys" "FAIL"; fail=1; fi

echo "== hard constraints =="
# The key being present says nothing about what it says. Every one of these
# must read false, or the app can reach the network after all.
ats_fail=0
for k in NSAllowsArbitraryLoads NSAllowsArbitraryLoadsForMedia NSAllowsArbitraryLoadsInWebContent NSAllowsLocalNetworking; do
  v=$(plutil -extract NSAppTransportSecurity.$k raw Sovox/Info.plist 2>/dev/null || echo absent)
  case "$v" in false|absent) ;; *) echo "  $k is $v"; ats_fail=1 ;; esac
done
if [ "$(plutil -extract NSAppTransportSecurity.NSExceptionDomains json -o - Sovox/Info.plist 2>/dev/null)" != "{}" ]; then
  echo "  NSExceptionDomains is not empty"; ats_fail=1
fi
if [ $ats_fail = 0 ]; then note "ATS blocks every outbound connection" "PASS"; else note "ATS" "FAIL"; fail=1; fi

# Their presence alone triggers the corporate review the user has to avoid, so
# absence is the requirement, not merely never calling the framework.
forbidden=0
for k in NSCalendarsUsageDescription NSCalendarsFullAccessUsageDescription \
         NSContactsUsageDescription NSRemindersUsageDescription \
         NSRemindersFullAccessUsageDescription NSPhotoLibraryUsageDescription \
         NSLocationWhenInUseUsageDescription NSUserTrackingUsageDescription; do
  for f in Sovox/Info.plist SovoxWidget/Info.plist; do
    grep -q "<key>$k</key>" "$f" && { echo "  $k present in $f"; forbidden=1; }
  done
done
grep -q "aps-environment" Sovox/Sovox.entitlements SovoxWidget/SovoxWidget.entitlements && { echo "  push entitlement present"; forbidden=1; }
if [ $forbidden = 0 ]; then note "no permission keys that trigger review" "PASS"; else note "forbidden keys" "FAIL"; fail=1; fi

# The rename broke the callback once by leaving a handler on the old scheme.
# These pin the three strings the hand off depends on.
scheme_fail=0
[ "$(plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes json -o - Sovox/Info.plist 2>/dev/null)" = '["sovox"]' ] \
  || { echo "  CFBundleURLSchemes is not exactly [sovox]"; scheme_fail=1; }
for s in shortcuts ms-outlook; do
  plutil -extract LSApplicationQueriesSchemes json -o - Sovox/Info.plist 2>/dev/null | grep -q "\"$s\"" \
    || { echo "  LSApplicationQueriesSchemes missing $s"; scheme_fail=1; }
done
if [ $scheme_fail = 0 ]; then note "URL schemes pinned" "PASS"; else note "URL schemes" "FAIL"; fail=1; fi

# Stated by the user as unchangeable: a new identifier means a new App Store
# Connect record and an app that can no longer read the container it shipped.
if [ "$(grep -c 'PRODUCT_BUNDLE_IDENTIFIER = com.rishabh.capturenotes;' Sovox.xcodeproj/project.pbxproj)" -ge 1 ] \
   && [ "$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*;' Sovox.xcodeproj/project.pbxproj | grep -vc 'com.rishabh.capturenotes')" = "0" ]; then
  note "bundle identifier unchanged" "PASS"
else
  note "bundle identifier" "FAIL"; fail=1
fi

echo "== E37, E41, E42 capture path =="
must_be_absent "E37 no voice processing"           "setVoiceProcessingEnabled|isVoiceProcessingEnabled"
must_be_absent "E37 no near field session mode"    "\.voiceChat|\.videoChat|\.gameChat|\.measurement"
must_be_absent "E42 no custom vocabulary"          "contextualStrings|customLanguageModel"
if find . \( -name '*.mlmodel*' -o -name '*.ggml*' \) | grep -q .; then
  note "E41 no bundled speech model" "FAIL"; fail=1; else note "E41 no bundled speech model" "PASS"; fi

echo "== E10 colour tokens =="
stray=$(grep -rlE "0x[0-9A-Fa-f]{6}" --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ 2>/dev/null \
        | grep -v "Theme.swift\|WidgetPalette.swift" | wc -l | tr -d ' ')
if [ "$stray" = "0" ]; then note "E10 no hex outside token files" "PASS"; else note "E10 hex outside tokens" "FAIL ($stray)"; fail=1; fi

echo
if [ $fail = 0 ]; then echo "VERIFICATION PASSED"; else echo "VERIFICATION FAILED"; fi
exit $fail
