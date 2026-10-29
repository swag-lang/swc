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

### app.scope.004 — Folder previews are slow and use the wrong page shape

- Evidence: `Explorer` runs one isolated thumbnail renderer per logical processor, less two. On a
  22-thread machine, the 60 visible previews of a cold 181-SVG folder took about 20 s with three
  renderers; 8 s once SVG drawings were rasterized at the 320-pixel thumbnail size instead of their
  own size, and with `RenderCpu` walking only the span of each triangle row; 3.8 s with twenty
  renderers, for about 1.3 GB across the processes and a first preview at 1.4 s instead of 1 s.
  Concurrent renderers had shared an exchange directory when their `Guid64` generators were seeded
  in the same microsecond, losing a preview now and then. Video previews keep the first lively
  frame of five positions, each read as a key picture (`Reader.decodeKeyPicture`: the clean point
  a cue names, read alone), 0.3 to 1.2 MB a film instead of 3 to 9 MB. Folders on a network share
  run six renderers, which the NAS serves faster than twenty: 100 cold tiles of Z:/Séries in 6.4 s. Film folders use screen-shaped tiles, previews trim
  encoded black bands, stand on their names with the interface corner, and films carry their
  duration. The former generic
  path created a complete viewer for each uncached file. Generic thumbnails now use
  one persistent CPU canvas and font cache per worker, reading at most 16 KiB for text or mapping
  the first 2 KiB for binary input. Image and video plugins keep their direct decoders. The Explorer
  no longer invalidates the full grid every 16 ms during preview work; each spinner repaints its own
  window. Appearance changes no longer invalidate previews; viewer-selection changes still do. The
  gallery uses larger portrait tiles and preserves intrinsic media ratios. Focused tests cover generic
  and direct routes, bounded input, worker cache reuse, spinner frames, and the gallery golden.
  Cold/warm child-process latency and UI frame cadence have not yet been measured.
- Next: profile cold and warm child-process latency plus spinner frame cadence for Markdown, image,
  video, and one expensive structured viewer. If direct media decoders miss the first-preview budget,
  reduce their decode work while retaining a useful representative image.
- Done when: representative formats meet the first-preview and UI frame budgets, pages read clearly
  in the portrait tile, and media previews retain their natural aspect ratios.
- Related: app.scope.viewers.004, app.scope.viewers.009, app.scope.document.001

### app.scope.005 — Film matching needs correction and broader coverage

- Evidence: Explorer automatically looks up films on Wikipedia and Wikidata without credentials,
  conservatively matches titles and years, shows available credits and IMDb ratings, and uses local
  previews when a result is unavailable. Cached results expire after 120 days.
- Decision (2026-10-28): real posters and synopses come first from the Apple iTunes Search API,
  which needs no key (entity `movie`; the 100 px artwork URL scales to a poster size); Wikipedia and
  Wikidata stay for direction, cast and the IMDb rating. Its rate limit is not documented: requests
  are spaced and cached like MusicBrainz's. TMDB (key required, attribution in About, cache under six
  months) is the later option for series and better coverage.
- Next: query iTunes for posters and synopses, keep the Wikipedia/Wikidata credits, offer a
  searchable list of candidates, improve filename interpretation and cover TV series separately
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

- Evidence: `viewerwindow.test.swg:2598` (the image viewer's play button after a round trip
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
  consecutive runs of `viewerwindow.test.swg` (`--run-timeout 300`) and two full Scope runs.
- Done when: the bar never leaves while a sheet or menu opened from it is up, and the play button
  test passes ten runs in a row under load.
- Related: std.gui.058
