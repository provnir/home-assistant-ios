#!/usr/bin/env bash
# One Khala archive + App Store export on macOS (the only part of the pipeline that needs
# Xcode). Everything checkable without Xcode already ran on Ubuntu in `prepare`.
# Written for macOS's /bin/bash 3.2: no empty-array expansion under `set -u`.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SHIP="$ROOT/Configuration/Khala/khala_ship.py"
: "${APPLE_TEAM_ID:?missing vars.APPLE_TEAM_ID}" "${BUNDLE_ID_PREFIX:?}" "${BUNDLE_ID:?}" \
  "${SIGNING:?}" "${SHORT_VERSION:?}" "${BUILD_NUMBER:?}" "${RUNNER_TEMP:?}"
cd "$ROOT"

python3 "$SHIP" apply --team "$APPLE_TEAM_ID" --prefix "$BUNDLE_ID_PREFIX"
python3 "$SHIP" xcconfig --mode "$SIGNING" --team "$APPLE_TEAM_ID" --version "$SHORT_VERSION" \
    --build "$BUILD_NUMBER" --profile "${PROFILE_NAME:-}" --out "$RUNNER_TEMP/khala.xcconfig"
python3 "$SHIP" export-options --mode "$SIGNING" --team "$APPLE_TEAM_ID" --bundle-id "$BUNDLE_ID" \
    --profile "${PROFILE_NAME:-}" --out "$RUNNER_TEMP/ExportOptions.plist"

auth=()
if [[ "$SIGNING" == cloud ]]; then
    : "${APP_STORE_CONNECT_KEY_ID:?}" "${APP_STORE_CONNECT_ISSUER_ID:?}" "${APP_STORE_CONNECT_PRIVATE_KEY:?}"
    KEY_DIR="$RUNNER_TEMP/asc-key"
    mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
    trap 'rm -rf "$KEY_DIR"' EXIT
    KEY_PATH="$KEY_DIR/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
    (umask 077 && printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$KEY_PATH")
    # Automatic signing through the API key: the archive is signed with an Apple Development
    # certificate/profile Xcode creates on the fly, the export is cloud-signed for App Store.
    auth=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH"
          -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
          -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")
fi

ARCHIVE="$RUNNER_TEMP/Khala.xcarchive"
xcodebuild archive -project HomeAssistant.xcodeproj -scheme App-Release -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" -xcconfig "$RUNNER_TEMP/khala.xcconfig" \
    -skipPackagePluginValidation -skipMacroValidation ${auth[@]+"${auth[@]}"} \
    | xcbeautify --renderer github-actions

EXPORT="$RUNNER_TEMP/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" ${auth[@]+"${auth[@]}"} \
    | xcbeautify --renderer github-actions

shopt -s nullglob
ipas=("$EXPORT"/*.ipa)
[[ ${#ipas[@]} == 1 ]] || { echo '::error::expected exactly one exported IPA'; exit 1; }
IPA="$RUNNER_TEMP/Khala.ipa"
mv "${ipas[0]}" "$IPA"

# The signature check needs codesign, so it stays here; Info.plist/profile checks run on Ubuntu.
VERIFY="$RUNNER_TEMP/verify"
rm -rf "$VERIFY" && mkdir -p "$VERIFY"
unzip -qq "$IPA" -d "$VERIFY"
apps=("$VERIFY/Payload/"*.app)
[[ ${#apps[@]} == 1 ]] || { echo '::error::expected exactly one packaged app'; exit 1; }
codesign --verify --deep --strict "${apps[0]}"
codesign -d --entitlements - --xml "${apps[0]}" > "$RUNNER_TEMP/entitlements.plist" 2>/dev/null
python3 - "$RUNNER_TEMP/entitlements.plist" <<'PY'
import os, plistlib, sys
with open(sys.argv[1], "rb") as stream:
    ent = plistlib.load(stream)
team, bundle, prefix = os.environ["APPLE_TEAM_ID"], os.environ["BUNDLE_ID"], os.environ["BUNDLE_ID_PREFIX"]
assert ent.get("com.apple.developer.team-identifier") == team, "wrong signing team"
assert ent.get("application-identifier") == f"{team}.{bundle}", "wrong signed app identity"
assert ent.get("get-task-allow") is not True, "development entitlement in a distribution build"
assert "com.apple.developer.associated-domains" not in ent, "applinks leaked into the signature"
assert ent.get("com.apple.security.application-groups") == [f"group.{prefix}.homeassistant"], \
    "app group missing: the app keeps its database in it"
print("Distribution signature and entitlements verified:", ", ".join(sorted(ent)))
PY
echo "- Signed Khala.ipa exported and its signature verified ($SIGNING signing)." >> "$GITHUB_STEP_SUMMARY"
echo "ipa=$IPA" >> "$GITHUB_OUTPUT"
