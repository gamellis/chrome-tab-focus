# finicky-tab-focus

Click a link anywhere on your Mac. If that URL is already open in a Chrome tab,
that tab gets focused. If it isn't, it opens in a new tab. No duplicate tabs.

Chrome has no built-in equivalent, and no browser chooser does it either —
Finicky, Velja and Choosy all pick a *browser*, then leave tab handling to it.
This wires tab reuse in as the system default handler, so it applies to every
link from every app.

Linear links are the one exception: they open in the Linear desktop app.

Local pages work the same way: `open page.html` in a terminal, or double-clicking
an HTML file in Finder, opens it in Chrome as a `file://` URL and reuses the tab
if that file is already open.

> **This sees every URL you open.** It has to — it becomes your default browser
> handler. Everything happens locally: nothing is sent anywhere, nothing is
> logged, and there is no network code in this repo. The one exception is opt-in
> and noted under [Editing the config](#editing-the-config) — Finicky's
> `logRequests` writes every URL you visit to a local file.

## Requirements

- macOS with Chrome and Finicky **4.x** — a v3 config has different syntax and
  fails *silently*, so `install.sh` refuses to proceed on one
- Homebrew, only if Finicky isn't already installed
- Developed on macOS 26.5; no lower bound has been tested

## Install

```sh
./install.sh
```

That checks your Chrome and Finicky versions, installs Finicky if it's missing,
backs up any existing Finicky config, builds and registers the applet, and
prints the two steps it can't do for you: choosing Finicky as the default
browser, and approving Chrome automation on first click.

Then:

```sh
./verify.sh
```

Every failure mode here is silent, so `verify.sh` exists to turn "links just
don't do anything" into a specific answer. To back out, `./uninstall.sh` — read
its first message, the default-browser step has to come first.

## How it works

Two pieces.

**Finicky** is set as the default browser, so it sees every URL the system
opens and decides where it goes. Its `defaultBrowser` is ChromeTabFocus, so
everything lands there unless a handler claims it first.

**ChromeTabFocus** is an AppleScript applet registered as an http/https
handler. Given a URL it scans every Chrome window for a tab already showing it
(ignoring trailing slashes), focuses that tab and window if found, and
otherwise opens a new tab in the front window — or a new window, if Chrome has
none open.

Inside, the applet is three scripts. `tab-focus.applescript` decides which tab
matches and whether to focus or open; it reaches Chrome only through an
adapter with three calls (`findTab`, `focusTab`, `openTab`).
`chrome-tabs-appleevents.applescript` is that adapter over Apple events, and
`test-tab-focus.sh` swaps in a fake one. A different way of reaching Chrome —
an extension over native messaging, say — is a new adapter, not a rewrite.

It addresses Chrome by process, not by name. Test runners (Selenium,
Puppeteer, etc.) launch headless Chrome from the same `.app`, and while one is
running `tell application "Google Chrome"` can resolve to it — every link then
opens in an invisible browser and the click looks like it did nothing. The
applet picks the Chrome process with a regular (Dock) activation policy and
drives it through ScriptingBridge by pid instead.

A click therefore crosses two processes before Chrome sees it. Naively that
cost ~0.6s with a visible focus flash. Three details bring it to ~0.27s:

- The applet is built **stay-open** (`osacompile -s`), so it stays warm instead
  of cold-launching per click.
- **`LSUIElement`** is set, so it has no Dock presence and focus never visibly
  leaves the app you clicked from.
- Tab URLs are read **one Apple event per window**, not one per tab — per-tab
  round trips dominate once you have a lot of tabs.

Finicky's `keepRunning` does the same job on its side.

Both figures are wall-clock from `open <url>` until Chrome's active tab reports
the target URL, on one machine with ~6 tabs open. Treat them as "the difference
was obvious", not as a benchmark.

`./bench.sh` is the benchmark: it times focusing an existing tab via Finicky
and direct to the applet, with your windows as they are and again with 50
filler tabs in front. On the machine above, the Finicky hop costs ~150ms and
50 extra tabs cost ~140ms in the applet. Run it before and after any change to
the applet; numbers drift between sessions, so compare runs made back to back.

## Limitations

- **Minimized windows don't work.** If the matching tab is in a minimized
  window, the click appears to do nothing at all — no new tab, no visible
  change. The applet selects the right tab but never deminiaturizes. Confirmed,
  and deliberately not fixed.
- **Incognito windows participate.** A URL open in an incognito window will
  raise that window. That's intended here, but it's worth knowing before you
  click a link from Mail in front of someone.
- **Chrome only.** Safari's scripting dictionary differs, and Firefox exposes
  no tab-URL scripting at all, so it could never participate.
- **Links clicked inside an app that opens its own webview never reach
  Finicky**, so they can't be deduplicated.
- **URLs must match exactly** (modulo trailing slash, and percent-encoding for
  `file:` URLs). Query strings, tracking params and anchors all count as
  different tabs.
- The applet accepts a URL from **any** app, not just Finicky. Nothing is
  passed to a shell, so there's no injection surface; an unusual scheme just
  lands in a new blank tab.

## Editing the config

`~/.config/finicky/finicky.js`. **Finicky does not hot-reload it** — an edit
does nothing until Finicky restarts, and every URL quietly falls through to the
default browser in the meantime.

```sh
pkill -x Finicky
```

This config sets `hideIcon`, so there's no Finicky menu bar item to reach for —
`pkill` is the control.

Stop it and stop there — do **not** launch it again. Finicky shows its window
on every explicit launch, and `open -g -j -a Finicky` is no better than
`open -a Finicky`; the background and hidden flags make no difference. That
window is the flash people mistake for a slow route. Launched by LaunchServices
to handle a URL, it never shows the window at all, so the next link you click
brings it back silently.

Editing any `.applescript` file is different: re-run
`./install-chrome-tab-focus.sh`, or the old compiled applet keeps handling URLs
and your change appears to do nothing.

When a rule misbehaves, set `options.logRequests: true`, restart, and read
`~/Library/Logs/Finicky/*.log` — it records the exact `open` command issued,
which settles what a rule actually did. Turn it back off afterwards; that log
contains every URL you visit.

### Adding your own carve-out

Handlers are tried in order; the first match wins, and anything unmatched falls
through to `defaultBrowser`. A handler is just `match` + `browser`:

```js
{
  match: ({ url }) => url.host === "figma.com",
  browser: { name: "Figma", appType: "appName" },
}
```

Note the `{ url }` destructure — see the trap below before you copy this
somewhere else.

### Two Finicky v4 traps

Both fail silently rather than erroring:

- **A handler has no `url` field** — only `match` and `browser`. URL rewriting
  belongs in the top-level `rewrite` array, which runs first; handlers then
  match the already-rewritten URL. Confirmed in Finicky's own
  `finicky.d.ts`, where `BrowserHandler` is `{ match, browser }`.
- **The bundled `finicky.d.ts` disagrees with the runtime about `match`.** It
  declares `(args_0: URL, ...)`, implying a bare WHATWG `URL`, but Finicky
  4.2.2 actually passes a `{ url }` wrapper — which is why the config here
  destructures. Verified by routing rather than by reading: `/issue/...`
  reaches Linear while `/pricing` falls through to Chrome, which can only
  happen if the destructure works. If a future version drops the wrapper, every
  Linear link will start opening in Chrome; switch to a bare `url` parameter
  then.

## Linear notes

Linear.app ships no `com.apple.developer.associated-domains` entitlement, so a
universal link can never reach the app directly — only the `linear://` scheme
can. In practice handing Linear the plain https URL and letting it route
internally works better than rewriting the scheme, so this config doesn't
rewrite anything.

Linear matches its in-app tabs on the **exact URL**, so a slug-less issue link
(`/issue/ES-583`) opens a second tab alongside the canonical one
(`/issue/ES-583/some-title-slug`). Use the full URL from
`linear issue view <id> --json` when pasting links. Canonicalising slug-less
URLs automatically was considered and rejected: the CLI lookup costs ~0.9s per
click, and links clicked inside Linear never pass through Finicky anyway.

Don't use Linear? Delete the handler between the `---8<---` markers in
`finicky.js` and every URL goes to Chrome.

## Rejected approaches

Kept so they don't get re-attempted:

- **Routing GitHub to the GitHub PWA's shim app** drops the deep link. Its
  `app_mode_loader` accepts no URL argument and always lands on the app's start
  URL.
- **Launching Chrome with `--app=<url>`** opens the right URL, but in a fresh
  window every time, with no tab reuse.
- **GitHub Desktop** registers only clone/auth schemes (`x-github-client://`,
  `github-mac://`) and cannot render issues, PRs, or code.

## Files

| File                            | Purpose                                          |
| ------------------------------- | ------------------------------------------------ |
| `install.sh` / `uninstall.sh`   | Everything, both directions                      |
| `verify.sh`                     | Diagnose a silent failure                        |
| `finicky.js`                    | Copied to `~/.config/finicky/finicky.js`         |
| `chrome-tab-focus.applescript`  | The applet's entry points: URLs and files in     |
| `tab-focus.applescript`         | Tab focus: which tab matches a URL, focus or open |
| `chrome-tabs-appleevents.applescript` | The Chrome adapter: reads and drives Chrome over Apple events |
| `install-chrome-tab-focus.sh`   | Builds and registers the applet only; also the edit-test loop |
| `test-tab-focus.sh`             | Tab focus against a fake Chrome; no Chrome needed |
| `bench.sh`                      | Times a click that focuses an existing tab       |

The applet is built rather than committed: `osacompile` produces the `.app` in
`~/Applications`, then the installer patches its bundle id, URL types,
`LSUIElement` and `NSAppleEventsUsageDescription` into `Info.plist`, ad-hoc
signs it, and registers it with LaunchServices.

Ad-hoc signing has one sharp edge worth knowing: the code identity changes on
every rebuild, so macOS may re-prompt for Chrome automation after you re-run
the installer — or, with a stale grant on record, silently deny it. If links
stop working right after a rebuild:

```sh
tccutil reset AppleEvents io.github.gamellis.chrometabfocus
```

## License

MIT — see [LICENSE](LICENSE).
