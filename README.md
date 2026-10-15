# chrome-tab-focus

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

> **This sees every URL you open.** It has to — it becomes your default browser.
> Everything happens locally: nothing is sent anywhere, nothing is logged, and
> there is no network code in this repo.

## Requirements

- macOS with Chrome
- Developed on macOS 26.5; no lower bound has been tested

## Install

```sh
./install.sh
```

That builds and registers the applet and asks macOS to make it the default
browser and the handler for `.html` files. Two steps are yours: confirming the
"change your default web browser?" dialog, and approving Chrome automation on
first click.

Coming from the Finicky version of this? `install.sh` replaces Finicky as the
default browser and prints how to remove it.

Then:

```sh
./verify.sh
```

Every failure mode here is silent, so `verify.sh` exists to turn "links just
don't do anything" into a specific answer. To back out, `./uninstall.sh` — read
its first message, the default-browser step has to come first.

## How it works

**ChromeTabFocus** is an AppleScript applet set as the default browser, so it
receives every URL the system opens. A carve-out can send a URL on to a desktop
app (Linear, here). Otherwise it scans every Chrome window for a tab already showing it
(ignoring trailing slashes), focuses that tab and window if found, and
otherwise opens a new tab in the front window — or a new window, if Chrome has
none open.

Inside, the applet is four scripts. `carve-outs.applescript` decides which URLs
belong to another app. `tab-focus.applescript` decides which tab matches and
whether to focus or open; it reaches Chrome only through an adapter with three
calls (`findTab`, `focusTab`, `openTab`). `chrome-tabs-appleevents.applescript`
is that adapter over Apple events, and `test-tab-focus.sh` swaps in a fake one. A different way of reaching Chrome —
an extension over native messaging, say — is a new adapter, not a rewrite.

It addresses Chrome by process, not by name. Test runners (Selenium,
Puppeteer, etc.) launch headless Chrome from the same `.app`, and while one is
running `tell application "Google Chrome"` can resolve to it — every link then
opens in an invisible browser and the click looks like it did nothing. The
applet picks the Chrome process with a regular (Dock) activation policy and
drives it through ScriptingBridge by pid instead.

A click crosses a process before Chrome sees it. Naively that cost ~0.6s with a
visible focus flash. Three details bring it down:

- The applet is built **stay-open** (`osacompile -s`), so it stays warm instead
  of cold-launching per click.
- **`LSUIElement`** is set, so it has no Dock presence and focus never visibly
  leaves the app you clicked from.
- Tab URLs are read **one Apple event per window**, not one per tab — per-tab
  round trips dominate once you have a lot of tabs.

Earlier versions put Finicky in front of the applet as the router. That hop
cost ~165ms of a ~300ms click, so carve-outs moved into the applet.

`./bench.sh` is the benchmark: it times focusing an existing tab through the
default browser and direct to the applet, with your windows as they are and
again with 50 filler tabs in front — the two paths should now agree. Run it
before and after any change to the applet; numbers drift between sessions, so
compare runs made back to back.

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
- **Links clicked inside an app that opens its own webview never reach the
  default browser**, so they can't be deduplicated.
- **URLs must match exactly** (modulo trailing slash, and percent-encoding for
  `file:` URLs). Query strings, tracking params and anchors all count as
  different tabs.
- The applet accepts a URL from **any** app. Nothing is passed to a shell, so there's no injection surface; an unusual scheme just
  lands in a new blank tab.

## Editing

Edit the `.applescript` files, then re-run `./install-chrome-tab-focus.sh`, or
the old compiled applet keeps handling URLs and your change appears to do
nothing. Run `./test-tab-focus.sh` and `./test-carve-outs.sh` first; neither
needs Chrome.

### Adding your own carve-out

Add a branch to `appFor` in `carve-outs.applescript` that returns the app's
bundle id, and a case to `test-carve-outs.sh`:

```applescript
if hostName is "figma.com" then return "com.figma.Desktop"
```

Find an app's bundle id with `osascript -e 'id of app "Figma"'`. If the app
isn't installed, the URL falls through to Chrome.

## Linear notes

Linear.app ships no `com.apple.developer.associated-domains` entitlement, so a
universal link can never reach the app directly — only the `linear://` scheme
can. In practice handing Linear the plain https URL and letting it route
internally works better than rewriting the scheme, so the carve-out doesn't
rewrite anything.

Linear matches its in-app tabs on the **exact URL**, so a slug-less issue link
(`/issue/ES-583`) opens a second tab alongside the canonical one
(`/issue/ES-583/some-title-slug`). Use the full URL from
`linear issue view <id> --json` when pasting links. Canonicalising slug-less
URLs automatically was considered and rejected: the CLI lookup costs ~0.9s per
click, and links clicked inside Linear never reach the default browser anyway.

Don't use Linear? Delete the branch between the `---8<---` markers in
`carve-outs.applescript`, re-run `./install-chrome-tab-focus.sh`, and every URL
goes to Chrome.

## Rejected approaches

Kept so they don't get re-attempted:

- **Routing GitHub to the GitHub PWA's shim app** drops the deep link. Its
  `app_mode_loader` accepts no URL argument and always lands on the app's start
  URL.
- **Launching Chrome with `--app=<url>`** opens the right URL, but in a fresh
  window every time, with no tab reuse.
- **Finicky as the router in front of the applet** worked, but its hop cost
  ~165ms per click — over half the total. Carve-outs live in the applet now.
- **GitHub Desktop** registers only clone/auth schemes (`x-github-client://`,
  `github-mac://`) and cannot render issues, PRs, or code.

## Files

| File                            | Purpose                                          |
| ------------------------------- | ------------------------------------------------ |
| `install.sh` / `uninstall.sh`   | Everything, both directions                      |
| `verify.sh`                     | Diagnose a silent failure                        |
| `chrome-tab-focus.applescript`  | The applet's entry points: URLs and files in     |
| `carve-outs.applescript`        | URLs that go to a desktop app instead of Chrome   |
| `tab-focus.applescript`         | Tab focus: which tab matches a URL, focus or open |
| `chrome-tabs-appleevents.applescript` | The Chrome adapter: reads and drives Chrome over Apple events |
| `install-chrome-tab-focus.sh`   | Builds and registers the applet only; also the edit-test loop |
| `test-tab-focus.sh`             | Tab focus against a fake Chrome; no Chrome needed |
| `test-carve-outs.sh`            | Which URLs each carve-out claims                 |
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
