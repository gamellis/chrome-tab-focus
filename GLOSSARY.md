# chrome-tab-focus

Every link opened on the Mac goes to the user's Chrome, reusing a tab that
already shows it instead of opening a duplicate.

## Language

**Tab focus**:
Bringing forward the tab that already shows a URL, or opening a new one when
none does.
_Avoid_: tab reuse, dedupe, routing

**User Chrome**:
The Chrome instance a person is looking at, as opposed to a headless or
automation instance launched from the same app.
_Avoid_: Chrome (unqualified, when the distinction matters)

**Match key**:
The form of a URL two tabs are compared by: trailing slashes dropped, and for
`file:` URLs, the path decoded and composed so every spelling of one file
agrees.
_Avoid_: normalized URL, canonical URL

**Matching tab**:
A tab in User Chrome whose URL has the same Match key as the URL being opened.
The frontmost window's tabs win.

**Carve-out**:
A rule that sends a URL to a desktop app instead of a Chrome tab, such as
Linear issue links going to the Linear app.
_Avoid_: handler, route, exception
