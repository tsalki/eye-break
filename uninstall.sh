#!/bin/zsh
# Stop Eye Break and remove everything install.sh put in place.
# The break log is kept; delete ~/Library/Logs/eye-break*.log by hand if you want.
set -u

LABEL=com.tsalki.eye-break
BIN=$HOME/.local/bin

launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" \
      "$BIN/eye-break" \
      "$BIN/eye-break.sh" "$BIN/eye-break-helper"
rm -rf "$HOME/Library/Application Support/eye-break"
defaults delete $LABEL 2>/dev/null

print "Uninstalled. Your break log is still at ~/Library/Logs/eye-break.log"
