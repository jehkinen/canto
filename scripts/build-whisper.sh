#!/bin/bash
# Builds whisper.cpp into Packages/WhisperBridge/Frameworks/whisper.xcframework: one static
# library per architecture (arm64 + x86_64, merged with lipo) plus a clang module map, so Swift
# can `import whisper`. Metal shaders are embedded into the library.
# The pinned whisper.cpp release is downloaded into Vendor/ on first use and checked by SHA-256.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/whisper.cpp"
WHISPER_VERSION="1.7.4"
WHISPER_SHA256="9ce7b33028793fcbf62f81f1fd087af7778dace8772eaba8c43c66bf0c8a3eed"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
  echo "Downloading whisper.cpp $WHISPER_VERSION"
  mkdir -p "$ROOT/Vendor"
  ARCHIVE="$ROOT/Vendor/whisper.cpp-$WHISPER_VERSION.tar.gz"
  curl -fsSL -o "$ARCHIVE" "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v$WHISPER_VERSION.tar.gz"
  echo "$WHISPER_SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null
  rm -rf "$SRC" "$ROOT/Vendor/whisper.cpp-$WHISPER_VERSION"
  tar -xzf "$ARCHIVE" -C "$ROOT/Vendor"
  mv "$ROOT/Vendor/whisper.cpp-$WHISPER_VERSION" "$SRC"
  rm "$ARCHIVE"
fi
BUILD="$ROOT/Vendor/.build-whisper"
OUT="$ROOT/Packages/WhisperBridge/Frameworks/whisper.xcframework"
DEPLOYMENT_TARGET="14.0"
JOBS="$(sysctl -n hw.ncpu)"

build_arch() {
  local arch="$1"; shift
  local dir="$BUILD/$arch"
  cmake -S "$SRC" -B "$dir" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_METAL_NDEBUG=ON \
    -DGGML_BLAS=ON \
    -DGGML_ACCELERATE=ON \
    "$@" >"$dir.configure.log"
  cmake --build "$dir" --config Release -j "$JOBS" >"$dir.build.log"

  # Every static archive the build produced goes into one library per arch.
  local libs=()
  while IFS= read -r lib; do libs+=("$lib"); done < <(find "$dir" -name "*.a" | sort)
  libtool -static -o "$BUILD/libwhisper-$arch.a" "${libs[@]}" 2>/dev/null
  echo "  $arch: ${#libs[@]} archives -> libwhisper-$arch.a"
}

mkdir -p "$BUILD"
echo "Building whisper.cpp $(grep -m1 -oE 'whisper.cpp" VERSION [0-9.]+' "$SRC/CMakeLists.txt" | grep -oE '[0-9.]+$')"
build_arch arm64
# Every Mac that runs macOS 14 has AVX2/FMA/F16C, so the Intel slice may use them.
build_arch x86_64 -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON

lipo -create "$BUILD/libwhisper-arm64.a" "$BUILD/libwhisper-x86_64.a" -output "$BUILD/libwhisper.a"

HEADERS="$BUILD/Headers"
rm -rf "$HEADERS" && mkdir -p "$HEADERS"
cp "$SRC/include/whisper.h" "$HEADERS/"
cp "$SRC/ggml/include/"{ggml.h,ggml-cpu.h,ggml-backend.h,ggml-alloc.h} "$HEADERS/"
cat >"$HEADERS/module.modulemap" <<'EOF'
module whisper [system] {
  header "whisper.h"
  link "c++"
  link framework "Accelerate"
  link framework "Foundation"
  link framework "Metal"
  link framework "MetalKit"
  export *
}
EOF

rm -rf "$OUT"
xcodebuild -create-xcframework -library "$BUILD/libwhisper.a" -headers "$HEADERS" -output "$OUT" >/dev/null
echo "Done: $OUT ($(lipo -archs "$BUILD/libwhisper.a"))"
