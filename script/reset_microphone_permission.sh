#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${1:-com.trmd.syn}"

/usr/bin/tccutil reset Microphone "$BUNDLE_ID"

echo "Reset Microphone permission for $BUNDLE_ID only."
echo "Relaunch Syn, then use the Permissions panel to request Microphone again."
echo "If using the in-app Reset Mic button, Syn will relaunch and request Microphone automatically."
