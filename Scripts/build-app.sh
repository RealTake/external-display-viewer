#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="$PROJECT_DIR/build"
APP_LINK="$BUILD_DIR/ExternalDisplayViewer.app"
ARCHIVE="$BUILD_DIR/ExternalDisplayViewer-macOS-arm64.zip"
EXECUTABLE="$PROJECT_DIR/.build/release/ExternalDisplayViewer"
INFO_PLIST="$PROJECT_DIR/Support/Info.plist"

resolve_signing_identity() {
  if [[ -n "${EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY:-}" ]]; then
    print -r -- "$EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY"
    return
  fi

  local identity_line
  if ! identity_line=$(security find-identity -v -p codesigning | grep -m 1 '"Apple Development:'); then
    print -u2 -- "A stable Apple Development signing identity is required. Set EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY to a valid code-signing identity."
    return 1
  fi

  identity_line=${identity_line#*\"}
  print -r -- "${identity_line%%\"*}"
}

SIGNING_IDENTITY=$(resolve_signing_identity)
if ! security find-identity -v -p codesigning | grep -F -- "\"$SIGNING_IDENTITY\"" >/dev/null; then
  print -u2 -- "Code-signing identity not found: $SIGNING_IDENTITY"
  exit 1
fi

APPLICATION_SUPPORT_DIR=$(swift -e 'import Foundation; print(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path)')
if [[ -z "$APPLICATION_SUPPORT_DIR" || "$APPLICATION_SUPPORT_DIR" != /* || "$APPLICATION_SUPPORT_DIR" == "/" ]]; then
  print -u2 -- "Invalid Application Support directory: $APPLICATION_SUPPORT_DIR"
  exit 1
fi

DURABLE_ROOT="$APPLICATION_SUPPORT_DIR/ExternalDisplayViewer"
DURABLE_APP="$DURABLE_ROOT/ExternalDisplayViewer.app"
STAGING_ROOT=""
STAGING_APP=""
NEXT_APP=""
BACKUP_APP=""
LEGACY_APP=""
TEMP_ARCHIVE=""
PROMOTED=0
LINK_INSTALLED=0

cleanup() {
  local exit_code=$?

  if [[ -n "$STAGING_ROOT" && -d "$STAGING_ROOT" ]]; then
    rm -rf "$STAGING_ROOT"
  fi
  if [[ -n "$NEXT_APP" && -e "$NEXT_APP" ]]; then
    rm -rf "$NEXT_APP"
  fi
  if [[ -n "$TEMP_ARCHIVE" && -e "$TEMP_ARCHIVE" ]]; then
    rm -f "$TEMP_ARCHIVE"
  fi

  if (( exit_code != 0 )); then
    if (( LINK_INSTALLED == 1 )) && [[ -L "$APP_LINK" ]]; then
      rm "$APP_LINK"
    fi
    if [[ -n "$LEGACY_APP" && -e "$LEGACY_APP" && ! -e "$APP_LINK" ]]; then
      mv "$LEGACY_APP" "$APP_LINK"
      LEGACY_APP=""
    fi
    if (( PROMOTED == 1 )); then
      rm -rf "$DURABLE_APP"
      if [[ -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$DURABLE_APP"
        BACKUP_APP=""
      fi
    fi
  fi

  if [[ -n "$BACKUP_APP" && -e "$BACKUP_APP" ]]; then
    rm -rf "$BACKUP_APP"
  fi
  if [[ -n "$LEGACY_APP" && -e "$LEGACY_APP" ]]; then
    rm -rf "$LEGACY_APP"
  fi

  return "$exit_code"
}
trap cleanup EXIT INT TERM

cd "$PROJECT_DIR"
swift build -c release --disable-sandbox

mkdir -p "$BUILD_DIR"
if [[ -L "$DURABLE_ROOT" ]]; then
  print -u2 -- "Refusing symlinked durable directory: $DURABLE_ROOT"
  exit 1
fi
mkdir -p "$DURABLE_ROOT"

STAGING_ROOT=$(mktemp -d /private/tmp/external-display-viewer-build.XXXXXX)
STAGING_APP="$STAGING_ROOT/ExternalDisplayViewer.app"
VERIFY_DIR="$STAGING_ROOT/verify"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources" "$VERIFY_DIR"
cp "$EXECUTABLE" "$STAGING_APP/Contents/MacOS/ExternalDisplayViewer"
cp "$INFO_PLIST" "$STAGING_APP/Contents/Info.plist"
chmod 755 "$STAGING_APP/Contents/MacOS/ExternalDisplayViewer"
plutil -lint "$STAGING_APP/Contents/Info.plist"
xattr -cr "$STAGING_APP"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$STAGING_APP"
codesign --verify --deep --strict "$STAGING_APP"

TEMP_ARCHIVE="$BUILD_DIR/.ExternalDisplayViewer-macOS-arm64.${$}.zip"
ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$STAGING_APP" "$TEMP_ARCHIVE"
ditto --norsrc --noextattr --noqtn --noacl -x -k "$TEMP_ARCHIVE" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/ExternalDisplayViewer.app"

NEXT_APP="$DURABLE_ROOT/.ExternalDisplayViewer.next-${$}.app"
BACKUP_APP="$DURABLE_ROOT/.ExternalDisplayViewer.backup-${$}.app"
ditto --norsrc --noextattr --noqtn --noacl "$STAGING_APP" "$NEXT_APP"
codesign --verify --deep --strict "$NEXT_APP"

if [[ -e "$DURABLE_APP" || -L "$DURABLE_APP" ]]; then
  mv "$DURABLE_APP" "$BACKUP_APP"
fi
mv "$NEXT_APP" "$DURABLE_APP"
NEXT_APP=""
PROMOTED=1
codesign --verify --deep --strict "$DURABLE_APP"

LEGACY_APP="$BUILD_DIR/.ExternalDisplayViewer.legacy-${$}.app"
if [[ -L "$APP_LINK" ]]; then
  rm "$APP_LINK"
elif [[ -e "$APP_LINK" ]]; then
  mv "$APP_LINK" "$LEGACY_APP"
fi
ln -s "$DURABLE_APP" "$APP_LINK"
LINK_INSTALLED=1
codesign --verify --deep --strict "$APP_LINK"

mv -f "$TEMP_ARCHIVE" "$ARCHIVE"
TEMP_ARCHIVE=""

print -r -- "Signed with: $SIGNING_IDENTITY"
print -r -- "$APP_LINK"
