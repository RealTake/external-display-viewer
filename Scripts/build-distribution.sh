#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_NAME="ExternalDisplayViewer.app"
EXECUTABLE_NAME="ExternalDisplayViewer"
ARCHITECTURE="arm64"
INFO_PLIST="$PROJECT_DIR/Support/Info.plist"
DISTRIBUTION_PLIST="$PROJECT_DIR/Support/Distribution.plist"
DEFAULT_OUTPUT_DIR="$PROJECT_DIR/build/distribution"

read_distribution_value() {
  plutil -extract "$1" raw -o - "$DISTRIBUTION_PLIST"
}

BUNDLE_ID=$(read_distribution_value CFBundleIdentifier)
VERSION=$(read_distribution_value CFBundleShortVersionString)
MINIMUM_MACOS=$(read_distribution_value LSMinimumSystemVersion)
ARCHIVE_NAME="ExternalDisplayViewer-v${VERSION}-macOS-${ARCHITECTURE}.zip"

usage() {
  print -u2 -- "Usage: $0 [--print-metadata] [--verify-tag TAG] [--output-dir DIR]"
}

print_metadata() {
  print -r -- "app=$APP_NAME"
  print -r -- "archive=$ARCHIVE_NAME"
  print -r -- "architecture=$ARCHITECTURE"
  print -r -- "bundle_id=$BUNDLE_ID"
  print -r -- "minimum_macos=$MINIMUM_MACOS"
  print -r -- "version=$VERSION"
}

verify_tag() {
  local tag="$1"
  if [[ "$tag" != "v$VERSION" ]]; then
    print -u2 -- "Release tag '$tag' does not match bundle version v$VERSION."
    exit 65
  fi
}

PRINT_METADATA=0
VERIFY_TAG=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"

while (( $# > 0 )); do
  case "$1" in
    --print-metadata)
      PRINT_METADATA=1
      shift
      ;;
    --verify-tag)
      if (( $# < 2 )); then
        usage
        exit 64
      fi
      VERIFY_TAG="$2"
      shift 2
      ;;
    --output-dir)
      if (( $# < 2 )); then
        usage
        exit 64
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if (( PRINT_METADATA == 1 )); then
  print_metadata
  exit 0
fi

if [[ -n "$VERIFY_TAG" ]]; then
  verify_tag "$VERIFY_TAG"
  if [[ "$OUTPUT_DIR" == "$DEFAULT_OUTPUT_DIR" ]]; then
    exit 0
  fi
fi

resolve_signing_identity() {
  if [[ -n "${EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY:-}" ]]; then
    print -r -- "$EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY"
    return
  fi

  local identity_line
  if ! identity_line=$(security find-identity -v -p codesigning | grep -m 1 '"Developer ID Application:'); then
    print -u2 -- "Developer ID Application signing identity is required. Set EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY."
    return 1
  fi

  identity_line=${identity_line#*\"}
  print -r -- "${identity_line%%\"*}"
}

SIGNING_IDENTITY=$(resolve_signing_identity) || exit 64
if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  print -u2 -- "Distribution builds require a Developer ID Application identity, got: $SIGNING_IDENTITY"
  exit 64
fi

NOTARY_PROFILE="${EXTERNAL_DISPLAY_VIEWER_NOTARY_PROFILE:-}"
if [[ -z "$NOTARY_PROFILE" ]]; then
  print -u2 -- "EXTERNAL_DISPLAY_VIEWER_NOTARY_PROFILE is required for notarized distribution builds."
  exit 64
fi
NOTARY_KEYCHAIN="${EXTERNAL_DISPLAY_VIEWER_NOTARY_KEYCHAIN:-}"

if ! security find-identity -v -p codesigning | grep -F -- "\"$SIGNING_IDENTITY\"" >/dev/null; then
  print -u2 -- "Code-signing identity not found: $SIGNING_IDENTITY"
  exit 64
fi

STAGING_ROOT=""
FINAL_TEMP_ARCHIVE=""

cleanup() {
  local exit_code=$?
  if [[ -n "$STAGING_ROOT" && -d "$STAGING_ROOT" ]]; then
    rm -rf "$STAGING_ROOT"
  fi
  if [[ -n "$FINAL_TEMP_ARCHIVE" && -e "$FINAL_TEMP_ARCHIVE" ]]; then
    rm -f "$FINAL_TEMP_ARCHIVE"
  fi
  return "$exit_code"
}
trap cleanup EXIT INT TERM

cd "$PROJECT_DIR"
swift build -c release --arch "$ARCHITECTURE" --disable-sandbox
BUILD_BIN_DIR=$(swift build -c release --arch "$ARCHITECTURE" --disable-sandbox --show-bin-path)
EXECUTABLE="$BUILD_BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  print -u2 -- "Expected release executable is missing: $EXECUTABLE"
  exit 1
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="$PROJECT_DIR/$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"

STAGING_ROOT=$(mktemp -d /private/tmp/external-display-viewer-distribution.XXXXXX)
STAGING_APP="$STAGING_ROOT/$APP_NAME"
VERIFY_DIR="$STAGING_ROOT/verify"
NOTARY_ARCHIVE="$STAGING_ROOT/notary-submit.zip"
FINAL_TEMP_ARCHIVE="$OUTPUT_DIR/.$ARCHIVE_NAME.$$"
FINAL_ARCHIVE="$OUTPUT_DIR/$ARCHIVE_NAME"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources" "$VERIFY_DIR"

cp "$EXECUTABLE" "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$STAGING_APP/Contents/Info.plist"
chmod 755 "$STAGING_APP/Contents/MacOS/$EXECUTABLE_NAME"

plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$STAGING_APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$STAGING_APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$STAGING_APP/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "$MINIMUM_MACOS" "$STAGING_APP/Contents/Info.plist"
plutil -lint "$STAGING_APP/Contents/Info.plist"
plutil -extract CFBundleIdentifier raw "$STAGING_APP/Contents/Info.plist" | grep -Fx "$BUNDLE_ID" >/dev/null
plutil -extract CFBundleShortVersionString raw "$STAGING_APP/Contents/Info.plist" | grep -Fx "$VERSION" >/dev/null
plutil -extract LSMinimumSystemVersion raw "$STAGING_APP/Contents/Info.plist" | grep -Fx "$MINIMUM_MACOS" >/dev/null

xattr -cr "$STAGING_APP"
codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$STAGING_APP"
codesign --verify --deep --strict "$STAGING_APP"

ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$STAGING_APP" "$NOTARY_ARCHIVE"
notary_submit_args=(notarytool submit "$NOTARY_ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait)
if [[ -n "$NOTARY_KEYCHAIN" ]]; then
  notary_submit_args+=(--keychain "$NOTARY_KEYCHAIN")
fi
xcrun "${notary_submit_args[@]}"
xcrun stapler staple "$STAGING_APP"
xcrun stapler validate "$STAGING_APP"
spctl --assess --type execute --verbose=4 "$STAGING_APP"

ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$STAGING_APP" "$FINAL_TEMP_ARCHIVE"
ditto --norsrc --noextattr --noqtn --noacl -x -k "$FINAL_TEMP_ARCHIVE" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/$APP_NAME"
spctl --assess --type execute --verbose=4 "$VERIFY_DIR/$APP_NAME"

mv -f "$FINAL_TEMP_ARCHIVE" "$FINAL_ARCHIVE"
FINAL_TEMP_ARCHIVE=""

CHECKSUM=$(shasum -a 256 "$FINAL_ARCHIVE" | awk '{print $1}')
print -r -- "artifact=$FINAL_ARCHIVE"
print -r -- "sha256=$CHECKSUM"
