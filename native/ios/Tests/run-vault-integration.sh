#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
case "$developer_dir" in
  */CommandLineTools)
    if [ -d /Applications/Xcode.app/Contents/Developer ]; then
      developer_dir=/Applications/Xcode.app/Contents/Developer
    elif [ -d "$HOME/Applications/Xcode.app/Contents/Developer" ]; then
      developer_dir="$HOME/Applications/Xcode.app/Contents/Developer"
    fi
    ;;
esac
if ! DEVELOPER_DIR="$developer_dir" xcrun --find swiftc >/dev/null 2>&1; then
  echo "A full Xcode installation is required for the CryptoKit/Keychain integration harness." >&2
  exit 2
fi

binary=$(mktemp "${TMPDIR:-/tmp}/pdbridge-vault-test.XXXXXX")
trap 'rm -f "$binary"' EXIT HUP INT TERM
cd "$repo_root"
DEVELOPER_DIR="$developer_dir" xcrun swiftc \
  native/ios/Observation.swift \
  native/shared/FictionalWatchEvent.swift \
  native/ios/ObservationService.swift \
  native/ios/ProtectedObservationVault.swift \
  native/ios/ObservationBackup.swift \
  native/watch/FictionalWatchOutbox.swift \
  native/ios/Tests/vault-integration.swift \
  -o "$binary"
"$binary"
