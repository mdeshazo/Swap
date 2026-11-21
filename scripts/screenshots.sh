#!/bin/bash
# Boots an iPhone simulator, installs the built app, and captures screenshots.
# Needs UDID and RUNNER_TEMP in the environment, and a finished build in ./build.
set -u
OUT="$RUNNER_TEMP/shots"; mkdir -p "$OUT"
APP=$(find build/Build/Products -maxdepth 3 -name 'Swap.app' | head -1)
echo "App: $APP"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light || true

shot() {
  local name="$1"; local wait="$2"; shift 2
  xcrun simctl uninstall "$UDID" com.example.swap || true
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" com.example.swap "$@"
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  xcrun simctl terminate "$UDID" com.example.swap || true
}

shot 1-browse  6  -demoMode YES -startTab browse
shot 2-listing 8  -demoMode YES -openFirstListing YES
shot 3-sell    6  -demoMode YES -startTab sell
shot 4-chat    10 -demoMode YES -startTab inbox -demoChat YES
shot 5-signin  8  -startTab profile -showSignIn YES
ls -la "$OUT"
