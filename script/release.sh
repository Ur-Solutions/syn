#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Syn"
BUNDLE_ID="com.trmdy.syn"
PROJECT_PATH="Syn.xcodeproj"
SCHEME="Syn"
CONFIGURATION="Release"
APPLE_ID="${APPLE_ID:-tormod.haugland@gmail.com}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-4QK8JBAU4V}"
DEFAULT_HEM_APP_PASSWORD_PATHS=(
  "project/syn/app-specific-password"
  "project/flyt/app-specific-password"
)

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
require_tool osascript

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
    local hem_paths=("${DEFAULT_HEM_APP_PASSWORD_PATHS[@]}")
    if [[ -n "${SYN_HEM_APP_PASSWORD_PATH:-}" ]]; then
      hem_paths=("$SYN_HEM_APP_PASSWORD_PATH")
    fi

    local path
    for path in "${hem_paths[@]}"; do
      echo "fetching notarization password from Hem: $path"
      if APPLE_APP_SPECIFIC_PASSWORD="$(hem get "$path" password --reason "syn release v${VERSION}" 2>/tmp/syn-hem-error.log)"; then
        break
      fi
      /bin/cat /tmp/syn-hem-error.log >&2 || true
      APPLE_APP_SPECIFIC_PASSWORD=""
    done

    if [[ -z "$APPLE_APP_SPECIFIC_PASSWORD" ]]; then
      echo "could not fetch notarization password from Hem." >&2
      exit 1
    fi
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

generate_dmg_background() {
  local output_path="$1"
  if [[ ! -x /usr/bin/python3 ]]; then
    echo "missing required tool: /usr/bin/python3" >&2
    exit 2
  fi

  /usr/bin/python3 - "$output_path" <<'PY'
import math
import struct
import sys
import zlib

path = sys.argv[1]
width, height = 720, 420

def clamp(value):
    return max(0, min(255, int(round(value))))

def mix(a, b, t):
    return a + (b - a) * t

def blend(px, color, alpha):
    return tuple(clamp(mix(px[i], color[i], alpha)) for i in range(3))

def radial_alpha(x, y, cx, cy, radius, strength):
    d = math.hypot(x - cx, y - cy) / radius
    if d >= 1:
        return 0.0
    return (1 - d) ** 2 * strength

pixels = []
for y in range(height):
    row = []
    for x in range(width):
        tx = x / (width - 1)
        ty = y / (height - 1)
        base = (
            mix(247, 231, ty * 0.62 + tx * 0.10),
            mix(244, 250, tx * 0.48),
            mix(238, 246, ty * 0.40),
        )
        px = tuple(clamp(channel) for channel in base)
        px = blend(px, (236, 101, 121), radial_alpha(x, y, 110, 70, 260, 0.38))
        px = blend(px, (54, 176, 156), radial_alpha(x, y, 610, 330, 280, 0.28))
        px = blend(px, (28, 35, 38), radial_alpha(x, y, 360, 210, 360, 0.05))
        row.append(px)
    pixels.append(row)

def put(x, y, color, alpha=1.0):
    if 0 <= x < width and 0 <= y < height:
        pixels[y][x] = blend(pixels[y][x], color, alpha)

def disk(cx, cy, radius, color, alpha):
    min_x, max_x = int(cx - radius), int(cx + radius)
    min_y, max_y = int(cy - radius), int(cy + radius)
    for yy in range(min_y, max_y + 1):
        for xx in range(min_x, max_x + 1):
            d = math.hypot(xx - cx, yy - cy) / radius
            if d <= 1:
                put(xx, yy, color, alpha * (1 - d) ** 1.7)

def thick_line(x1, y1, x2, y2, radius, color, alpha):
    steps = max(abs(x2 - x1), abs(y2 - y1))
    for i in range(steps + 1):
        t = i / max(1, steps)
        x = x1 + (x2 - x1) * t
        y = y1 + (y2 - y1) * t
        disk(x, y, radius, color, alpha)

def triangle(points, color, alpha):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    min_x, max_x = int(min(xs)), int(max(xs))
    min_y, max_y = int(min(ys)), int(max(ys))
    (x1, y1), (x2, y2), (x3, y3) = points
    denom = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    for yy in range(min_y, max_y + 1):
        for xx in range(min_x, max_x + 1):
            a = ((y2 - y3) * (xx - x3) + (x3 - x2) * (yy - y3)) / denom
            b = ((y3 - y1) * (xx - x3) + (x1 - x3) * (yy - y3)) / denom
            c = 1 - a - b
            if a >= 0 and b >= 0 and c >= 0:
                put(xx, yy, color, alpha)

for cx in (180, 540):
    disk(cx, 214, 88, (255, 255, 255), 0.72)
    disk(cx, 214, 58, (255, 255, 255), 0.40)

for x in range(278, 443, 14):
    y = int(214 + math.sin((x - 278) / 38) * 7)
    disk(x, y, 4.7, (39, 48, 54), 0.58)

thick_line(280, 214, 438, 214, 2.2, (39, 48, 54), 0.38)
triangle([(454, 214), (424, 196), (424, 232)], (39, 48, 54), 0.44)

for y in range(height):
    for x in range(width):
        edge = min(x, y, width - 1 - x, height - 1 - y)
        if edge < 34:
            pixels[y][x] = blend(pixels[y][x], (255, 255, 255), (34 - edge) / 34 * 0.26)

raw = bytearray()
for row in pixels:
    raw.append(0)
    for r, g, b in row:
        raw.extend((r, g, b))

def chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )

png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    + chunk(b"IEND", b"")
)

with open(path, "wb") as f:
    f.write(png)
PY
}

style_dmg_window() {
  local mount_path="$1"
  /usr/bin/osascript - "$mount_path" "$APP_NAME.app" <<'OSA'
on run argv
  set mountPath to item 1 of argv
  set appItemName to item 2 of argv
  set backgroundPath to mountPath & "/.background/dmg-background.png"

tell application "Finder"
    set volumeFolder to POSIX file mountPath as alias
    open volumeFolder
    delay 1
    set installWindow to container window of volumeFolder
    set current view of installWindow to icon view
    set toolbar visible of installWindow to false
    set statusbar visible of installWindow to false
    set bounds of installWindow to {120, 120, 840, 540}
    set theViewOptions to icon view options of installWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 104
    set background picture of theViewOptions to (POSIX file backgroundPath as alias)
    set position of item appItemName of volumeFolder to {180, 222}
    set position of item "Applications" of volumeFolder to {540, 222}
    update volumeFolder without registering applications
    delay 1
    close installWindow
  end tell
end run
OSA
}

make_dmg() {
  local app_bundle="$1"
  local dmg_path="$2"
  local volume_name="$APP_NAME $VERSION"
  local rw_dmg="$RELEASE_DIR/$APP_NAME-$VERSION-arm64-rw.dmg"
  local mount_dir="$RELEASE_DIR/dmg-mount"
  local dmg_size_mb="${SYN_DMG_SIZE_MB:-260}"
  local mounted=0

  rm -rf "$mount_dir" "$dmg_path" "$rw_dmg"
  mkdir -p "$mount_dir"

  /usr/bin/hdiutil create \
    -volname "$volume_name" \
    -size "${dmg_size_mb}m" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    "$rw_dmg" >/dev/null

  cleanup_dmg_mount() {
    if [[ "$mounted" == "1" ]]; then
      /usr/bin/hdiutil detach "$mount_dir" -quiet || /usr/bin/hdiutil detach "$mount_dir" -force -quiet || true
    fi
  }
  trap cleanup_dmg_mount EXIT

  /usr/bin/hdiutil attach "$rw_dmg" -mountpoint "$mount_dir" -readwrite -noverify -noautoopen >/dev/null
  mounted=1

  /usr/bin/ditto "$app_bundle" "$mount_dir/$APP_NAME.app"
  /bin/ln -s /Applications "$mount_dir/Applications"
  /bin/mkdir -p "$mount_dir/.background"
  generate_dmg_background "$mount_dir/.background/dmg-background.png"
  style_dmg_window "$mount_dir"
  /usr/sbin/bless --folder "$mount_dir" --openfolder "$mount_dir" >/dev/null 2>&1 || true
  /bin/sync
  /usr/bin/hdiutil detach "$mount_dir" -quiet || { /bin/sleep 2; /usr/bin/hdiutil detach "$mount_dir" -force -quiet; }
  mounted=0
  trap - EXIT

  /usr/bin/hdiutil convert "$rw_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_path" >/dev/null
  rm -f "$rw_dmg"
  rmdir "$mount_dir" 2>/dev/null || true
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg_path"
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

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > "$(basename "$SUMS_PATH")"
)

echo "release artifacts:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $SUMS_PATH"
