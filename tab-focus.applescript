-- Tab focus: bring forward the tab that already shows a URL, or open a new one.
--
--   focusOrOpen(theURL, chromeTabs)
--
-- chromeTabs is the adapter for whatever Chrome is reachable through. It
-- answers three calls, and nothing here looks past them:
--
--   findTab(matcher)  the first tab, front window first, for which
--                     matcher's matches(tabURL) is true — as an opaque ref the
--                     adapter alone understands — or missing value. Taking the
--                     predicate rather than returning every tab lets an adapter
--                     stop reading Chrome at the first hit.
--   focusTab(tabRef)  select that tab, raise its window, activate Chrome.
--   openTab(theURL)   open the URL in a new tab, however this Chrome needs it:
--                     launch, new window, or new tab in the front window.
--
-- What counts as the same tab is decided here, once, by matchKey; adapters
-- never compare URLs themselves.
use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

on focusOrOpen(theURL, chromeTabs)
	set tabRef to chromeTabs's findTab(my matcherFor(theURL))
	if tabRef is missing value then
		chromeTabs's openTab(theURL)
	else
		chromeTabs's focusTab(tabRef)
	end if
end focusOrOpen

on matcherFor(theURL)
	set wantedKey to my matchKey(theURL)
	set tabFocus to me
	script
		property wanted : wantedKey
		on matches(tabURL)
			return (tabFocus's matchKey(tabURL)) is wanted
		end matches
	end script
	return result
end matcherFor

-- The form two URLs are compared by. Trailing slashes are cosmetic, so
-- ".../pull/1" and ".../pull/1/" agree. file: URLs additionally compare
-- decoded, so two spellings of the same path still match. Only file: URLs:
-- decoding costs a bridged call, and for http the string Chrome reports is
-- already the string we were given.
on matchKey(u)
	set s to u as text
	repeat while s ends with "/"
		if (count of s) is 1 then exit repeat
		set s to text 1 thru -2 of s
	end repeat
	if s starts with "file:" then set s to my decodedURL(s)
	return s
end matchKey

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
