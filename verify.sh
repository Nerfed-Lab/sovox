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
for s in shortcuts ms-outlook chatgpt claude; do
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

echo "== E48 to E60 bridge setup =="
# E48. Letters only, in code and in every displayed string.
if grep -rn 'Sovox Bridge' --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ | grep -qv 'Tests'; then
  note "E48 no old bridge name in app code" "FAIL"; fail=1
else
  note "E48 no old bridge name in app code" "PASS"
fi
if [ "$(grep -A4 'var shortcutName' Sovox/Model/OutputTypes.swift | grep -oE 'return "[^"]*"' | grep -vcE 'return "[A-Za-z]+"')" = "0" ]; then
  note "E48 shortcut names are letters only" "PASS"; else note "E48 shortcut names" "FAIL"; fail=1; fi

# E49. Smart punctuation cannot reach a string the user has to reproduce.
smart=$(grep -rlP '[\x{2013}\x{2014}\x{2018}\x{2019}\x{201C}\x{201D}]' --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$smart" = "0" ]; then note "E49 no en dash, em dash or smart quotes" "PASS"; else
  note "E49 smart punctuation present" "FAIL ($smart)"
  grep -rlP '[\x{2013}\x{2014}\x{2018}\x{2019}\x{201C}\x{201D}]' --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ | head -3 | sed 's/^/    /'
  fail=1
fi

# E50 and E51. Documents root, and never deleted as cleanup.
if grep -q 'documents.appendingPathComponent("sovox-pending.txt")' Sovox/Model/RecordingPaths.swift; then
  note "E50 pending file in the Documents root" "PASS"; else note "E50 pending file path" "FAIL"; fail=1; fi
must_be_absent "E51 pending file never deleted"    "removeItem\(at: RecordingPaths.pendingPromptFile\)"

# E52. Three actions. Nothing in the recipe asks for a callback action.
if grep -q 'sovox://done' Sovox/Handoff/BridgeShortcutRecipe.swift; then
  note "E52 recipe has no callback action" "FAIL"; fail=1
else
  note "E52 recipe has no callback action" "PASS"
fi

# E53. The date fallback is wired to becoming active.
if grep -q 'collectIfResultWaiting' Sovox/SovoxApp.swift; then
  note "E53 result date fallback on activation" "PASS"; else note "E53 fallback" "FAIL"; fail=1; fi

# E57. Preparing a manual test must not invoke anything.
if awk '/func prepareManualTest/,/^    }/' Sovox/Handoff/HandoffCoordinator.swift | grep -q 'UIApplication.shared.open'; then
  note "E57 manual test does not invoke" "FAIL"; fail=1
else
  note "E57 manual test does not invoke" "PASS"
fi

# E59. The migration card exists and is presented.
if [ -f Sovox/UI/BridgeMigrationView.swift ] && grep -q 'BridgeMigrationView' Sovox/UI/RootView.swift; then
  note "E59 migration card present" "PASS"; else note "E59 migration card" "FAIL"; fail=1; fi

echo "== E48 to E73 phases 15 to 18 =="
# E51. The wizard walks one bridge per run, so the page count is four.
grep -q "private let lastStep = 3" Sovox/UI/SetupWizardView.swift \
  && note "E51 wizard is four pages, dots follow" "PASS" || { note "E51 page count" "FAIL"; fail=1; }

# E50. Never both bridges in one run.
if grep -q "bridgeStep(for: .chatgpt).tag" Sovox/UI/SetupWizardView.swift \
   || grep -q "bridgeStep(for: .claude).tag" Sovox/UI/SetupWizardView.swift; then
  note "E50 one bridge page per run" "FAIL"; fail=1
else
  note "E50 one bridge page per run" "PASS"
fi

# E68. The model selector is gone from Transcript Ready.
if grep -q 'Picker("Destination"' Sovox/UI/OutputSelectionView.swift; then
  note "E68 no model selector on Transcript Ready" "FAIL"; fail=1
else
  note "E68 no model selector on Transcript Ready" "PASS"
fi

# E66. Phase 16 copy, exactly.
grep -q 'blurb: "Transcripts are sent to this email."' Sovox/UI/SetupWizardView.swift \
  && grep -q 'blurb: "Optional. For quick access when you need it."' Sovox/UI/SetupWizardView.swift \
  && note "E66 wizard copy matches Phase 16" "PASS" || { note "E66 wizard copy" "FAIL"; fail=1; }

# E67. No implementation detail in user copy.
if grep -nE '"[^"]*(public API|deep link|deep-link|has to be done by hand)[^"]*"' Sovox/UI/*.swift | grep -q .; then
  note "E67 no API talk in user copy" "FAIL"; fail=1
else
  note "E67 no API talk in user copy" "PASS"
fi

# E69. empty is its own state, and only a failure leaves a gap marker.
grep -q "case empty" Sovox/Model/RecordingSession.swift \
  && grep -q "if record.state.isFailure {" Sovox/Model/TranscriptStitcher.swift \
  && note "E69 empty and failed are distinct" "PASS" || { note "E69 empty vs failed" "FAIL"; fail=1; }

# E72. The retroactive sweep is keyed, so it runs once.
grep -q "sovox.discardSweepV18" Sovox/Model/RecorderController.swift \
  && note "E72 retroactive sweep runs once" "PASS" || { note "E72 sweep" "FAIL"; fail=1; }

# E73. No user visible string from the old name.
# A UserDefaults key is neither user visible nor a callback, and renaming
# sovox.migratedFromCapture would re-run a migration that has already run.
capture_hits() {
  grep -rnE '"[^"]*Capture[^"]*"' --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ \
    | grep -vE ':[0-9]+: *(//|///)' | grep -v '"sovox\.'
}
if capture_hits | grep -q .; then
  note "E73 no Capture in user strings" "FAIL"; fail=1
  capture_hits | head -3 | sed 's/^/    /'
else
  note "E73 no Capture in user strings" "PASS"
fi

echo "== E75 on device recognition =="
# Server recognition is prohibited. Every SFSpeechRecognitionRequest must set
# the flag true, and the assertion has to sit next to it.
bad=$(grep -rn "requiresOnDeviceRecognition = false" --include='*.swift' Sovox/ SovoxShared/ | wc -l | tr -d ' ')
if [ "$bad" = "0" ] && grep -q "precondition(request.requiresOnDeviceRecognition" Sovox/Transcription/SegmentTranscriber.swift; then
  note "E75 on device only, asserted" "PASS"
else
  note "E75 on device recognition" "FAIL"; fail=1
fi

echo "== E74 to E95 phase 19 =="
# E81. Silence gaps and clamps, not a fixed clock window.
grep -q "silenceGap: TimeInterval = 0.4" Sovox/Transcription/TranscriptMerge.swift \
  && grep -q "minimumWindow: TimeInterval = 3" Sovox/Transcription/TranscriptMerge.swift \
  && grep -q "maximumWindow: TimeInterval = 20" Sovox/Transcription/TranscriptMerge.swift \
  && note "E81 pause aligned windows, clamped" "PASS" || { note "E81 windows" "FAIL"; fail=1; }

# E82. Nothing in the merge may score, classify or detect a language.
if grep -nE "score|confidence|classif|spellCheck|dominantLanguage|NLLanguage" Sovox/Transcription/TranscriptMerge.swift | grep -vE "^\s*[0-9]+: *(//|///)" | grep -q .; then
  note "E82 no heuristics in the merge" "FAIL"; fail=1
else
  note "E82 no heuristics in the merge" "PASS"
fi
must_be_absent "E82 no language detection anywhere"  "NLLanguageRecognizer|dominantLanguage"

# E86 and E88. The threshold, and stage two without the preamble.
grep -q "threshold = 80_000" Sovox/Handoff/StagedGeneration.swift \
  && note "E86 two stage above 80,000" "PASS" || { note "E86 threshold" "FAIL"; fail=1; }
if awk '/Stage 2/,/purpose: .notes/' Sovox/Handoff/HandoffCoordinator.swift | grep -q "merged: false"; then
  note "E88 stage two omits the preamble" "PASS"
else
  note "E88 stage two preamble" "FAIL"; fail=1
fi

# E83. Devanagari belongs in the prompt only. The merged form must not be what
# History, the clipboard or the email read.
if grep -rn "mergedTranscript" Sovox/UI/ | grep -v MergePreviewView | grep -q .; then
  note "E83 merged text stays out of the UI" "FAIL"; fail=1
  grep -rn "mergedTranscript" Sovox/UI/ | grep -v MergePreviewView | head -3 | sed 's/^/    /'
else
  note "E83 merged text stays out of the UI" "PASS"
fi
if grep -n "mergedTranscript\|secondaryText" Sovox/Handoff/OutlookComposer.swift | grep -q .; then
  note "E83 no second reading in the email" "FAIL"; fail=1
else
  note "E83 no second reading in the email" "PASS"
fi

# E80. The canonical readers must never touch the secondary.
if grep -n "secondaryText\|mergedTranscript" Sovox/Handoff/AskPromptBuilder.swift Sovox/Model/TodoStore.swift | grep -q .; then
  note "E80 primary canonical for Ask and to-dos" "FAIL"; fail=1
else
  note "E80 primary canonical for Ask and to-dos" "PASS"
fi

echo "== E10 colour tokens =="
stray=$(grep -rlE "0x[0-9A-Fa-f]{6}" --include='*.swift' Sovox/ SovoxShared/ SovoxWidget/ 2>/dev/null \
        | grep -v "Theme.swift\|WidgetPalette.swift" | wc -l | tr -d ' ')
if [ "$stray" = "0" ]; then note "E10 no hex outside token files" "PASS"; else note "E10 hex outside tokens" "FAIL ($stray)"; fail=1; fi

echo
if [ $fail = 0 ]; then echo "VERIFICATION PASSED"; else echo "VERIFICATION FAILED"; fi
exit $fail
