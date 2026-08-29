#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DISTRIBUTION_PLIST="$PROJECT_DIR/Support/Distribution.plist"

usage() {
  print -u2 -- "Usage: $0 --sha256 CHECKSUM"
}

SHA256=""
while (( $# > 0 )); do
  case "$1" in
    --sha256)
      if (( $# < 2 )); then
        usage
        exit 64
      fi
      SHA256="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ ${#SHA256} -ne 64 || "$SHA256" == *[^0-9a-f]* ]]; then
  print -u2 -- "SHA-256 must contain exactly 64 lowercase hexadecimal characters."
  exit 64
fi

VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$DISTRIBUTION_PLIST")

print -r -- 'cask "external-display-viewer" do'
print -r -- "  version \"$VERSION\""
print -r -- "  sha256 \"$SHA256\""
print -r -- ''
print -r -- '  url "https://github.com/RealTake/external-display-viewer/releases/download/v#{version}/ExternalDisplayViewer-v#{version}-macOS-arm64.zip"'
print -r -- '  name "External Display Viewer"'
print -r -- '  desc "Mirror and control an extended external display from a viewer window"'
print -r -- '  homepage "https://github.com/RealTake/external-display-viewer"'
print -r -- ''
print -r -- '  depends_on arch: :arm64'
print -r -- '  depends_on macos: :sequoia'
print -r -- ''
print -r -- '  app "ExternalDisplayViewer.app"'
print -r -- 'end'
