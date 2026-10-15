-- Chrome tabs over Apple events: the adapter Tab focus uses to reach the
-- user's Chrome. See tab-focus.applescript for the three calls it answers.
--
-- A tab ref here is {chrome, window, tab index}. Nothing outside this file
-- looks inside one.

-- AppKit and ScriptingBridge for finding and driving the right Chrome process
-- (see userChrome).
use AppleScript version "2.4"
use framework "Foundation"
use framework "AppKit"
use framework "ScriptingBridge"
use scripting additions

on findTab(matcher)
	set chrome to my userChrome()
	if chrome is missing value then return missing value
	-- Index 0 is the front window, as with AppleScript's `window 1`.
	set wins to chrome's |windows|()
	repeat with wi from 0 to ((wins's |count|()) as integer) - 1
		set w to (wins's objectAtIndex:wi)
		-- One Apple event per window rather than one per tab: with many tabs
		-- open, per-tab round trips dominate the whole operation.
		set tabURLs to (w's tabs()'s arrayByApplyingSelector:"URL") as list
		repeat with ti from 1 to (count of tabURLs)
			if matcher's matches(item ti of tabURLs) then return {chrome, w, ti}
		end repeat
	end repeat
	return missing value
end findTab

on focusTab(tabRef)
	set {chrome, w, ti} to tabRef
	-- KNOWN LIMITATION: this does not deminiaturize. If the matching tab lives
	-- in a minimized window, the click looks like it did nothing at all.
	-- Confirmed, deliberately not fixed; see the README.
	--
	-- try/end try because Chrome's `index` is historically unreliable: without
	-- it a failure here aborts after the tab was selected but before
	-- `activate`, so Chrome never comes forward and the click silently does
	-- nothing.
	w's setActiveTabIndex:ti
	try
		w's setIndex:1
	end try
	chrome's |activate|()
end focusTab

-- Elements are built from the base SBObject and the sdef's four-char codes
-- ('cwin' window, 'CrTb' tab). The classes classForScriptingClass: hands back
-- can't be instantiated from AppleScriptObjC: every init throws "object has
-- not been added to a container yet".
on openTab(theURL)
	set chrome to my userChrome()
	if chrome is missing value then
		my launchChromeWith(theURL)
		return
	end if
	set wins to chrome's |windows|()
	if ((wins's |count|()) as integer) is 0 then
		set newWin to current application's SBObject's alloc()'s ¬
			initWithElementCode:(my fourCharCode("cwin")) |properties|:(missing value) |data|:(missing value)
		wins's addObject:newWin
		((chrome's |windows|()'s objectAtIndex:0)'s activeTab())'s setURL:theURL
	else
		set newTab to current application's SBObject's alloc()'s ¬
			initWithElementCode:(my fourCharCode("CrTb")) |properties|:{|URL|:theURL} |data|:(missing value)
		((wins's objectAtIndex:0)'s tabs())'s addObject:newTab
	end if
	chrome's |activate|()
end openTab

-- The Chrome a person is using, as a ScriptingBridge object addressed by pid,
-- or missing value if there isn't one.
--
-- Not `tell application "Google Chrome"`: that resolves by bundle id, and while
-- a second Chrome process is running — the headless one Selenium, Puppeteer et
-- al. launch from the same .app for system tests — it can resolve to that one
-- instead. Every link then opens in an invisible browser and the click appears
-- to do nothing. Headless and automation instances never have a regular
-- activation policy, so that is what tells them apart.
on userChrome()
	set apps to current application's NSRunningApplication's ¬
		runningApplicationsWithBundleIdentifier:"com.google.Chrome"
	repeat with a in (apps as list)
		if (a's activationPolicy()) is (current application's NSApplicationActivationPolicyRegular) then ¬
			return current application's SBApplication's ¬
				applicationWithProcessIdentifier:(a's processIdentifier())
	end repeat
	return missing value
end userChrome

-- Chrome isn't running, or only a headless instance is. Launch a new instance
-- with the URL rather than `open location`, which LaunchServices may hand to
-- that headless instance.
on launchChromeWith(theURL)
	set ws to current application's NSWorkspace's sharedWorkspace()
	set appURL to ws's URLForApplicationWithBundleIdentifier:"com.google.Chrome"
	if appURL is missing value then return
	set config to current application's NSWorkspaceOpenConfiguration's configuration()
	config's setCreatesNewApplicationInstance:true
	set u to current application's NSURL's URLWithString:theURL
	if u is missing value then
		set urls to current application's NSArray's array()
	else
		set urls to current application's NSArray's arrayWithObject:u
	end if
	ws's openURLs:urls withApplicationAtURL:appURL configuration:config completionHandler:(missing value)
end launchChromeWith

on fourCharCode(s)
	set n to 0
	repeat with c in (characters of s)
		set n to n * 256 + (id of c)
	end repeat
	return n
end fourCharCode
