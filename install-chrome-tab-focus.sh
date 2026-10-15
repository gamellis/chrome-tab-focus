#!/bin/sh
# Build ChromeTabFocus.app from the AppleScript source and register it as an
# http/https handler, so it can be the default browser.
#
# Safe to re-run: this is also the edit-test loop. After changing the
# AppleScript you must re-run this, or the old compiled applet keeps handling
# URLs and your edit appears to do nothing.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/chrome-tab-focus.applescript"
APP="$HOME/Applications/ChromeTabFocus.app"
PLIST="$APP/Contents/Info.plist"
BUNDLE_ID="io.github.gamellis.chrometabfocus"
LEGACY_BUNDLE_ID="local.chrometabfocus"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Stop the running applet, including a pre-rename build. A stay-open applet
# whose bundle was deleted underneath it keeps serving URLs until logout, so
# fall back to pkill if the polite quit doesn't land.
for id in "$BUNDLE_ID" "$LEGACY_BUNDLE_ID"; do
  osascript -e "tell application id \"$id\" to quit" 2>/dev/null || true
done
pkill -f "ChromeTabFocus.app" 2>/dev/null || true

[ -e "$APP" ] && "$LSREGISTER" -u "$APP" 2>/dev/null
rm -rf "$APP"

# ~/Applications is not created by default on macOS, and osacompile will not
# create intermediate directories — it fails with coreFoundationUnknownErr.
mkdir -p "$HOME/Applications"

# -s: stay-open applet, so the process stays warm between URLs instead of
# cold-launching on every click.
osacompile -s -o "$APP" "$SRC"

# Tab focus, its Chrome adapter and the carve-outs, which the applet loads from
# Resources at first use. Compiled before signing, so the signature covers them.
for lib in tab-focus chrome-tabs-appleevents carve-outs; do
  osacompile -o "$APP/Contents/Resources/$lib.scpt" "$ROOT/$lib.applescript"
done

plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleURLTypes \
  -json '[{"CFBundleURLName":"Web","CFBundleURLSchemes":["http","https","file"]}]' "$PLIST"
# Local pages arrive as documents, not URLs: `open page.html` hands the file to
# the default handler for public.html. Without this claim macOS refuses with
# "ChromeTabFocus cannot open files in the 'HTML text' format".
#
# Rank Alternate, not Default: install.sh makes this the .html handler
# explicitly, so the rank only matters to someone who never ran it — and they
# didn't ask for their .html files to change hands.
plutil -replace CFBundleDocumentTypes \
  -json '[{"CFBundleTypeName":"Web page","CFBundleTypeRole":"Viewer",
           "LSHandlerRank":"Alternate",
           "LSItemContentTypes":["public.html","public.xhtml"]}]' "$PLIST"
plutil -replace NSAppleEventsUsageDescription \
  -string "Focus an existing Chrome tab." "$PLIST"
# Agent app: no Dock icon, no app switch when handling a URL.
plutil -replace LSUIElement -bool true "$PLIST"

# Ad-hoc signing gives the bundle a code identity so macOS will grant it
# automation access at all. Note the tradeoff: the identity changes on every
# rebuild, so TCC may re-prompt after re-running this — or, with a stale grant
# on record, silently deny, at which point the applet does nothing. If clicking
# links stops working after a rebuild, reset the grant and click again:
#
#   tccutil reset AppleEvents io.github.gamellis.chrometabfocus
#
# --deep is deliberately absent: Apple deprecated it for signing, and this is a
# single bundle with nothing nested to sign.
codesign --force -s - "$APP"
"$LSREGISTER" -f "$APP"

echo "Installed $APP"
echo "First use will prompt to allow controlling Google Chrome — approve it."
