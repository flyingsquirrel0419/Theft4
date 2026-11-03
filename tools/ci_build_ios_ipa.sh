#!/bin/zsh
# CI variant of tools/build_ios_release.sh for a hosted macOS runner.
# Differences: the legacy MoltenVK archives are optional (passed only when a
# directory is supplied), and the game-payload check uses an empty placeholder
# directory. No game data is read or packaged.
set -euo pipefail
repo_root="${0:A:h:h}"
cd "$repo_root"
source "$repo_root/tools/theft4_renderer_build_args.sh"

build_jobs="${THEFT4_BUILD_JOBS:-3}"
library_dir="${THEFT4_MOLTENVK_IOS_LIB_DIR:-$repo_root/out/no-moltenvk}"
shader_dir="${THEFT4_XENIOS_GENERATED_SHADER_DIR:-$repo_root/out/no-xenios-shaders}"
app_path="$repo_root/out/build/ios-device-release/theft4/Release/Theft4.app"

# Configure-time existence check only (CMakeLists.txt). Never bundled: the
# packager refuses bundled game data.
payload="$repo_root/out/ci-placeholder-game"
mkdir -p "$payload"
for f in default.xex common.rpf xbox360.rpf audio.rpf; do : > "$payload/$f"; done
export GAME_PATH="$payload"

cmake --preset ios-device-release \
  -DREXGLUE_RUNTIME_ONLY=ON \
  -DREXGLUE_HEADLESS_KERNEL=ON \
  -DTHEFT4_BUILD_GAME_CODE=ON \
  -DTHEFT4_ENABLE_GAME_STARTUP=ON \
  -DTHEFT4_COMPILE_GTA4_NATIVE_BACKEND=ON \
  -DTHEFT4_ENABLE_GTA4_NATIVE_BACKEND=ON \
  -DTHEFT4_LAB_BUILD=ON \
  -DTHEFT4_BUNDLE_IDENTIFIER=com.lukebrosious.theft4 \
  -DTHEFT4_DISPLAY_NAME=Theft4 \
  "${renderer_build_args[@]}" \
  -DTHEFT4_SIGN_DEVICE=OFF \
  -DTHEFT4_PUBLIC_BUILD=ON \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DTHEFT4_XENIOS_IOS_LIB_DIR="$library_dir" \
  -DTHEFT4_XENIOS_GENERATED_SHADER_DIR="$shader_dir"
cmake --build --preset theft4-device-release --parallel "$build_jobs" -- -quiet
python3 "$repo_root/tests/ios/verify_release_build.py" "$repo_root/out/build/ios-device-release"
"$repo_root/tools/package_ios_ipa.sh" "$app_path" "$repo_root/dist"
