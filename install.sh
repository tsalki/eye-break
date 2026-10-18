#!/bin/zsh
# Build and install Eye Break for the current user, then start it.
# Safe to re-run: it replaces the installed copy.
set -euo pipefail
cd "${0:A:h}"

LABEL=com.tsalki.eye-break
BIN=$HOME/.local/bin
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist
DOMAIN=gui/$(id -u)

if ! command -v swiftc >/dev/null; then
  print -u2 "swiftc not found. Install Apple's Command Line Tools first:  xcode-select --install"
  exit 1
fi

print "Building…"
mkdir -p "$BIN" "${PLIST:h}"
swiftc -O src/*.swift -o "$BIN/eye-break"
sed -e "s|__BIN__|$BIN|g" -e "s|__HOME__|$HOME|g" src/$LABEL.plist > "$PLIST"

# Files from the earlier zsh version.
rm -f "$BIN/eye-break.sh" "$BIN/eye-break-helper"

if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "$DOMAIN/$LABEL" || true
  # bootout can return before the old copy has exited; bootstrap fails until it has.
  for _ in {1..20}; do
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
    sleep 0.5
  done
fi
launchctl bootstrap "$DOMAIN" "$PLIST"

print "Installed. Eye Break is in your menu bar and will start at every login."
