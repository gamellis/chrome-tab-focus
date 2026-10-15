#!/bin/sh
# Tab focus, driven through its interface with a fake Chrome adapter: no Chrome
# needed, so this runs anywhere osascript does.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TMPDIR_TEST=$(mktemp -d "${TMPDIR:-/tmp}/tab-focus-test.XXXXXX")
trap 'rm -rf "$TMPDIR_TEST"' EXIT HUP INT TERM

osacompile -o "$TMPDIR_TEST/tab-focus.scpt" "$ROOT/tab-focus.applescript"

osascript - "$TMPDIR_TEST/tab-focus.scpt" <<'EOF'
-- A Chrome made of lists: each window is a list of tab URLs, front first.
-- Records what Tab focus asked of it, so a case can assert on the outcome.
on fakeChrome(wins)
	script
		property windowsList : wins
		property did : "nothing"
		on findTab(matcher)
			repeat with wi from 1 to (count of windowsList)
				set tabURLs to item wi of windowsList
				repeat with ti from 1 to (count of tabURLs)
					if matcher's matches(item ti of tabURLs) then return {wi, ti}
				end repeat
			end repeat
			return missing value
		end findTab
		on focusTab(tabRef)
			set did to "focus " & (item 1 of tabRef) & "," & (item 2 of tabRef)
		end focusTab
		on openTab(theURL)
			set did to "open " & theURL
		end openTab
	end script
	return result
end fakeChrome

on run argv
	set tabFocus to load script ((item 1 of argv) as POSIX file)
	set failures to {}

	-- {label, windows, URL opened, expected outcome}
	set cases to {¬
		{"match in a later window", {{"https://a.test/1"}, {"https://a.test/x", "https://a.test/2"}}, "https://a.test/2", "focus 2,2"}, ¬
		{"no match opens", {{"https://a.test/1"}}, "https://a.test/2", "open https://a.test/2"}, ¬
		{"front window wins", {{"https://a.test/x", "https://a.test/2"}, {"https://a.test/2"}}, "https://a.test/2", "focus 1,2"}, ¬
		{"no windows opens", {}, "https://a.test/2", "open https://a.test/2"}, ¬
		{"trailing slash on the tab", {{"https://a.test/pull/1/"}}, "https://a.test/pull/1", "focus 1,1"}, ¬
		{"trailing slash on the URL", {{"https://a.test/pull/1"}}, "https://a.test/pull/1/", "focus 1,1"}, ¬
		{"query differs", {{"https://a.test/p?x=1"}}, "https://a.test/p?x=2", "open https://a.test/p?x=2"}, ¬
		{"http is not decoded", {{"https://a.test/caf%C3%A9"}}, "https://a.test/café", "open https://a.test/café"}, ¬
		{"file: NFD and NFC agree", {{"file:///tmp/caf%C3%A9.html"}}, "file:///tmp/cafe%CC%81.html", "focus 1,1"}, ¬
		{"file: encoded and literal agree", {{"file:///tmp/a%20b.html"}}, "file:///tmp/a b.html", "focus 1,1"}, ¬
		{"file: encoded # is not a fragment", {{"file:///tmp/report.html#intro"}}, "file:///tmp/report.html%23intro", "open file:///tmp/report.html%23intro"}, ¬
		{"file: encoded ? is not a query", {{"file:///tmp/report.html?print"}}, "file:///tmp/report.html%3Fprint", "open file:///tmp/report.html%3Fprint"}, ¬
		{"file: query and fragment kept apart", {{"file://server/share/report%23draft.html?mode=print#intro"}}, "file://server/share/report%23draft.html?mode=print#intro", "focus 1,1"}, ¬
		{"file: structure is not collapsed", {{"file://server/share/report#draft.html?mode=print"}}, "file://server/share/report%23draft.html?mode=print", "open file://server/share/report%23draft.html?mode=print"}}

	repeat with c in cases
		set {label, wins, theURL, expected} to c
		set chrome to my fakeChrome(wins)
		tabFocus's focusOrOpen(theURL, chrome)
		if (did of chrome) is not expected then ¬
			set end of failures to label & ": expected '" & expected & "', got '" & (did of chrome) & "'"
	end repeat

	set AppleScript's text item delimiters to linefeed
	if failures is not {} then error (failures as text)
	return "tab focus: " & (count of cases) & " cases passed"
end run
EOF
