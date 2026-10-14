-- ChromeTabFocus — open a URL in Chrome, reusing an existing tab if one
-- already shows that URL. Registered as an http/https handler so Finicky can
-- hand URLs to it.
--
-- Compiled as a stay-open applet: it keeps running between URLs so each click
-- reuses the warm process instead of paying an app launch. LSUIElement keeps it
-- out of the Dock, so focus never visibly leaves the app you clicked from.

-- Foundation is here for percent-encoding; AppKit and ScriptingBridge for
-- finding and driving the right Chrome process (see userChrome). Loading them
-- costs time once at launch, not per URL, because the applet stays open.
use framework "Foundation"
use framework "AppKit"
use framework "ScriptingBridge"
use scripting additions

on open location this_URL
	my focusOrOpen(this_URL)
end open location

-- Files, not URLs. Because Finicky is the default handler for public.html, a
-- plain `open page.html` reaches Finicky, which hands the *file* to the default
-- browser — us. Without this handler (and the matching CFBundleDocumentTypes in
-- the installer) macOS refuses with "ChromeTabFocus cannot open files in the
-- 'HTML text' format" and the page never opens.
on open theFiles
	repeat with f in theFiles
		my focusOrOpen(my fileURLFor(POSIX path of f))
	end repeat
end open

-- POSIX path -> file:// URL, encoded the way Chrome encodes one. Chrome leaves
-- most punctuation literal and escapes only space, non-ASCII, and # ; ? % { }
-- (and the rest of the unsafe set). Escaping more than that is not merely ugly
-- in the URL bar: a tab Chrome opened itself, from Finder or a link, carries
-- Chrome's spelling, and a string that doesn't match it opens a duplicate.
--
-- Deliberately not NSURL's fileURLWithPath: its absoluteString escapes [ and ]
-- where Chrome leaves them literal, so it is not the rule we need to match.
on fileURLFor(posixPath)
	set allowed to current application's NSCharacterSet's ¬
		characterSetWithCharactersInString:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,/:=@[]"
	set s to current application's NSString's stringWithString:posixPath
	return "file://" & ((s's stringByAddingPercentEncodingWithAllowedCharacters:allowed) as text)
end fileURLFor

-- Decode and normalize only the path of a file: URL into something two
-- spellings of the same path both reduce to. The component boundary matters:
-- "%23" in a path names a literal #, while an unescaped # starts a fragment
-- (and likewise for "%3F" and a query). Decoding the whole URL would collapse
-- those distinct resources.
--
-- `POSIX path of` hands us the filesystem representation, which is NFD, while
-- a tab Chrome opened from Finder carries the NFC form from disk. Composing the
-- decoded path explicitly makes "caf%C3%A9" and "cafe%CC%81" compare equal.
-- Re-encoding it before rebuilding the URL protects the query and fragment
-- delimiters. Returns the input unchanged if it isn't parseable or decodable.
on decodedURL(u)
	set s to current application's NSString's stringWithString:u
	set components to current application's NSURLComponents's componentsWithString:s
	if components is missing value then return u
	set encodedPath to components's percentEncodedPath()
	set d to encodedPath's stringByRemovingPercentEncoding()
	if d is missing value then return u
	set normalizedPath to d's precomposedStringWithCanonicalMapping()
	-- Keep / literal, but escape #, ? and % so path data cannot become URL
	-- structure when NSURLComponents rebuilds the string.
	set pathAllowed to current application's NSCharacterSet's ¬
		characterSetWithCharactersInString:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,/:=@[]"
	set encodedNormalizedPath to normalizedPath's ¬
		stringByAddingPercentEncodingWithAllowedCharacters:pathAllowed
	if encodedNormalizedPath is missing value then return u
	components's setPercentEncodedPath:encodedNormalizedPath
	return (components's |string|()) as text
end decodedURL

on run argv
	if class of argv is list and (count of argv) > 0 then
		my focusOrOpen(item 1 of argv)
	end if
end run

-- Trailing slashes are cosmetic; treat ".../pull/1" and ".../pull/1/" as one.
on normalizeURL(u)
	set s to u as text
	repeat while s ends with "/"
		if (count of s) is 1 then exit repeat
		set s to text 1 thru -2 of s
	end repeat
	return s
end normalizeURL

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

on focusOrOpen(theURL)
	set wanted to my normalizeURL(theURL)
	-- file: URLs compare decoded, so two spellings of the same path still match.
	-- Only file: URLs: decoding every tab URL would add a bridged call per tab,
	-- and for http the string Chrome reports is already the string we were given.
	set wantIsFile to wanted starts with "file:"
	if wantIsFile then set wanted to my decodedURL(wanted)

	set chrome to my userChrome()
	if chrome is missing value then
		my launchChromeWith(theURL)
		return
	end if

	-- Index 0 is the front window, as with AppleScript's `window 1`.
	set wins to chrome's |windows|()
	set winCount to (wins's |count|()) as integer
	repeat with wi from 0 to winCount - 1
		set w to (wins's objectAtIndex:wi)
		-- One Apple event per window rather than one per tab: with many tabs
		-- open, per-tab round trips dominate the whole operation.
		set tabURLs to (w's tabs()'s arrayByApplyingSelector:"URL") as list
		repeat with ti from 1 to (count of tabURLs)
			set tabURL to my normalizeURL(item ti of tabURLs)
			if wantIsFile and tabURL starts with "file:" then ¬
				set tabURL to my decodedURL(tabURL)
			if tabURL is wanted then
				-- KNOWN LIMITATION: this does not deminiaturize. If the
				-- matching tab lives in a minimized window, the click looks
				-- like it did nothing at all. Confirmed, deliberately not
				-- fixed; see the README.
				--
				-- try/end try because Chrome's `index` is historically
				-- unreliable: without it a failure here aborts after the tab
				-- was selected but before `activate`, so Chrome never comes
				-- forward and the click silently does nothing.
				w's setActiveTabIndex:ti
				try
					w's setIndex:1
				end try
				chrome's |activate|()
				return
			end if
		end repeat
	end repeat

	-- No match: open a new tab in the frontmost window.
	--
	-- Elements are built from the base SBObject and the sdef's four-char codes
	-- ('cwin' window, 'CrTb' tab). The classes classForScriptingClass: hands
	-- back can't be instantiated from AppleScriptObjC: every init throws
	-- "object has not been added to a container yet".
	if winCount is 0 then
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
end focusOrOpen

on fourCharCode(s)
	set n to 0
	repeat with c in (characters of s)
		set n to n * 256 + (id of c)
	end repeat
	return n
end fourCharCode
