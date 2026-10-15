#!/bin/sh
# Install the whole thing: build the ChromeTabFocus applet and make it the
# default browser.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID="io.github.gamellis.chrometabfocus"

die() { echo "$@" >&2; exit 1; }

# Resolve apps through LaunchServices rather than testing /Applications: a
# per-user or MDM-managed install lives elsewhere and is still perfectly valid.
app_path() {
  osascript -e "POSIX path of (path to application id \"$1\")" 2>/dev/null
}

[ -n "$(app_path com.google.Chrome)" ] ||
  die "Google Chrome is required — the tab reuse is Chrome-specific."

"$HERE/install-chrome-tab-focus.sh"

# Make the applet the handler for web links and local pages. macOS asks the
# user to confirm the http change ("Do you want to change your default web
# browser?") — that dialog is the only way a script may set it. The .html
# types change without asking.
osascript - "$BUNDLE_ID" <<'APPLESCRIPT'
use framework "AppKit"
use framework "UniformTypeIdentifiers"
use scripting additions
on run argv
	set ws to current application's NSWorkspace's sharedWorkspace()
	set appURL to ws's URLForApplicationWithBundleIdentifier:(item 1 of argv)
	ws's setDefaultApplicationAtURL:appURL toOpenURLsWithScheme:"http" completionHandler:(missing value)
	repeat with uti in {"public.html", "public.xhtml"}
		set t to (current application's UTType's typeWithIdentifier:(contents of uti))
		ws's setDefaultApplicationAtURL:appURL toOpenContentType:t completionHandler:(missing value)
	end repeat
	-- The calls are asynchronous; give them a moment before this process exits.
	delay 1
end run
APPLESCRIPT

cat <<'TEXT'

Installed. Two things left, both one-time and both interactive:

  1. macOS asks whether to change your default web browser to
     ChromeTabFocus — choose it. If the dialog didn't appear:
     System Settings > Desktop & Dock > Default web browser > ChromeTabFocus

  2. Click any link. macOS will ask to let ChromeTabFocus control Google
     Chrome — approve it, or the applet silently does nothing.

Then check it worked:

  ./verify.sh
TEXT

if [ -n "$(app_path se.johnste.finicky)" ]; then
  cat <<'TEXT'

Finicky is no longer needed. Once ./verify.sh passes:

  brew uninstall --cask finicky
  rm ~/.config/finicky/finicky.js   # or restore finicky.js.bak if you had one
TEXT
fi
