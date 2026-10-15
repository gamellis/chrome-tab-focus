#!/bin/sh
# Carve-outs: which URLs go to a desktop app instead of a Chrome tab.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TMPDIR_TEST=$(mktemp -d "${TMPDIR:-/tmp}/carve-outs-test.XXXXXX")
trap 'rm -rf "$TMPDIR_TEST"' EXIT HUP INT TERM

osacompile -o "$TMPDIR_TEST/carve-outs.scpt" "$ROOT/carve-outs.applescript"

osascript - "$TMPDIR_TEST/carve-outs.scpt" <<'EOF'
on run argv
	set carveOuts to load script ((item 1 of argv) as POSIX file)
	set failures to {}
	-- {URL, expected app or "chrome"}
	set cases to {¬
		{"https://linear.app/acme/issue/ES-583/some-slug", "com.linear"}, ¬
		{"https://linear.app/acme/issue/ES-583", "com.linear"}, ¬
		{"https://www.linear.app/acme/project/x", "com.linear"}, ¬
		{"https://linear.app/acme/my-issues", "com.linear"}, ¬
		{"https://linear.app/pricing", "chrome"}, ¬
		{"https://linear.app/", "chrome"}, ¬
		{"https://linear.app", "chrome"}, ¬
		{"https://linear.app/acme/changelog", "chrome"}, ¬
		{"https://notlinear.app/acme/issue/1", "chrome"}, ¬
		{"https://example.com/acme/issue/1", "chrome"}, ¬
		{"file:///tmp/issue/x.html", "chrome"}, ¬
		{"not a url", "chrome"}}
	repeat with c in cases
		set {theURL, expected} to c
		set got to carveOuts's appFor(theURL)
		if got is missing value then set got to "chrome"
		if got is not expected then set end of failures to theURL & ": expected " & expected & ", got " & got
	end repeat
	set AppleScript's text item delimiters to linefeed
	if failures is not {} then error (failures as text)
	return "carve-outs: " & (count of cases) & " cases passed"
end run
EOF
