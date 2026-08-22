#!/bin/bash
# Archive and upload to TestFlight.
#
# The archive is deliberately built unsigned and signing happens at export.
# Xcode's automatic signing provisions an archive for Development, and Apple
# refuses to issue a Development profile to a team with no registered devices,
# so a signed archive fails on a Mac that has never had an iPhone plugged in.
# Exporting with -allowProvisioningUpdates creates the Apple Distribution
# certificate and the App Store profiles on demand, neither of which needs a
# device.
set -euo pipefail
cd "$(dirname "$0")"



ARCHIVE=build/Sovox.xcarchive
rm -rf "$ARCHIVE" build/upload

echo "==> Archiving"
xcodebuild archive \
  -project Sovox.xcodeproj \
  -scheme Sovox \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

# App Store Connect API key, if configured. This removes Xcode's interactive
# account session from the loop, which is what fails from a terminal with
# "Failed to Use Accounts" even when Xcode itself is signed in.
AUTH=()
if [ -f asc-key.env ]; then
  # shellcheck disable=SC1091
  . ./asc-key.env
  KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  if [ -f "$KEY_FILE" ]; then
    AUTH=(-authenticationKeyPath "$KEY_FILE"
          -authenticationKeyID "$ASC_KEY_ID"
          -authenticationKeyIssuerID "$ASC_ISSUER_ID")
    echo "==> Using App Store Connect API key $ASC_KEY_ID"
  else
    echo "asc-key.env names key $ASC_KEY_ID but $KEY_FILE is missing."
    exit 1
  fi
else
  echo "==> No asc-key.env, falling back to the Xcode account session"
fi

# ExportOptions.plist ships with a placeholder team so the repo carries no
# account identifiers. Substituted into a temp copy at upload time.
OPTS=ExportOptions.plist
if grep -q 'ASC_TEAM_ID' ExportOptions.plist; then
  if [ -z "${ASC_TEAM_ID:-}" ]; then
    echo "Set ASC_TEAM_ID in asc-key.env (your 10 character Apple team id)."
    exit 1
  fi
  OPTS=build/ExportOptions.resolved.plist
  mkdir -p build
  sed "s/\$(ASC_TEAM_ID)/$ASC_TEAM_ID/" ExportOptions.plist > "$OPTS"
fi

echo "==> Signing and uploading"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTS" \
  -exportPath build/upload \
  "${AUTH[@]}" \
  -allowProvisioningUpdates \
  | grep -Ei "error|Upload succeeded|EXPORT (SUCCEEDED|FAILED)"

echo
echo "Uploaded. Processing takes five to fifteen minutes."
echo "App Store Connect, TestFlight, attach the new build to the internal group."
