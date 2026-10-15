-- Carve-outs: URLs that belong to a desktop app rather than a Chrome tab.
--
--   appFor(theURL)  the bundle id of the app that should open theURL, or
--                   missing value to let Tab focus have it.
--
-- To add your own, add a branch below and re-run
-- ./install-chrome-tab-focus.sh. The applet falls back to Chrome when the
-- named app isn't installed, so a carve-out for an app you remove is harmless.
use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

on appFor(theURL)
	set components to current application's NSURLComponents's componentsWithString:theURL
	if components is missing value then return missing value
	set rawHost to components's |host|()
	if rawHost is missing value then return missing value
	set hostName to (rawHost's lowercaseString()) as text
	set urlPath to (components's |path|()) as text

	-- ---8<--- Linear carve-out. Delete this whole branch if you don't use
	-- Linear, and every URL goes to Chrome.
	if hostName is in {"linear.app", "www.linear.app"} then
		-- Second path segment of an in-app route:
		-- https://linear.app/<workspace>/<route>/...
		set segments to my split(urlPath, "/")
		-- split of "/ws/issue/X" is {"", "ws", "issue", "X"}
		if (count of segments) ≥ 3 then
			if item 3 of segments is in {"issue", "project", "projects", "initiative", "initiatives", "team", ¬
				"view", "document", "search", "settings", "inbox", "my-issues", ¬
				"roadmap", "cycle", "label", "profile", "notification"} then return "com.linear"
		end if
	end if
	-- ---8<--- end Linear carve-out.

	return missing value
end appFor

on split(s, delimiter)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delimiter
	set parts to text items of s
	set AppleScript's text item delimiters to saved
	return parts
end split
