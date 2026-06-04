#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.trmd.syn"

for service in ScreenCapture Microphone Accessibility; do
  /usr/bin/tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
done

echo "Reset Screen Recording, Microphone, and Accessibility permissions for $BUNDLE_ID."
echo "Run ./script/build_and_run.sh --verify, then use Syn's Permissions panel to request/grant permissions again."
