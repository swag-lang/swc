# Swag Scope Application Backlog

This backlog covers the Swag Scope application shell: document lifecycle, process and window
management, viewer hosting, and persisted application state. Operating-system integration lives
in [platform.portability.md](platform.portability.md). Work
owned by a viewer lives in the corresponding domain:

- [app.scope.viewers.md](app.scope.viewers.md) — shared viewer contracts, coverage, and product scope
- [app.scope.text.md](app.scope.text.md) — basic text, code, subtitle, table, diff, and log viewers
- [app.scope.document.md](app.scope.document.md) — Markdown, HTML, PDF, office-document, and ebook viewers
- [app.scope.indesign.md](app.scope.indesign.md) — InDesign viewer
- [app.scope.opendocument.md](app.scope.opendocument.md) — OpenDocument viewer
- [app.scope.binary.md](app.scope.binary.md) — structured binary and container viewer
- [app.scope.hexa.md](app.scope.hexa.md) — hexadecimal viewer
- [app.scope.image.md](app.scope.image.md) — image viewer
- [app.scope.audio.md](app.scope.audio.md) — sound viewer
- [app.scope.video.md](app.scope.video.md) — video viewer
- [app.scope.font.md](app.scope.font.md) — font viewer
- [app.scope.midi.md](app.scope.midi.md) — MIDI viewer

Reusable engine work remains in the backlog of the standard module that owns it.

### app.scope.011 — Reduce repeated rendering in Scope's visual tests

- Evidence: with the existing DevMode compiler, devmode artifacts and three workers,
  `tools/apps.bat dm test swagscope` reuses its test executable and passes 353 tests in
  282.6 seconds; native execution accounts for about 280 seconds. A separate cached
  `--test-tag golden` run passes 70 tests in about 210 seconds (209 in execution), compared
  with 20.5 seconds for the 51 tests in `viewerwindow.swg` and 7.1 seconds for the
  28 tests in `video.swg`. These are single runs, not matched benchmark medians.
  Terminal progress attributes approximately 32 and 35 seconds to the Markdown and Explorer
  lens cases in `viewerwindow.swg`, and 31 seconds to the return-caption case in
  `viewer.pictures.swg`. That case opens 15 viewers in both themes, paints full
  1280-by-800 windows repeatedly through `framedViewerWindow`, settling and capture, then
  crops to the caption. Each `settleAnimations` call paints twice; it does not sleep.
- Next: separate preparation from settling/capture in the picture helpers and measure the
  necessary paints at each checkpoint. Profile lens setup, CPU backdrop rendering and golden
  comparison separately before attributing its time to the Gaussian blur. Preserve whole-window
  composition checks and both themes; do not replace the real viewers or disable effects merely
  to shorten the campaign. Keep a focused test-file command for local changes.
- Done when: repeatable cached-run measurements show lower native test time with the same
  visual assertions and reviewed golden pixels, and individual test costs remain observable.

### app.scope.010 — Explorer previews stay generic after a graphics device reset

- Evidence: after a GPU reset, `RenderOgl.recoverLostDevice` retires every texture, and the
  explorer's preview textures read as invalid. `explorer.swg` then draws the generic tile, but
  its entries are already `attempted`, so the previews are only decoded again by a refresh.
  The theme, icons and glyphs come back on their own; only the library previews do not.
- Next: on `NotifyEvent.Kind.ThemeChanged` or a first paint that finds an entry with a handle
  whose texture is no longer valid, clear `attempted` for those entries so the preview workers
  decode them again; cover it with `Pixel.Testing.submitDeviceHang` in an opt-in
  `integration.renderer.reset` journey.
- Done when: previews visible before a device reset reappear without a manual refresh.
- Related: std.gui.057

### app.scope.001 — One document per window

- Evidence: `src/main.swg` creates one `ViewerWindow`, which owns one active file and viewer.
  Opening another file replaces that document; there is no document-tab host.
- Next: adopt the GUI document-host contract with independent document ownership, close behavior,
  focus and saved reading state. Keep process reuse behind platform.portability.022's messaging
  contract, and side-by-side presentation separate.
- Done when: several documents can remain open as tabs in one window, and switching or closing
  a tab preserves the other documents' state and outstanding-work ownership.
- Related: std.gui.029, platform.portability.022, app.scope.003

### app.scope.003 — Two documents cannot be shown side by side

- Evidence: `ViewerWindow` has one active viewer surface. The application has no pair of independently
  focused document panes; hexadecimal difference analysis remains a separate viewer capability.
- Next: add a split presentation for two open documents with explicit focus and command routing,
  preserving each viewer's reading state when moving between tabs and split panes.
- Done when: two documents remain visible and independently usable, and closing or replacing
  either pane leaves the other's state and input intact.
- Related: app.scope.001, app.scope.hexa.003

### app.scope.004 — Cold folder previews need latency profiling

- Evidence: `Explorer` submits visible previews as background tasks to the runtime's shared
  admission pool. A cold video preview opens a reader and seeks to as many as five key pictures
  until it finds a lively frame. An isolated passwordless Swag Vault mount with eight copies of
  a ten-minute H.264 video produced eight visible local Explorer previews in 322 ms. Warm direct
  thumbnail extraction was 1.2–1.5 times slower through the mount than from the host filesystem;
  parallel extraction was 1.08 times slower in one run. These measurements do not cover cold
  storage. With online movie artwork enabled, Explorer looks up the poster before decoding a
  fallback frame. Four fresh ten-minute H.264 files on the mount took 9.87 s to show all four
  pictures in one warm run; the first appeared after 0.99 s. The Apple catalogue imposes about
  20 searches per minute, so a batch of unmatched titles remains limited by its request cadence.
  A 150 MB 1920 × 1080 Motion JPEG MP4 exposed a separate frame cost: the previous thumbnail
  path decoded five key pictures (3.84 s local, 4.08 s mounted) because bilinear reduction made
  the first detailed image appear flat to the contrast test. Analysing before reduction kept that
  first picture (0.75 s local, 0.78 s mounted), without replacing the poster-first policy.
- Next: profile cold and warm child-process latency plus spinner frame cadence for Markdown, image,
  video, and one expensive structured viewer. If direct media decoders miss the first-preview budget,
  reduce their decode work while retaining a useful representative image.
- Done when: representative formats meet the first-preview and UI frame budgets without losing
  useful preview content.
- Related: app.scope.viewers.004, app.scope.viewers.009, app.scope.document.001

### app.scope.005 — Film matching needs correction and broader coverage

- Evidence: Explorer automatically looks up films on Wikipedia and Wikidata without credentials,
  conservatively matches titles and years, shows available credits and IMDb ratings, and uses local
  previews when a result is unavailable. Cached results expire after 120 days.
- Decision (2026-10-28): real posters and synopses come first from the Apple iTunes Search API,
  which needs no key (entity `movie`; the 100 px artwork URL scales to a poster size); Wikipedia and
  Wikidata stay for direction, cast and the IMDb rating. [Apple documents](https://performance-partners.apple.com/search-api)
  an approximate limit of 20 searches per minute, so requests are spaced and cached. TMDB (key
  required, attribution in About, cache under six months) is the later option for series and better
  coverage.
- Next: query iTunes for posters and synopses, keep the Wikipedia/Wikidata credits, offer a
  searchable list of candidates and cover TV series separately
  from films, retaining source attribution, privacy, cancellation and bounded requests.
- Done when: users can review candidate matches in the application and correct one without
  looking up an ID elsewhere; series identification remains distinct from film matching.
- Related: app.scope.004, std.core.001, std.core.003, std.core.005, std.core.006

### app.scope.006 — Music matching needs correction and broader tag coverage

- Evidence: Explorer previews use MP3/FLAC album and artist tags to query MusicBrainz
  and retrieve artwork from Cover Art Archive. Results are cached, requests are spaced within
  the process, and missing or ambiguous results fall back to local previews. The
  [MusicBrainz API](https://musicbrainz.org/doc/MusicBrainz_API/FAQ) supports release search
  without an API key and requires a meaningful user agent; its
  [rate policy](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting) normally limits each
  source IP to one request per second. A user can persist a MusicBrainz release-group ID against
  the identity of a file. Separate processes can still share the same rate limit.
- Next: offer a searchable list of candidates, extend tag support to more music formats, and
  coordinate rate limiting across processes sharing the same host when practical.
- Done when: users can choose a release in the application, supported tagged formats have
  equivalent lookup behavior, and rate-limited or ambiguous responses remain safe and usable.
- Related: app.scope.005, app.scope.audio.008, std.core.006

### app.scope.007 — The viewer bar can leave while an options sheet opened from it is up

- Evidence: `viewerwindow.swg:2598` (the image viewer's play button after a round trip
  through the hex viewer) failed once in two full Scope runs and twice in the first two of
  fifteen runs of that file alone; the other thirteen passed. The test calls `revealViewerBar`,
  then opens two options sheets from the play button. Their modal loops call
  `Application.runFrame`, whose `sendTimerEvents` fires timers by wall clock, so when the sheets
  take longer than `ViewerBarLinger` (2.5 s, a loaded machine) `concealViewerBar` runs while a
  sheet is up: the focus is in the sheet's surface, which `viewerBar.isOwnerOf` does not reach,
  and the bar is hidden. The commit ad810f0b50 only kept the linger out of
  `completeQueuedViewerFile`'s `fireTimers`. The same thing happens to a reader who lingers in
  the sheet: it loses the button it is attached to.
- Next: count a running modal loop (`app().inModalLoop != 0`) as holding the bar in
  `concealViewerBar`, add a test that fires `viewerBarTimer` with `inModalLoop` raised and checks
  the bar stays (and leaves on the next linger once the loop is over), then prove it with ten
  consecutive runs of `viewerwindow.swg` (`--run-timeout 300`) and two full Scope runs.
- Done when: the bar never leaves while a sheet or menu opened from it is up, and the play button
  test passes ten runs in a row under load.
- Related: std.gui.058

### app.scope.008 — Online services and viewer settings have no global options page

- Evidence: online film and music information is switched by two lens commands
  (`ViewerCommands.OnlineMovies`, `OnlineMusic`); MusicBrainz is chosen per album through an
  identifier box (`explore_ChooseMusic`). Services that need a key (TMDB, later IMDb) have no
  place to receive it. Each viewer keeps its own settings (`g_ViewerSettings` in the Markdown and
  MIDI viewers) reachable only from its own options sheet, while the viewer is open.
- Next: give Swag Scope one global options page reached from the lens; let a viewer plugin
  declare the global options it offers (a `Viewer.Plugin` callback filling an `OptionSheet.Page`)
  and let the explorer's online services declare theirs, keys included; persist them with the
  window settings, never in a golden or a log.
- Done when: every online service and every viewer setting can be changed from the global page
  without opening a file, and a key entered there is used by its service.
- Related: app.scope.005, app.scope.006
