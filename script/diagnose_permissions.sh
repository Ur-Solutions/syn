#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Syn"
BUNDLE_ID="com.trmd.syn"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
INFO_PLIST="$STAGED_APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "Syn permission diagnostics"
echo "Expected bundle: $STAGED_APP_BUNDLE"
echo "Expected bundle id: $BUNDLE_ID"
echo

if [[ ! -d "$STAGED_APP_BUNDLE" ]]; then
  echo "Bundle is missing. Run ./script/build_and_run.sh --verify first."
  exit 1
fi

echo "Bundle"
/bin/ls -ld "$STAGED_APP_BUNDLE"
echo

echo "Info.plist"
for key in CFBundleIdentifier CFBundleExecutable LSUIElement NSMicrophoneUsageDescription; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="<missing>"
  fi
  echo "$key=$value"
done
echo

echo "Running process"
pids="$(/usr/bin/pgrep -x "$APP_NAME" 2>/dev/null || true)"
if [[ -z "$pids" ]]; then
  echo "Syn is not currently running."
else
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    /bin/ps -p "$pid" -o pid= -o comm= -o args= || true
  done <<< "$pids"
fi
echo

echo "App permission status"
if [[ -x "$APP_BINARY" ]]; then
  "$APP_BINARY" --syn-permission-status-fixture 2>&1 || true
else
  echo "Cannot run permission status fixture; app binary is missing at $APP_BINARY."
fi
echo

echo "Code signature"
codesign_output="$(/usr/bin/codesign -dvvv --entitlements :- "$STAGED_APP_BUNDLE" 2>&1 || true)"
echo "$codesign_output" | /usr/bin/sed -n '1,140p'
if echo "$codesign_output" | /usr/bin/grep -q "Signature=adhoc"; then
  echo
  echo "NOTE: Syn is ad-hoc signed. If you rebuild after granting permissions, macOS may require a fresh grant."
fi
if echo "$codesign_output" | /usr/bin/grep -q "TeamIdentifier=not set"; then
  echo
  echo "NOTE: Syn is signed without a TeamIdentifier. macOS privacy grants may not survive rebuilds."
  echo "      Prefer Apple Development or Developer ID signing for permission-stable debug builds."
fi
echo

echo "Signature verification"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP_BUNDLE" 2>&1 || true
echo

echo "Gatekeeper assessment"
spctl_output="$(/usr/sbin/spctl -a -vv "$STAGED_APP_BUNDLE" 2>&1 || true)"
echo "$spctl_output"
if echo "$spctl_output" | /usr/bin/grep -q "origin=Rift Local Signing"; then
  echo "NOTE: Gatekeeper may reject local development certificates even when the app launches and codesign verification passes."
fi
echo

echo "Available code signing identities"
/usr/bin/security find-identity -p codesigning -v 2>/dev/null || true
echo

echo "Readable user TCC rows"
tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [[ ! -r "$tcc_db" ]]; then
  echo "Cannot read $tcc_db. This is normal unless the shell has Full Disk Access."
  exit 0
fi

sql="
SELECT
  service,
  client,
  client_type,
  auth_value,
  auth_reason,
  flags,
  datetime(last_modified, 'unixepoch') AS last_modified
FROM access
WHERE client = '$BUNDLE_ID'
   OR client LIKE '%Syn.app%'
ORDER BY service, client;
"

tcc_rows="$(/usr/bin/sqlite3 -readonly -header -column "$tcc_db" "$sql" 2>&1 || true)"
if [[ -z "$tcc_rows" ]]; then
  echo "No matching rows in the user TCC database."
else
  echo "$tcc_rows"
fi
