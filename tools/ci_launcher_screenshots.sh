#!/bin/zsh
# Build the isolated launcher preview for the iOS Simulator and capture
# screenshots of every page in portrait and landscape. No game code or data.
set -euo pipefail
root=${0:A:h:h}
out=${1:-$root/out/launcher-shots}
build=$root/out/launcher-preview
mkdir -p "$out"
cmake -S "$root/ios/launcher-preview" -B "$build" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0
xcodebuild -project "$build/Theft4LauncherPreview.xcodeproj" \
  -scheme Theft4LauncherPreview -configuration Debug -sdk iphonesimulator \
  -derivedDataPath "$build/dd" CODE_SIGNING_ALLOWED=NO build | tail -n 30
app=$(find "$build" -name 'Theft4LauncherPreview.app' -type d -path '*iphonesimulator*' | head -n 1)
[[ -n "$app" ]] || { echo "preview app not built"; exit 1; }
bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")

shoot() {  # device-name label args...
  local device=$1 label=$2; shift 2
  local udid
  udid=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
name=sys.argv[1]
for rt,devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["name"]==name: print(d["udid"]); raise SystemExit
' "$device")
  [[ -n "$udid" ]] || { echo "no simulator named $device"; return 0; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$app"
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl launch "$udid" "$bundle" "$@" >/dev/null
  sleep 6
  xcrun simctl io "$udid" screenshot "$out/$label.png" >/dev/null
  echo "captured $label"
}

phone=${THEFT4_SHOT_PHONE:-}
if [[ -z "$phone" ]]; then
  phone=$(xcrun simctl list devices available | grep -oE 'iPhone 1[5-9] Pro( Max)?|iPhone 1[5-9]' | head -n 1)
fi
pad=$(xcrun simctl list devices available | grep -oE 'iPad Pro [^(]*\)' | head -n 1 | sed 's/ *$//' || true)
[[ -z "$pad" ]] && pad=$(xcrun simctl list devices available | grep -oE 'iPad Air [^(]*' | head -n 1 | sed 's/ *$//' || true)
echo "phone=$phone pad=$pad"
for orient in portrait landscape; do
  shoot "$phone" "phone-$orient-play" --$orient
  for page in display interface system mods; do
    shoot "$phone" "phone-$orient-$page" --$orient --$page
  done
done
shoot "$phone" "phone-portrait-locked" --portrait --display --locked
if [[ -n "$pad" ]]; then
  shoot "$pad" "pad-landscape-play" --landscape
  shoot "$pad" "pad-landscape-display" --landscape --display
  shoot "$pad" "pad-portrait-play" --portrait
fi
ls -la "$out"
