#!/usr/bin/env bash

# Builds dock-gap-fix.swift and runs it as a LaunchAgent at login, so a hidden Dock whose space
# macOS keeps reserved, leaving maximized windows short of the screen's bottom edge, gets cleared by
# restarting the Dock and then WindowManager, without anyone noticing. It logs each restart to
# ~/Library/Logs/dock-gap-fix.log. Mac only; needs swiftc from Xcode or its command line tools.
# Run it again after changing the Swift file or after a macOS update stopped the agent.
#
# Growing Claude's short window back needs Accessibility permission, which macOS ties to the
# signature. It signs with the code signing identity named on the one line of signing-identity
# beside this script, so a rebuild keeps the permission, or ad hoc without that file, so each
# rebuild asks again.
#
#   install.sh               build, install and start the agent
#   install.sh --uninstall   stop and remove the agent; the log stays

set -eu

dir="$(cd "$(dirname "$0")" && pwd)"
label=local.claude.dock-gap-fix
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
log="$HOME/Library/Logs/dock-gap-fix.log"

launchctl bootout "$domain/$label" 2>/dev/null || true
if [ "${1:-}" = --uninstall ]; then
  rm -f "$plist" "$dir/dock-gap-fix"
  exit 0
fi

swiftc -O -o "$dir/dock-gap-fix" "$dir/dock-gap-fix.swift"
identity=-
if [ -s "$dir/signing-identity" ]; then
  identity="$(head -n 1 "$dir/signing-identity")"
fi
codesign --force --sign "$identity" --identifier "$label" --timestamp=none "$dir/dock-gap-fix"
mkdir -p "$HOME/Library/LaunchAgents"
cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$dir/dock-gap-fix</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$log</string>
  <key>StandardErrorPath</key>
  <string>$log</string>
</dict>
</plist>
EOF
plutil -lint -s "$plist"

# A bootout can still be settling, and bootstrap then fails with error 5.
for _ in 1 2 3 4 5; do
  launchctl bootstrap "$domain" "$plist" 2>/dev/null && exit 0
  sleep 1
done
launchctl bootstrap "$domain" "$plist"
