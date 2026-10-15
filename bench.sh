#!/bin/sh
# Time a click that should focus an existing tab: from `open <url>` until
# Chrome's front window shows that tab. Reports median and p90.
#
#   ./bench.sh [runs] [filler-tabs]
#
# Measures two paths, so a router in front of the applet (Finicky, before it
# was dropped) can be told apart from the applet itself:
#   default  `open <url>`, through whatever the default browser is, the way
#            every real click arrives
#   direct   `open -b <applet> <url>`, straight to the applet
#
# And two tab counts: your windows as they are, then with a throwaway window of
# filler tabs in front, which the applet must scan before reaching the target.
#
# This drives your real Chrome while it runs: it opens a target window and a
# filler window, shuffles them, and closes both at the end. Don't type into
# Chrome until it finishes.
set -eu

RUNS=${1:-10}
FILLER=${2:-50}
BUNDLE_ID="io.github.gamellis.chrometabfocus"
TARGET="https://example.com/?chrome-tab-focus-bench"

if ! pgrep -x "Google Chrome" >/dev/null; then
  echo "Start Chrome first: this measures focusing a tab in a running Chrome." >&2
  exit 1
fi

# Everything runs in one osascript so the poll loop's own overhead is a tight
# Apple event per check, not a process launch.
osascript - "$RUNS" "$FILLER" "$BUNDLE_ID" "$TARGET" <<'EOF'
use framework "Foundation"
use scripting additions

on now()
	return (current application's NSProcessInfo's processInfo()'s systemUptime()) as real
end now

-- Put the target window at the back, behind every window the applet scans,
-- with the target tab inactive; put the filler window (if any) in front.
on reset(targetWin, fillerWin)
	tell application "Google Chrome"
		set active tab index of targetWin to 1
		set index of targetWin to (count of windows)
		if fillerWin is not missing value then set index of fillerWin to 1
	end tell
	delay 0.3
end reset

on landed(target)
	tell application "Google Chrome"
		try
			return (URL of active tab of front window) is target
		on error
			return false
		end try
	end tell
end landed

on timeOne(openCmd, target, targetWin, fillerWin)
	my reset(targetWin, fillerWin)
	set t0 to my now()
	do shell script openCmd
	repeat
		if my landed(target) then exit repeat
		if (my now()) - t0 > 5 then error "timed out waiting for " & target
		delay 0.005
	end repeat
	return ((my now()) - t0) * 1000
end timeOne

on sorted(xs)
	set a to current application's NSArray's arrayWithArray:xs
	return (a's sortedArrayUsingSelector:"compare:") as list
end sorted

on pct(xs, p)
	set s to my sorted(xs)
	set i to (round ((count of s) * p) rounding up)
	if i < 1 then set i to 1
	return round (item i of s)
end pct

on bench(label, openCmd, runs, target, targetWin, fillerWin)
	my timeOne(openCmd, target, targetWin, fillerWin) -- warm-up, discarded
	set xs to {}
	repeat runs times
		set end of xs to my timeOne(openCmd, target, targetWin, fillerWin)
	end repeat
	return label & "  median " & my pct(xs, 0.5) & "ms  p90 " & my pct(xs, 0.9) & "ms"
end bench

on run argv
	set runs to (item 1 of argv) as integer
	set filler to (item 2 of argv) as integer
	set bundleId to item 3 of argv
	set target to item 4 of argv

	tell application "Google Chrome"
		set targetWin to make new window
		set URL of active tab of targetWin to "about:blank"
		tell targetWin to make new tab with properties {URL:target}
		set userTabs to 0
		repeat with w in windows
			set userTabs to userTabs + (count of tabs of w)
		end repeat
		set userTabs to userTabs - 2
		set userWins to (count of windows) - 1
	end tell

	set defaultCmd to "open " & quoted form of target
	set directCmd to "open -b " & quoted form of bundleId & " " & quoted form of target
	set out to {}
	set fillerWin to missing value
	set end of out to "your windows (" & userWins & " windows, " & userTabs & " tabs), " & runs & " runs"
	try
		set end of out to my bench("  default", defaultCmd, runs, target, targetWin, missing value)
		set end of out to my bench("  direct ", directCmd, runs, target, targetWin, missing value)

		if filler > 0 then
			tell application "Google Chrome"
				set fillerWin to make new window
				repeat with i from 2 to filler
					tell fillerWin to make new tab with properties {URL:"about:blank#" & i}
				end repeat
			end tell
			set end of out to "+ " & filler & " filler tabs in front"
			set end of out to my bench("  default", defaultCmd, runs, target, targetWin, fillerWin)
			set end of out to my bench("  direct ", directCmd, runs, target, targetWin, fillerWin)
		end if
	on error e
		set end of out to "error: " & e
	end try
	tell application "Google Chrome"
		try
			close targetWin
		end try
		if fillerWin is not missing value then
			try
				close fillerWin
			end try
		end if
	end tell
	set AppleScript's text item delimiters to linefeed
	return out as text
end run
EOF
