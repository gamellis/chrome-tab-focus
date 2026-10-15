-- ChromeTabFocus — open a URL in Chrome, reusing an existing tab if one
-- already shows that URL. Registered as an http/https handler so Finicky can
-- hand URLs to it.
--
-- Compiled as a stay-open applet: it keeps running between URLs so each click
-- reuses the warm process instead of paying an app launch. LSUIElement keeps it
-- out of the Dock, so focus never visibly leaves the app you clicked from.

-- Foundation for percent-encoding file paths and locating the bundle.
use framework "Foundation"
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

on run argv
	if class of argv is list and (count of argv) > 0 then
		my focusOrOpen(item 1 of argv)
	end if
end run

-- Tab focus and its Chrome adapter live in their own compiled scripts in
-- Contents/Resources, so tests can drive Tab focus through a fake adapter.
-- Loaded once per launch and kept: a load costs ~15ms, and the applet stays
-- open. Globals, not properties: an applet writes properties back into its own
-- bundle, which would break the code signature.
global tabFocus, chromeTabs

on focusOrOpen(theURL)
	try
		tabFocus
	on error
		set resources to (current application's NSBundle's mainBundle()'s resourcePath()) as text
		set tabFocus to load script ((resources & "/tab-focus.scpt") as POSIX file)
		set chromeTabs to load script ((resources & "/chrome-tabs-appleevents.scpt") as POSIX file)
	end try
	tabFocus's focusOrOpen(theURL, chromeTabs)
end focusOrOpen
