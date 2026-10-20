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
    --build "$BUILD_NUMBER" --profile "${PROFILE_UUID:-}" --out "$RUNNER_TEMP/khala.xcconfig"
[[ "$SIGNING" == unsigned ]] || python3 "$SHIP" export-options --mode "$SIGNING" --team "$APPLE_TEAM_ID" --bundle-id "$BUNDLE_ID" \
    --profile "${PROFILE_UUID:-}" --out "$RUNNER_TEMP/ExportOptions.plist"

KEY_DIR="$RUNNER_TEMP/asc-key"
KEYCHAIN="$RUNNER_TEMP/khala-signing.keychain-db"
P12="$RUNNER_TEMP/khala-dist.p12"
cleanup() {
    rm -rf "$KEY_DIR" "$P12"
    [[ -f "$KEYCHAIN" ]] && security delete-keychain "$KEYCHAIN" 2>/dev/null || true
}
trap cleanup EXIT

auth=()
if [[ "$SIGNING" == manual ]]; then
    : "${APPSTORE_DIST_P12_BASE64:?}" "${APPSTORE_DIST_P12_PASSWORD:?}" "${PROFILE_UUID:?}" "${PROFILE_B64:?}"
    # Throwaway keychain with a random password: the distribution key lives only here and only
    # for this job (deleted on exit). Never Xcode's own Apple login.
    KC_PASS=$(openssl rand -hex 24)
    (umask 077 && printf '%s' "$APPSTORE_DIST_P12_BASE64" | base64 --decode > "$P12")
    security create-keychain -p "$KC_PASS" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
    security import "$P12" -k "$KEYCHAIN" -f pkcs12 -P "$APPSTORE_DIST_P12_PASSWORD" \
        -T /usr/bin/codesign -T /usr/bin/security >/dev/null
    rm -f "$P12"
    for ca in AppleWWDRCAG3 AppleWWDRCAG6; do  # intermediates; harmless if already on the image
        curl -fsSL "https://www.apple.com/certificateauthority/$ca.cer" -o "$RUNNER_TEMP/$ca.cer" &&
            security import "$RUNNER_TEMP/$ca.cer" -k "$KEYCHAIN" >/dev/null 2>&1 || true
    done
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1
    # shellcheck disable=SC2046  # keychain paths on the runner carry no spaces
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
    security find-identity -v -p codesigning "$KEYCHAIN" | grep 'Apple Distribution' >/dev/null ||
        { echo '::error::the P12 holds no valid Apple Distribution identity'; exit 1; }
    echo "Signing identity ready in a throwaway keychain."
    for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
               "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
        mkdir -p "$dir"
        printf '%s' "$PROFILE_B64" | base64 --decode > "$dir/$PROFILE_UUID.mobileprovision"
    done
elif [[ "$SIGNING" == cloud ]]; then
    : "${APP_STORE_CONNECT_KEY_ID:?}" "${APP_STORE_CONNECT_ISSUER_ID:?}" "${APP_STORE_CONNECT_PRIVATE_KEY:?}"
    mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
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

if [[ "$SIGNING" == unsigned ]]; then
    echo "- Unsigned compile-only archive succeeded (nothing exported or kept)." >> "$GITHUB_STEP_SUMMARY"
    exit 0
fi

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
