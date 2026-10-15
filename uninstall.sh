#!/bin/sh
# Back out.
#
# Order matters here. Removing the applet while it is still the default
# browser leaves you with a default browser that routes nowhere — every link
# dead, and you need a browser to look up the fix. So the default-browser step
# comes first, and it's yours: macOS won't let a script set it silently.
set -eu

APP="$HOME/Applications/ChromeTabFocus.app"
BUNDLE_ID="io.github.gamellis.chrometabfocus"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

default_browser() {
  osascript -e 'use framework "AppKit"' \
    -e 'set u to current application'"'"'s NSURL'"'"'s URLWithString:"https://example.com"' \
    -e 'set a to current application'"'"'s NSWorkspace'"'"'s sharedWorkspace()'"'"'s URLForApplicationToOpenURL:u' \
    -e '((current application'"'"'s NSBundle'"'"'s bundleWithURL:a)'"'"'s bundleIdentifier()) as text' 2>/dev/null
}

if [ "$(default_browser)" = "$BUNDLE_ID" ]; then
  cat <<'TEXT'
ChromeTabFocus is still your default browser.

Set it back FIRST — System Settings > Desktop & Dock > Default web browser —
or you'll be left with no working browser and no easy way to look up why.

Re-run this script once that's done.
TEXT
  exit 1
fi

for id in "$BUNDLE_ID" local.chrometabfocus; do
  osascript -e "tell application id \"$id\" to quit" 2>/dev/null || true
done
pkill -f "ChromeTabFocus.app" 2>/dev/null || true

# Unregister before deleting, or a handler entry pointing at a missing bundle
# lingers in the default-browser list until the LS database is rebuilt.
[ -e "$APP" ] && "$LSREGISTER" -u "$APP" 2>/dev/null
rm -rf "$APP"

echo "Removed ChromeTabFocus."
