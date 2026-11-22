---
name: chrome
description: Browser work in Claude in Chrome: starting the extension, the cookie bridge (also "the bridge" or "the proton bridge"), reading before each click, local files, rendering a page to a file, Google APIs and sign-ins. Load before the first browser step of a turn.
---

# Browser work

- Browser work runs in Claude in Chrome, the extension in the user's own Chrome, which the user also
  calls Chrome and is signed in to, never in the desktop app's built-in browser pane, whose user
  agent cannot be changed. A page, a file or an upload is tried there before a reply calls it out of
  reach, and an address that WebFetch or another fetch could not reach is tried there next and with
  plain curl from the user's machine, its public API included, before any question or other route.
  When the extension is not connected, the session runs `~/.claude/hooks/chrome-background.sh`
  without asking, which gives the extension the window it needs and keeps Chrome hidden, and never
  opens Chrome another way, since Chrome then puts its window on top. Nor does a session open a
  tab or load a page in Chrome through AppleScript, which brings Chrome to the front as well.
  Claude in Chrome's own tools leave Chrome behind the app the user is in, but the tab they open or
  load can become the one the user's Chrome window shows. It then calls
  `list_connected_browsers` for up to a minute until it lists a browser, and tries before that are
  no failures. When the extension is still not connected, the reply gives its install page and the
  step to sign in to it from Chrome's side panel, and the browser step waits for that, never moving
  to the pane. A local file reaches a page through the extension's `file_upload`, up to 10 MB a
  call, and a larger one through `~/.claude/hooks/pane-bridge.mjs`, driven as its header says.
  Rendering is browser work too: no session starts a Chrome of its own, headless or with another
  profile, also not to turn a page into an image or a PDF. Playwright's own Chromium, which a
  project's tests and the `pull-requests` skill's screenshots run on, is not that app. A page that
  has to become a file draws it on a canvas in a Chrome tab, an HTML layout through an SVG
  `foreignObject` with each font named by its installed family or inlined as a data URL, never a
  keyword such as `-apple-system` or a linked web font, and posts the blob to the bridge's `/save`
  from a page the bridge serves. A job Chrome cannot do this way is asked about first. A Google API
  is read through Google's OAuth 2.0 Playground with the narrowest read-only scope the user said yes
  to, a grant the session removes under `myaccount.google.com/connections` once the read is done.
  A sign-in page in a Chrome tab for a site the user is signed in to in Firefox means the cookie
  bridge's copy fell short, so before that sign-in goes to the user the session checks that Firefox
  runs and has loaded a page of the site since it started, since the bridge's script runs only in a
  loaded page and a tab Firefox restored but nobody opened sends no local storage, that the site's
  cookies and local storage reached the tab, whose key `cookie-bridge-written` lists the items the
  bridge wrote, and that the Chrome tab runs the same app as Firefox's tab, since two apps on one
  origin, such as Telegram Web's `/a/` and `/k/`, keep a login under different keys. It reads the
  page's own code for signed-in state kept elsewhere, such as in IndexedDB or session storage, which
  the bridge does not carry, and names the cause in the reply. When only an unloaded Firefox tab
  stands in the way, the step for the user is to open that tab in Firefox, never the sign-in.
  The user calls the cookie bridge the bridge or the proton bridge too, so those words mean it,
  never Proton Mail Bridge or another program of that name. On a machine where it is not set up,
  with no `run/` folder in `~/.claude/cookie-bridge`, setting it up is the step before any sign-in:
  `install-host.sh` registers the host for both browsers, and the user adds each half.
  When a step needs the user in the browser, such as a sign-in, personal data to type or a click the
  session may not make, the session opens the page that step happens on in a tab of its group,
  leaves that tab open, selects it with `~/.claude/cookie-bridge/front-tab <tab id>`, puts the
  cursor in the field to fill and names the tab in the reply, and the turn ends with `wrap_up` and
  `blocked`, so the sidebar marks the session as waiting on the user. A source behind the user's
  sign-in, such as Apple's developer downloads, is such a step, never one left unread or called not
  checked. A step that hands the user input to type in the browser names the button that saves it,
  and the session reads that page as it stands before its first navigate, reload or click away from
  it, saves what is still unsaved and leaves only once the input is saved.
- A file that a member of another organisation posted in a shared channel, such as a Slack Connect
  channel, lives in that organisation's workspace, which the connector's token cannot reach, so the
  retry fails too and file search does not list it. Open such a file where the user is signed in:
  the message's permalink in Chrome, the option to open it in the browser, then the app's own
  viewer, read page by page from zoomed screenshots, since the viewer's frame blocks scripts.
- While the user is in a call in a Chrome tab, such as Google Meet, no session opens, loads or
  closes a tab in Chrome, since its tab can take the call's place on the screen. Chrome holds the
  camera or the microphone then, so before its first browser step the session reads
  `/usr/bin/log show --last 5m --predicate 'process == "ControlCenter" AND eventMessage BEGINSWITH
  "Active activity attributions changed to "'`, whose latest line lists `cam:com.google.Chrome` or
  `mic:com.google.Chrome` while the call runs.
- Claude in Chrome reaches only the tabs of its own group and opens no `chrome://` page: its
  `navigate` turns `chrome://webrtc-internals` into `https://chrome//webrtc-internals`. Such a page,
  like a tab of the user's outside the group, is a step for the user: the reply gives its address in
  a `text` block, the session reads it with `screencapture -x -o -l <window id>` of the Chrome
  window, whose id `CGWindowListCopyWindowInfo` gives, and figures below what the window shows come
  from the page's own download, such as the dump `chrome://webrtc-internals` saves.
- Before each click in a Chrome tab, the session reads the page as it is at that moment, a fresh
  screenshot or an element's ref from `find`, never coordinates from an earlier screenshot, since
  the user may have scrolled, typed or clicked there since. A click that submits, sends or posts
  first checks that the page still holds what the user approved, and a change the user made is named
  in the reply before it asks again.
- No reply suggests storing a password in Chrome: not in Chrome's own password manager or through
  its offer to save one, not by importing passwords from Firefox, and not in a password manager's
  Chrome extension that fills logins there. A sign-in in Chrome is the user's to type or paste each
  time a site asks, from the password manager they keep outside Chrome.
- A Chrome tab stays open while a step still needs it, such as a sign-in left to the user. Once
  the session needs no tab and no other open session names one, as the `archive-files` mod reads it
  from their transcripts, the session quits Chrome wholly before the reply: it first sends its tab
  ids as `{"ungroup": [ids]}` to the bridge's `run/chrome.sock`, so Chrome keeps no saved group,
  then quits with `osascript -e 'quit app "Google Chrome"'` on macOS, which leaves Chrome behind,
  and on Linux with SIGTERM to Chromium's browser process, the one without `--type=`, which Chromium
  records as a session end and so shows no restore bar. `chrome-background.sh` starts it again for
  the next browser step. Archiving a session closes every Chrome tab no open session names, the
  user's own too, through the app and the `archive-files` mod, which first takes those tabs out of
  their tab groups so Chrome deletes the saved groups, and deletes groups closed earlier while
  Chrome is out of sight.
- Chrome opens its next window at the size of the last one, so a session that resized a Chrome
  window, with `resize_window` or otherwise, makes it fill the screen less the menu bar and the
  Dock again before the reply, never only the size it read before its first resize: other sessions
  resize the same window, so that reading can be a check size another session left, and copying it
  back keeps Chrome small. This command does it:
  `osascript -l JavaScript -e 'ObjC.import("AppKit"); const s=$.NSScreen.mainScreen, f=s.frame,
  v=s.visibleFrame; Application("Google Chrome").windows[0].bounds={x:v.origin.x,
  y:f.size.height-v.origin.y-v.size.height, width:v.size.width, height:v.size.height}'`
