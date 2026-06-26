#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Syn"
BUNDLE_ID="com.trmdy.syn"
PROJECT_PATH="Syn.xcodeproj"
SCHEME="Syn"
CONFIGURATION="Release"
APPLE_ID="${APPLE_ID:-tormod.haugland@gmail.com}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-4QK8JBAU4V}"
HEM_APP_PASSWORD_PATH="${SYN_HEM_APP_PASSWORD_PATH:-project/syn/app-specific-password}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"

usage() {
  echo "usage: $0 <version>   e.g. $0 0.1.0" >&2
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 2
  fi
}

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  usage
  exit 2
fi
VERSION="${VERSION#v}"
BUILD_NUMBER="${SYN_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

source "$ROOT_DIR/script/signing_identity.sh"

require_tool xcodebuild
require_tool xcrun
require_tool hdiutil
require_tool codesign
require_tool security
require_tool ditto
require_tool shasum
require_tool git

if [[ "${SYN_ALLOW_DIRTY:-0}" != "1" && -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  echo "working tree is dirty. Commit/stash first, or set SYN_ALLOW_DIRTY=1 for a local test build." >&2
  exit 1
fi

SIGN_IDENTITY="${SYN_DEVELOPER_ID_CODE_SIGN_IDENTITY:-${SYN_DEVELOPER_ID_CERT_SHA1:-}}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(find_developer_id_sign_identity || true)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "could not find a Developer ID Application signing identity." >&2
  echo "Install the Developer ID certificate or set SYN_DEVELOPER_ID_CODE_SIGN_IDENTITY / SYN_DEVELOPER_ID_CERT_SHA1." >&2
  exit 1
fi
if [[ ! "$SIGN_IDENTITY" =~ ^[A-Fa-f0-9]{40}$ && "$SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "release signing requires a Developer ID Application identity, got: $SIGN_IDENTITY" >&2
  exit 1
fi

NOTARY_ARGS=()
configure_notary_auth() {
  if [[ -n "${APPLE_API_KEY:-}" || -n "${APPLE_API_KEY_ID:-}" || -n "${APPLE_API_ISSUER:-}" ]]; then
    if [[ -z "${APPLE_API_KEY:-}" || -z "${APPLE_API_KEY_ID:-}" || -z "${APPLE_API_ISSUER:-}" ]]; then
      echo "set APPLE_API_KEY, APPLE_API_KEY_ID, and APPLE_API_ISSUER together." >&2
      exit 1
    fi
    NOTARY_ARGS=(--key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
    return
  fi

  if [[ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    require_tool hem
    echo "fetching notarization password from Hem: $HEM_APP_PASSWORD_PATH"
    APPLE_APP_SPECIFIC_PASSWORD="$(hem get "$HEM_APP_PASSWORD_PATH" password --reason "syn release v${VERSION}")"
  fi

  if ! printf '%s' "$APPLE_APP_SPECIFIC_PASSWORD" | grep -qE '^[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}$'; then
    echo "unexpected Apple app-specific password shape." >&2
    exit 1
  fi
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
}

create_export_options() {
  local path="$1"
  /bin/cat > "$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>${SIGN_IDENTITY}</string>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
PLIST
}

sign_embedded_code() {
  local app_bundle="$1"
  local whisper_dir="$app_bundle/Contents/Resources/Whisper"

  if [[ ! -d "$whisper_dir" ]]; then
    return
  fi

  while IFS= read -r path; do
    if /usr/bin/file "$path" | /usr/bin/grep -q "Mach-O"; then
      /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$path"
    fi
  done < <(/usr/bin/find "$whisper_dir" -type f -print)
}

verify_bundle_metadata() {
  local app_bundle="$1"
  local info_plist="$app_bundle/Contents/Info.plist"
  local actual_id
  actual_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist")"
  if [[ "$actual_id" != "$BUNDLE_ID" ]]; then
    echo "expected bundle id $BUNDLE_ID, got $actual_id" >&2
    exit 1
  fi
}

resign_app() {
  local app_bundle="$1"
  sign_embedded_code "$app_bundle"
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT_DIR/Syn/Syn.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$app_bundle"
}

make_zip() {
  local app_bundle="$1"
  local zip_path="$2"
  rm -f "$zip_path"
  (
    cd "$(dirname "$app_bundle")"
    /usr/bin/ditto -c -k --keepParent --sequesterRsrc --zlibCompressionLevel 9 "$(basename "$app_bundle")" "$zip_path"
  )
}

make_dmg() {
  local app_bundle="$1"
  local dmg_path="$2"
  local dmg_root="$RELEASE_DIR/dmg-root"
  rm -rf "$dmg_root" "$dmg_path"
  mkdir -p "$dmg_root"
  /usr/bin/ditto "$app_bundle" "$dmg_root/$APP_NAME.app"
  /usr/bin/hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$dmg_root" -ov -format UDZO "$dmg_path" >/dev/null
}

notarize() {
  local artifact="$1"
  /usr/bin/xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait
}

configure_notary_auth

ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.xcarchive"
EXPORT_PATH="$RELEASE_DIR/export"
EXPORT_OPTIONS_PLIST="$RELEASE_DIR/ExportOptions.plist"
APP_BUNDLE="$EXPORT_PATH/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-arm64.dmg"
SUMS_PATH="$RELEASE_DIR/SHA256SUMS"

echo "Syn release v$VERSION"
echo "bundle id: $BUNDLE_ID"
echo "team id: $APPLE_TEAM_ID"
echo "signing identity: $SIGN_IDENTITY"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
create_export_options "$EXPORT_OPTIONS_PLIST"

echo "archiving..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" \
  "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" \
  "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
  "MARKETING_VERSION=$VERSION" \
  "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
  "OTHER_CODE_SIGN_FLAGS=--timestamp"

echo "exporting Developer ID app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "expected exported app at $APP_BUNDLE" >&2
  exit 1
fi

echo "re-signing embedded runtime assets..."
verify_bundle_metadata "$APP_BUNDLE"
resign_app "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "notarizing app..."
make_zip "$APP_BUNDLE" "$ZIP_PATH"
notarize "$ZIP_PATH"
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
make_zip "$APP_BUNDLE" "$ZIP_PATH"

echo "creating, notarizing, and stapling DMG..."
make_dmg "$APP_BUNDLE" "$DMG_PATH"
notarize "$DMG_PATH"
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"

echo "verifying Gatekeeper assessment..."
/usr/sbin/spctl -a -vvv -t install "$APP_BUNDLE"
/usr/sbin/spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH"

/usr/bin/shasum -a 256 "$DMG_PATH" "$ZIP_PATH" > "$SUMS_PATH"

echo "release artifacts:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $SUMS_PATH"
