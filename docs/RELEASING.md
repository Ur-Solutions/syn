# Releasing Syn

Syn releases are built locally with the Developer ID certificate and notarized with
Apple notarytool. The bundle id is `com.trmdy.syn`.

Because this differs from the earlier `com.trmd.syn` id, macOS treats it as a
separate app for Screen Recording, Microphone, Accessibility, and Automation
permissions.

## Prerequisites

- `Developer ID Application: Ur Solutions AS (4QK8JBAU4V)` in the login keychain.
- Xcode command-line tools on `PATH`.
- `hem` with `project/syn/app-specific-password` or the shared Flyt fallback
  `project/flyt/app-specific-password`, or
  `APPLE_APP_SPECIFIC_PASSWORD` already exported.
- Current Apple Developer agreements accepted.

## Build, Sign, Notarize

```bash
./script/release.sh 0.1.0
```

The script:

1. refuses a dirty working tree unless `SYN_ALLOW_DIRTY=1` is set,
2. builds an arm64 Release archive with hardened runtime,
3. exports with Developer ID signing,
4. re-signs embedded Whisper Mach-O assets and the outer app,
5. notarizes and staples `Syn.app`,
6. creates, notarizes, and staples a DMG,
7. verifies with `codesign`, `stapler`, and `spctl`.

Outputs are written to `release/`:

```text
release/Syn-<version>-arm64.dmg
release/Syn-<version>-arm64.zip
release/SHA256SUMS
```

## Overrides

- `APPLE_ID`, `APPLE_TEAM_ID`: Apple account/team for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: skip Hem and use this password directly.
- `SYN_HEM_APP_PASSWORD_PATH`: override Hem lookup. By default the script tries
  `project/syn/app-specific-password`, then `project/flyt/app-specific-password`.
- `SYN_DEVELOPER_ID_CODE_SIGN_IDENTITY`: explicit Developer ID identity name.
- `SYN_DEVELOPER_ID_CERT_SHA1`: explicit Developer ID certificate SHA-1.
- `SYN_BUILD_NUMBER`: override `CURRENT_PROJECT_VERSION`.
