#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${1:-$PROJECT_DIR/build/visual-qa}"
BUILT_EXECUTABLE="$PROJECT_DIR/.build/debug/ExternalDisplayViewer"
INFO_PLIST="$PROJECT_DIR/Support/Info.plist"
WINDOW_LOOKUP="$PROJECT_DIR/Scripts/window-id.swift"
WINDOW_LOOKUP_BINARY="$OUTPUT_DIR/window-id"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
export SWIFTPM_HOME="$PROJECT_DIR/.build/swiftpm"

states=(
  selection-ready
  selection-screen-recording-denied
  selection-interaction-denied
  selection-accessibility-settings
  selection-input-monitoring-settings
  selection-no-external-display
  selection-refresh-error
  viewer-view-only
  viewer-interactive-ready
  viewer-control-hud
  viewer-return-hud
  viewer-overlap-warning
  viewer-metrics-stress
)

mkdir -p "$OUTPUT_DIR" "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_HOME"
cd "$PROJECT_DIR"
swift build -c debug --disable-sandbox
swiftc "$WINDOW_LOOKUP" -o "$WINDOW_LOOKUP_BINARY"

QA_TEMP_DIR="$(mktemp -d /private/tmp/external-display-viewer-visual-qa.XXXXXX)"
QA_APP="$QA_TEMP_DIR/ExternalDisplayViewer.app"
EXECUTABLE="$QA_APP/Contents/MacOS/ExternalDisplayViewer"
mkdir -p "$QA_APP/Contents/MacOS" "$QA_APP/Contents/Resources"
cp "$BUILT_EXECUTABLE" "$EXECUTABLE"
cp "$INFO_PLIST" "$QA_APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "local.codex.ExternalDisplayViewer.VisualQA.$$" \
  "$QA_APP/Contents/Info.plist"
chmod 755 "$EXECUTABLE"
xattr -cr "$QA_APP"
codesign --force --deep --sign - "$QA_APP"

cleanup() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$WINDOW_LOOKUP_BINARY"
  if [[ -n "${QA_TEMP_DIR:-}" && -d "$QA_TEMP_DIR" ]]; then
    rm -rf "$QA_TEMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

for state in $states; do
  print -r -- "Capturing $state"
  /usr/bin/open -n "$QA_APP" --args "--visual-qa-state=$state"
  app_pid=""
  title="Visual QA - $state"
  window_id=""

  for attempt in {1..80}; do
    app_pid="$("$WINDOW_LOOKUP_BINARY" --bundle-pid "$QA_APP" 2>/dev/null || true)"
    if [[ -n "$app_pid" ]]; then
      break
    fi
    sleep 0.1
  done

  if [[ -z "$app_pid" ]]; then
    print -u2 "app process not found for state: $state"
    exit 1
  fi

  "$WINDOW_LOOKUP_BINARY" --activate "$app_pid" >/dev/null 2>&1 || true

  for attempt in {1..80}; do
    window_id="$("$WINDOW_LOOKUP_BINARY" --owner-pid "$app_pid" "$title" 2>/dev/null || true)"
    if [[ -n "$window_id" ]]; then
      break
    fi
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  if [[ -z "$window_id" ]]; then
    print -u2 "window not found for state: $state"
    "$WINDOW_LOOKUP_BINARY" --owner-windows "$app_pid" >&2 || true
    if [[ -n "$app_pid" ]]; then
      kill "$app_pid" >/dev/null 2>&1 || true
    fi
    exit 1
  fi

  "$WINDOW_LOOKUP_BINARY" --activate "$app_pid" >/dev/null 2>&1 || true
  sleep 0.7

  captured=false
  for capture_attempt in {1..10}; do
    if screencapture -x -o -l "$window_id" "$OUTPUT_DIR/$state.png"; then
      captured=true
      break
    fi
    sleep 0.2
  done
  if [[ "$captured" != true ]]; then
    print -u2 "capture failed for state: $state"
    exit 1
  fi
  file "$OUTPUT_DIR/$state.png" | grep -q 'PNG image data'
  kill "$app_pid" >/dev/null 2>&1 || true
  wait "$app_pid" 2>/dev/null || true
  app_pid=""
done

rm -f "$WINDOW_LOOKUP_BINARY"
rm -rf "$QA_TEMP_DIR"
trap - EXIT INT TERM

for image in "$OUTPUT_DIR"/*.png; do
  sips -g pixelWidth -g pixelHeight "$image"
done
