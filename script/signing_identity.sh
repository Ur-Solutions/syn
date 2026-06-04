#!/usr/bin/env bash

find_code_sign_identity_exact() {
  local identity="$1"
  /usr/bin/security find-identity -p codesigning -v 2>/dev/null \
    | /usr/bin/awk -F '"' -v identity="$identity" '$2 == identity { print $2; exit }'
}

find_code_sign_identity_prefix() {
  local prefix="$1"
  /usr/bin/security find-identity -p codesigning -v 2>/dev/null \
    | /usr/bin/awk -F '"' -v prefix="$prefix" 'index($2, prefix) == 1 { print $2; exit }'
}

find_default_sign_identity() {
  if [[ -n "${SYN_DEFAULT_CODE_SIGN_IDENTITY:-}" ]]; then
    find_code_sign_identity_exact "$SYN_DEFAULT_CODE_SIGN_IDENTITY"
    return
  fi

  find_code_sign_identity_exact "Apple Development: Tormod Haugland (QT5J6P28AM)" \
    || find_code_sign_identity_prefix "Apple Development:" \
    || find_code_sign_identity_exact "Developer ID Application: Ur Solutions AS (4QK8JBAU4V)" \
    || find_code_sign_identity_prefix "Developer ID Application:" \
    || find_code_sign_identity_exact "Rift Local Signing"
}
