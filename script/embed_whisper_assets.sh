#!/usr/bin/env bash
set -euo pipefail

RESOURCE_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Whisper"
MODEL_DIR="${RESOURCE_DIR}/Models"
BACKEND_DIR="${RESOURCE_DIR}/Backends"

WHISPER_CLI_SOURCE="${WHISPER_CLI_SOURCE:-/opt/homebrew/Cellar/whisper-cpp/1.8.4/bin/whisper-cli}"
LIBWHISPER_SOURCE="${LIBWHISPER_SOURCE:-/opt/homebrew/Cellar/whisper-cpp/1.8.4/lib/libwhisper.1.8.4.dylib}"
LIBGGML_SOURCE="${LIBGGML_SOURCE:-/opt/homebrew/opt/ggml/lib/libggml.0.11.1.dylib}"
LIBGGML_BASE_SOURCE="${LIBGGML_BASE_SOURCE:-/opt/homebrew/opt/ggml/lib/libggml-base.0.11.1.dylib}"
LIBOMP_SOURCE="${LIBOMP_SOURCE:-/opt/homebrew/opt/libomp/lib/libomp.dylib}"
GGML_BACKEND_SOURCE_DIR="${GGML_BACKEND_SOURCE_DIR:-/opt/homebrew/Cellar/ggml/0.11.1/libexec}"
WHISPER_MODEL_SOURCE="${WHISPER_MODEL_SOURCE:-/Users/trmd/Library/Caches/Ravn/whisper-models/ggml-base.en.bin}"

if [[ ! -x "${WHISPER_CLI_SOURCE}" || ! -f "${LIBWHISPER_SOURCE}" || ! -f "${LIBGGML_SOURCE}" || ! -f "${LIBGGML_BASE_SOURCE}" || ! -f "${LIBOMP_SOURCE}" || ! -d "${GGML_BACKEND_SOURCE_DIR}" || ! -f "${WHISPER_MODEL_SOURCE}" ]]; then
  echo "warning: Syn Whisper bundle assets were not found. Local transcription will use development fallbacks if available."
  exit 0
fi

mkdir -p "${MODEL_DIR}" "${BACKEND_DIR}"

cp -f "${WHISPER_CLI_SOURCE}" "${RESOURCE_DIR}/whisper-cli"
cp -f "${LIBWHISPER_SOURCE}" "${RESOURCE_DIR}/libwhisper.1.dylib"
cp -f "${LIBGGML_SOURCE}" "${RESOURCE_DIR}/libggml.0.dylib"
cp -f "${LIBGGML_BASE_SOURCE}" "${RESOURCE_DIR}/libggml-base.0.dylib"
cp -f "${LIBOMP_SOURCE}" "${BACKEND_DIR}/libomp.dylib"
cp -f "${GGML_BACKEND_SOURCE_DIR}"/libggml-*.so "${BACKEND_DIR}/"
cp -f "${WHISPER_MODEL_SOURCE}" "${MODEL_DIR}/ggml-base.en.bin"

chmod 755 "${RESOURCE_DIR}/whisper-cli"
chmod 644 "${RESOURCE_DIR}/libwhisper.1.dylib" "${RESOURCE_DIR}/libggml.0.dylib" "${RESOURCE_DIR}/libggml-base.0.dylib" "${MODEL_DIR}/ggml-base.en.bin"
chmod 755 "${BACKEND_DIR}"/libggml-*.so "${BACKEND_DIR}/libomp.dylib"

perl -0pi -e 'BEGIN { $from = "/opt/homebrew/Cellar/ggml/0.11.1/libexec"; $to = "./Backends" . ("\0" x (length($from) - length("./Backends"))); } s/\Q$from\E/$to/g' "${RESOURCE_DIR}/libggml.0.dylib"

install_name_tool -change @rpath/libwhisper.1.dylib @loader_path/libwhisper.1.dylib "${RESOURCE_DIR}/whisper-cli" || true
install_name_tool -change /opt/homebrew/opt/ggml/lib/libggml.0.dylib @loader_path/libggml.0.dylib "${RESOURCE_DIR}/whisper-cli" || true
install_name_tool -change /opt/homebrew/opt/ggml/lib/libggml-base.0.dylib @loader_path/libggml-base.0.dylib "${RESOURCE_DIR}/whisper-cli" || true

install_name_tool -id @loader_path/libwhisper.1.dylib "${RESOURCE_DIR}/libwhisper.1.dylib" || true
install_name_tool -change /opt/homebrew/opt/ggml/lib/libggml.0.dylib @loader_path/libggml.0.dylib "${RESOURCE_DIR}/libwhisper.1.dylib" || true
install_name_tool -change /opt/homebrew/opt/ggml/lib/libggml-base.0.dylib @loader_path/libggml-base.0.dylib "${RESOURCE_DIR}/libwhisper.1.dylib" || true

install_name_tool -id @loader_path/libggml.0.dylib "${RESOURCE_DIR}/libggml.0.dylib" || true
install_name_tool -change @rpath/libggml-base.0.dylib @loader_path/libggml-base.0.dylib "${RESOURCE_DIR}/libggml.0.dylib" || true
install_name_tool -id @loader_path/libggml-base.0.dylib "${RESOURCE_DIR}/libggml-base.0.dylib" || true

for backend in "${BACKEND_DIR}"/libggml-*.so; do
  install_name_tool -change @rpath/libggml-base.0.dylib @loader_path/../libggml-base.0.dylib "${backend}" || true
  install_name_tool -change /opt/homebrew/opt/libomp/lib/libomp.dylib @loader_path/libomp.dylib "${backend}" || true
done

codesign --force --sign - --timestamp=none "${RESOURCE_DIR}/whisper-cli" "${RESOURCE_DIR}/libwhisper.1.dylib" "${RESOURCE_DIR}/libggml.0.dylib" "${RESOURCE_DIR}/libggml-base.0.dylib" "${BACKEND_DIR}/libomp.dylib" "${BACKEND_DIR}"/libggml-*.so >/dev/null 2>&1 || true

echo "Syn bundled Whisper assets at ${RESOURCE_DIR}"
