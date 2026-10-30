# GUI Backlog

This backlog covers `std/gui`, measured against the desktop toolkits it competes with:
Qt, GTK4, Avalonia, Slint, Flutter, and — for the "we render every pixel ourselves" family —
Dear ImGui and egui.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/gui` stay together here.
Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). [README.md](README.md) has the whole layout.


## Entries

Touch inertia (std.gui.021) and docking feedback (std.gui.026) will need animation; docking also
depends on drag and drop.
Each entry names the
smallest coherent version that can ship and the existing controls or applications that would
prove it. Operating-system integrations live in
[platform.portability.md](platform.portability.md).

### std.gui.054 — Measure wheel-to-display latency under CPU contention

- Evidence: ordinary layered-window frames read only the dirty rectangle through one polled
  OpenGL transfer, allowing event dispatch while the GPU is busy. This bounds the frame queue
  and avoids waiting for completion during ordinary drawing, but message round-trip probes
  do not measure wheel-to-display latency. Driver calls and USER32 publication can still take
  time on the window thread.
- Reproducer: the user reports slow scrolling of `backlog/compiler.core.md` in Swag Scope
  while the CPU is busy, with Typora remaining fluid on the same document under that load;
  the slowdown affects the entire application, not only Markdown.
- Constraint: the default OpenGL context is owned by the window thread, because a worker
  renderer let drawable reallocation overlap native sizing (std.gui.056). `Pixel.RenderThread`
  remains an explicit adapter. Initial display and geometry changes still prepare a complete
  frame synchronously to publish pixels and geometry together.
- Next: timestamp input arrival, dispatch, and presentation under repeatable wheel input on
  that document at matched CPU contention. Separate recording, GPU completion, bitmap copy and
  native publication, and compare visible latency with Typora on the same display.
- Done when: real scrolling has a measured input-to-display budget under matched contention,
  including tail latency and any remaining window-thread stalls.
- Related: std.gui.049, std.gui.056, std.gui.057, platform.portability.066

### std.gui.057 — Validate layered presentation across displays and live resizing

- Evidence: rendering goes to an offscreen OpenGL target on a fixed-size hidden context host.
  The visible HWND stays layered, and `publishNativePresentation` (`surface.win32.swg`) hands
  premultiplied BGRA pixels, position and size to USER32 in one
  `UpdateLayeredWindowIndirect` call. Ordinary updates transfer and publish only the dirty
  rectangle; discrete placement prepares a complete frame before WM_NCCALCSIZE publishes it.
  A call that omits position and size still succeeds, but the screen keeps the previous
  image (4e7ee4e873 froze every repaint after the first that way).
  Existing captures ran at 12–30 fps under load, so they cannot exclude a one-refresh artifact.
- Rejected: a DirectComposition presenter does not bind the HWND geometry change to its
  content commit, and cropped content appeared in every commit ordering tried.
- Next: measure physical border-drag latency against std.gui.056 on both displays, and capture
  discrete placement at verified display cadence across DPI and adapter boundaries. Measure
  sustained repaint cost with asynchronous dirty-region transfers. Keep the
  single-HWND publication contract for any faster presenter.
- Capture constraint: target the verified Swag Scope HWND or its own window commands, never
  global full-screen shortcuts, and always include normal/full-screen/normal first.
- Done when: display-cadence captures across the supported monitors show only complete old
  and new frames, and physical border dragging preserves the responsiveness measured in
  std.gui.056 with an explicit sustained-presentation budget.
- Related: std.gui.054, std.gui.056

### std.gui.042 — Text outside a framed field is still centered on its line box, so its height follows the face

- Evidence: `EditBox`, `ComboBox` and `PopupListCtrl` center a single line on its capitals
  through `StringVertAlignment.OpticalCenter` (`Pixel.Font.opticalLineTop`, `drawstring.swg`).
  Labels, menu rows and list rows still center the line box, so their capitals sit where each
  face's internal leading puts them, and two families side by side disagree. Offsets measured
  before the theme switched to Inter and Roboto Mono no longer apply.
- Next: measure the cap-center offset of the current faces under line-box centering, then
  decide whether labels, menus and list rows follow the framed fields. If they do,
  `Gui.opticalTop` (`module.init.swg`) becomes plain centering and every golden that holds
  text moves by its face's offset. Pin the decision with a headless test that sets one field
  of each family side by side and asserts their capitals share a center.
- Done when: A headless side-by-side case measures the cap centers of framed fields, labels,
  menus, and list rows across shipped font families; the chosen placement rule is documented
  and the resulting goldens pin the decision.

### std.gui.055 — A menu entry borrows its identifier, so one formatted while the menu is built dangles

- Evidence: `Gui.WndId` is `string`, and `MenuCtrl.addItem` and `addRadioItem` keep the view
  they receive. An identifier built with `Format.toString(...).toString()` inside the call
  dangles after the statement. Nothing fails at build or run time, and the headless
  `clickPopupMenuItem` never matches the entry. The borrow-escape analysis does not see the
  escape through the `WndId` parameter. Consumers work around it with long-lived storage
  (Swag Scope's `SlideIds` table in `swagscope/src/api/playback.swg`).
- Next: decide whether `Item.id` and the other retained `WndId` fields should own a `String`,
  or whether the sanitizer can flag a `string` view of a temporary that escapes into a struct
  through a parameter. Prototype the owning field on `PopupMenuItem` and measure the churn on
  consumers.
- Done when: an identifier formatted at the call site either works or is rejected at build
  time, and a test in `menu.test.swg` pins whichever it is.

### std.gui.049 — One dirty rectangle couples distant changes on a surface

- Evidence: invalidations are unioned into one `dirtyRect`, which
  `Surface.paintToRenderTarget` (`surface.swg`) uses as the clip for the hierarchy and the
  chrome. A video picture and a distant timeline therefore grow a small update to most of the
  window. Earlier traces put adapter work above CPU recording cost. They are not a current
  frame budget.
- Next: compare a bounded list of dirty rectangles with dirty-subtree clips on separated
  animated widgets. Include overlapping effects, antialiasing, and shadow extents, so that
  smaller clips cannot leave stale pixels or repaint overlaps incorrectly.
- Done when: distant local changes stay local under a bounded invalidation policy, or the
  single rectangle is kept for a measured reason, with paint/golden tests for the decision.
- Related: std.gui.054

### std.gui.001 — Clipboard data cannot represent virtual files


Expose the same virtual-file descriptor and deferred contents through clipboard ownership without
making clipboard completion depend on drag interaction.

- Related: platform.portability.068

- Next: expose virtual-file descriptors and deferred contents through clipboard ownership
  independently of drag interaction.
- Done when: A clipboard owner publishes virtual-file names, metadata, and deferred contents through the typed-value API, and another GUI consumer retrieves them after the copy action without initiating a drag.

### std.gui.010 — No keyboard access keys


Add caption mnemonics, surface-level `Alt` handling, menu activation, and underline visibility as
one keyboard access-key contract.

- Related: platform.portability.048

- Next: add caption mnemonics, surface Alt handling, menu activation, and underline visibility as
  one access-key contract.
- Done when: Alt reveals mnemonic underlines, activates a unique caption or menu target from the keyboard, and restores focus correctly; tests cover duplicate and unavailable keys.

### std.gui.013 — Gesture recognizers have no claim arbitration


Add an arena or claim rule so a child control and its scrolling parent cannot both execute one raw
pointer sequence.

- Related: std.gui.011, std.gui.012, std.gui.014, std.gui.016, std.gui.017, std.gui.018, std.gui.019

- Next: define claim arbitration between child controls and scrolling parents for one raw pointer
  sequence.
- Done when: A child recognizer and scrolling parent receive one pointer sequence under an explicit winner/cancellation rule, and tests prove only the winner performs the action.

### std.gui.014 — No tap recognizer


Recognize a tap with platform-appropriate distance and timing thresholds.

- Related: std.gui.013, std.gui.015

- Next: recognize taps using documented platform-appropriate movement and duration thresholds.
- Done when: A touch sequence within documented movement and duration thresholds emits one tap, while movement, cancellation, and a second pointer prevent a false tap in headless tests.

### std.gui.015 — No double-tap recognizer


Recognize double tap as a composition of successful taps without delaying the single-tap contract
unless a control explicitly requests it.

- Related: std.gui.013, std.gui.014

- Next: compose qualifying taps into double tap without delaying single tap unless a control
  requests arbitration.
- Done when: Two qualifying taps within the configured interval and distance emit one double tap, and a single tap is delayed only for controls that request double-tap arbitration.

### std.gui.016 — No long-press recognizer


Recognize long press with movement cancellation and an explicit interaction with context menus.

- Related: std.gui.013

- Next: recognize long press with movement cancellation and an explicit context-menu interaction.
- Done when: A stationary held contact emits one long press and its requested context action, while release, movement, cancellation, or a competing gesture prevents it.

### std.gui.017 — No pan recognizer


Recognize single- and multi-pointer pan with capture transfer and velocity reporting.

- Related: std.gui.013, std.gui.021

- Next: recognize single- and multi-pointer pan with capture transfer and velocity reporting.
- Done when: Single- and multi-pointer movement emit pan deltas and bounded velocity, transfer capture according to the claim rule, and stop on cancellation in headless tests.

### std.gui.018 — No pinch recognizer


Report scale around the contact centroid without combining pinch completion with rotation.

- Related: std.gui.013, std.gui.019

- Next: report pinch scale around the contact centroid independently of rotation.
- Done when: Two contacts report scale around their centroid with stable start, update, and end phases, while rotation remains separately observable and contact loss ends the pinch.

### std.gui.019 — No rotate recognizer


Report rotation independently of pinch scale while sharing std.gui.013's arbitration.

- Related: std.gui.013, std.gui.018

- Next: report rotation independently of pinch while sharing gesture arbitration.
- Done when: Two contacts report signed rotation around their centroid independently of pinch scale, and gesture arbitration prevents duplicate actions in headless tests.

### std.gui.020 — No touch-sized input profile


Add a touch theme/input profile whose hit targets are larger even when the painted glyph is not —
  the 12-pixel slider thumb and the small scroll-bar profile are not finger targets.

- Related: std.gui.013, std.gui.021, std.gui.022

- Next: add a touch input profile that expands effective hit targets without enlarging the painted
  glyphs.
- Done when: A touch input profile expands effective hit targets for the slider, scroll bar, and representative small controls without enlarging their painted glyphs, with headless boundary tests.

### std.gui.021 — Touch scrolling has no inertia


Drive kinetic scrolling from the shared animation scheduler using the velocity reported by std.gui.017,
with deterministic deceleration and reduced-motion behavior.

- Related: std.gui.017

- Next: drive kinetic scrolling from the animation scheduler with deterministic deceleration and
  reduced-motion behavior.
- Done when: A pan release continues scrolling with bounded deterministic deceleration, stops at content bounds or cancellation, and follows reduced-motion policy in scheduler-driven tests.

### std.gui.022 — Nested scroll views do not chain touch motion


Transfer unconsumed pan motion to the next scrollable ancestor at a boundary.

- Related: std.gui.013, std.gui.017, std.gui.021

- Next: transfer unconsumed pan motion at a boundary to the nearest eligible scrollable ancestor.
- Done when: At a scroll boundary, unconsumed pan distance transfers once to the nearest eligible ancestor without losing or duplicating motion, with nested-view headless tests.

### std.gui.023 — Pen pressure is not modeled end to end


Carry pressure and pen identity from native input through drawing tools. `Swag Capture` is the proving
application, and the headless host must inject pen events so the behavior is testable without
hardware.

- Related: std.gui.011, std.gui.024

- Next: carry pen identity and pressure through native and headless input routing to a Swag Capture
  drawing tool.
- Done when: Native and headless pen events carry identity and pressure through GUI routing to a Swag Capture drawing tool, and varying pressure changes the recorded stroke in a deterministic test.

### std.gui.024 — No palm rejection during a pen stroke


Suppress competing touch contacts according to an explicit rule while a pen owns the drawing
gesture, with headless mixed-device tests.

- Related: std.gui.012, std.gui.013, std.gui.023

- Next: define and test suppression of competing touch contacts while a pen owns a drawing gesture.
- Done when: An explicit palm-rejection rule suppresses competing touch contacts while a pen owns a drawing gesture and restores ordinary touch behavior after pen release, with mixed-device headless tests.

### std.gui.026 — Docking has no tab-reorder or landing-preview interaction


Add internal tab reorder and edge/stack docking with an overlay that shows the exact landing
rectangle. Moving a pane transfers logical ownership, commands, and focus without destroying it.

- Related: std.gui.025

- Next: add tab reorder and edge/stack docking with an exact landing overlay while preserving pane
  ownership and focus.
- Done when: Tab reorder and edge or stack docking show an accurate landing rectangle and transfer pane identity, commands, and focus without destroying the view, with interaction tests.

### std.gui.027 — Docked panes cannot float and redock


Move a pane into a floating surface and redock it while preserving identity, focus, and DPI-correct
geometry.

- Related: std.gui.025, std.gui.026, std.gui.028

- Next: move panes into floating surfaces and redock them with stable identity, focus, and
  DPI-correct geometry.
- Done when: A pane floats into its own surface and redocks with unchanged identity and focus; geometry remains usable when monitor scale or topology changes.

### std.gui.029 — No multi-document host


Add `DocumentHost` over a tab stack: active document, dirty marker, close veto/save flow,
close-others, reorder, and command routing to the active view. Lazily create or virtualize heavy
pages, and test close veto and focus independently of docking. Swag Capture's open captures are the
first consumer; Swag Vault does not need this merely as a demonstration.

- Related: std.gui.025

- Next: add a tab-stack `DocumentHost` with active/dirty state, close veto/save, reorder, and
  command routing, using Capture as the first consumer.
- Done when: DocumentHost tracks active and dirty documents, close veto/save, close-others, reorder, and command routing, while tests cover lazy pages and focus independently of docking.

### std.gui.034 — No print preview


Render through exactly std.gui.030's page callback into a zoomable on-screen view; do not create a second
pagination path that can disagree with paper.

- Related: std.gui.030, std.gui.033, app.capture.001

- Next: render a zoomable preview through the same page-count and paint callback used for printing.
- Done when: Preview uses the same page count and paint callback as printing, zooms through representative pages, and matches fake-backend output without a separate pagination path.

### std.gui.035 — Data-driven UI resource for `std/gui`

- Evidence: a UI described by a data string pays off only if callers never need the controls
  back. The removed `FormCtrl` showed the opposite: every consumer recovered typed pointers by
  string identifier, so `FormLayoutCtrl` builders that return the concrete control replaced
  it. `Core.File.TweakFile` already parses text onto struct fields through reflection, and
  `ThemeStyle.addStyleSheetColors` is the existing string-resource precedent in `std/gui`.
- Next: prototype the compile-time half first. Parse a small UI resource in a `#run` block
  modeled on `TweakFile`, and check whether the parsed tree can emit typed member declarations
  for a window struct through `#code` or generated source. Evaluate an editor only if typed
  accessors can be generated.
- Done when: A bounded compile-time resource prototype either generates typed window members
  consumed without runtime string lookup, or demonstrates why that route fails and retires the
  resource proposal before editor work.

### std.gui.003 — Construction-time text does not automatically retranslate


`Application.setLanguage` already broadcasts `LanguageChanged`, and its documented contract asks
windows with construction-time text to handle that notification. Command-driven surfaces and
explicitly rebuilt grids already refresh. Define an automatic binding for text resolved once at
construction so static labels do not depend on each application remembering a manual handler.

- Related: std.gui.004

- Next: define automatic bindings for construction-time catalog text and test language changes
  without application-specific handlers.
- Done when: A label initialized from the GUI string catalog updates after Application.setLanguage without an application-specific notification handler, while command-driven controls retain their existing behavior in a localization test.

### std.gui.044 — A composite that commits a measured size loses the fraction the layout rounds off

- Evidence: `Wnd.resize` rounds a logical size to whole units, and `Surface.setPosition` places
  a native window on whole physical pixels. A composite that measures its content, commits
  that size, and then assumes the content still fits can lose up to half a unit, which is
  enough to wrap a line or to raise a scroll bar. Dialogs (`Dialog.physicalRoom`) and tooltips
  (rounding up on both axes) are guarded. The popup list, the menu popup, and `AutoHeight`
  labels are not audited.
- Next: audit those three composites for the commit-then-assume pattern. Either round out
  through one shared helper, or measure the second axis after committing the first. Prove it
  the way `dialogs.layout.test.swg` does, by sweeping content length.
- Done when: Popup lists, menu popups, and automatic labels retain all measured content after
  committing size across fractional scales and a sweep of content lengths, with no new scroll
  bar or clipped last line.

### std.gui.004 — French is the only shipped GUI translation


Add each additional shipped language as an independently reviewable resource contribution, with
coverage checks that prevent untranslated keys. Use `Core.Globalization.CultureInfo` for locale
date/name data and plural selection instead of maintaining GUI-local culture tables.

- Related: std.gui.003

- Next: add one independently reviewed GUI translation with key-coverage checks and
  `Core.Globalization` locale data.
- Done when: At least one additional GUI translation ships as a separately reviewed resource, its key coverage is checked, and locale data and plural selection use Core.Globalization rather than GUI-local rules.

### std.gui.011 — No pointer-event model


`MouseEvent` describes one mouse position,
one button and one global capture owner; it has no pointer identifier, device kind, contact area,
pressure or tilt. Treating touch as synthesized mouse input permits one finger to click, but loses
multiple contacts and cannot distinguish a pen stroke
from a pan.

The smallest coherent input layer is:

- Add a `PointerEvent` carrying a stable pointer id, mouse/touch/pen kind, primary/contact state,
  surface position, buttons, pressure, tilt and contact rectangle, routed and bubbled like the
  existing events. Native adapters belong to platform.portability.054.
- Related: std.gui.012, std.gui.013, std.gui.020, std.gui.023, platform.portability.054

- Next: add the stated platform-neutral `PointerEvent` fields and route and bubble simultaneous
  contacts through the headless host.
- Done when: Common GUI events carry pointer identity, mouse/touch/pen kind, contact state, position, buttons, pressure, tilt, and contact bounds through routing and bubbling, with headless tests for simultaneous contacts.

### std.gui.012 — Pointer capture is application-wide rather than per pointer


Add capture per pointer rather than one application-wide mouse capture, with cancellation when the
OS takes a contact away and an explicit rule for suppressing compatibility mouse events.
The native translation belongs to platform.portability.054.
- Related: std.gui.011, std.gui.013

- Next: add capture per pointer with cancellation and a rule suppressing duplicate compatibility
  mouse events.
- Done when: Two active pointers can hold independent capture owners, cancellation releases only the affected owner, and compatibility mouse messages do not trigger a second action in mixed-device tests.

### std.gui.025 — No docking layout host


The ingredients are present but not the model. `Tab` can select a page, `SplitterCtrl` can size
known panes, and a `Surface` can own a window. Add the split-tree model whose leaves are tab stacks
and whose panes have stable identity. Interaction, floating, persistence, and document semantics
are std.gui.026, std.gui.027, std.gui.028, and std.gui.029 respectively.

The proposed `DockHost` would own a split tree whose leaves are tab stacks, with close/hide and
minimum sizes. Start with programmatic docked layout and stable pane
identity; drag interaction, floating surfaces, and persistence have their own identifiers.

- Related: std.gui.029, std.gui.026, std.gui.027, std.gui.028

- Next: add the programmatic split-tree `DockHost` model with stable pane IDs, close/hide, and
  minimum sizes.
- Done when: A DockHost programmatically builds split leaves and tab stacks with stable pane IDs, close/hide, and minimum-size behavior, and layout tests cover nested splits without depending on drag, floating, or persistence.

### std.gui.045 — Verify the gui10 first-frame palette report

- Recorded observation: a Palettes-page launch was reported to show neutral selector colors
  until a pointer-triggered repaint. No frame capture or minimal reproducer is checked in.
- The recorded command used `--light --palettes`. Current `main.swg` maps `--light` to the
  neutral Light variant, whose system-blue accent is intentionally `#1473E6`; that color alone
  does not demonstrate a wrong palette. The same blue on the Widgets page is also expected.
- Source check: `variantColors` builds plain `ThemeColors` values and one local `Theme` for the
  sheet variant. `setLight` changes that value's palette, metrics and rectangles; this does not
  establish the earlier hypothesis that a local theme changes the application theme.
- Next: capture the first and second frames with the checkout-local DevMode compiler using
  `tools/examples.bat dm run gui10 --run-arg=--swagdark --run-arg=--palettes`, then compare the
  selector, caption and ground against the requested variant. If a mismatch remains, trace the
  affected window's style cache and invalidation. Remove this lead if the corrected reproduction
  is stable.

- Done when: A checkout-local gui10 capture records the first and next frames under --swagdark --palettes; either a reproducible mismatch is fixed with a frame regression or stable matching frames retire this lead with evidence.

### std.gui.028 — Docking layouts cannot be persisted


Serialize stable pane identifiers, splits, active tabs, and floating rectangles. Restore constrains
missing-monitor rectangles and ignores panes the application no longer registers.

- Related: std.gui.025, platform.portability.084, std.gui.027

- Next: serialize stable pane IDs, splits, active tabs, and floating rectangles with constrained
  restore and missing-pane handling.
- Done when: A dock layout round-trips stable pane IDs, splits, active tabs, and floating rectangles, and restore ignores missing panes while constraining rectangles to available monitors in tests.

### std.gui.030 — No printable-document pagination contract


Let a document answer page count and paint page `n` into a page-sized `Pixel.Painter` using
physical units. Define imageable bounds, multi-page failures, and vector-versus-raster behavior
without coupling the document to one printer backend. A fake backend records commands for CI.

- Related: std.pixel.005, platform.portability.086, std.gui.033, std.gui.034

- Next: define a printer-independent page-count and physical-unit paint callback and exercise it
  through a fake backend.
- Done when: One document page callback reports count and paints in physical units into Pixel.Painter; a fake backend verifies imageable bounds, page order, multi-page failure, and vector/raster fallback.

### std.gui.032 — Print jobs cannot be cancelled


Propagate cancellation from the GUI through pagination and the platform spooler, with a distinct
cancelled result and cleanup tests in the fake backend.

- Related: std.gui.030, platform.portability.086

- Next: propagate GUI cancellation through pagination and spooling with a distinct result and
  fake-backend cleanup tests.
- Done when: Cancellation from the GUI stops pagination and spooling, returns a distinct cancelled result, and leaves no open page or job handle in fake-backend failure tests.

### std.gui.033 — No page-setup model


Model paper, orientation, margins, scale/fit, and copies independently of printer discovery and
preview. Validate requested settings against the capabilities supplied by platform.portability.086.

- Related: std.gui.030, platform.portability.086, std.gui.034

- Next: model paper, orientation, margins, scale/fit, and copies independently and validate them
  against declared printer capabilities.
- Done when: Paper, orientation, margins, scale or fit, and copies form a printer-independent value that validates against declared device capabilities, with tests for unsupported combinations.

### std.gui.040 — A check box does not line up with the fields of the form it stands in

- Evidence: `CheckButton` and `RadioButton` place their marker in a `ThemeMetrics.btnCheck_Size`
  (24) cell. The atlas draws the shape inset inside that cell (`check_bk` is a 22-unit square
  at 5,5 of a 32-unit tile in `theme/widgets.svg`), so the ink starts about 3.75 logical pixels
  inside the given rectangle. A check box under a column of edit boxes therefore reads as
  indented, which shows in the Swag Vault open-vault card. Other atlas glyphs carry the same
  inset vertically.
- Next: decide who owns the difference. Either the tiles fill their cell and `btnCheck_Size`
  becomes the ink size, which changes the drawn box everywhere, or the widgets read the inset
  from the theme (`ThemeImageRect`) and place the cell so the ink lands on their rectangle.
  The second keeps the drawn size and is the smaller change.
- Done when: Check and radio marker ink aligns with the field column in the Swag Vault form and
  representative GUI layouts across shipped palettes and scales, without changing hit bounds
  or clipping the atlas tile.

### std.gui.056 — Reduce ordinary WGL resize latency with window-thread ownership preserved

- Evidence: when a worker thread rendered, a physical border drag of a large Swag Scope window
  stalled for 0.9–3.3 s in `wglMakeCurrent`, drawing and `glFlush`. The worker sat in the
  Intel driver's `NtGdiDdDDIDestroyAllocation2` while the window thread was resizing. With the
  context on the window thread there were no multi-second calls, but the previous presenter
  still reached 71–93 ms in `glFlush + SwapBuffers`. Remeasure physical dragging with the
  current layered presenter and its synchronous geometry frames (std.gui.057). The default renderer
  owns its context on the window thread, and `surface.renderthread.win32.test.swg` checks
  that ownership across resized paints.
- Measurement constraint: use a DPI-aware probe that actually presses, moves, and releases the
  border. Cross-thread `SetWindowPos` probes and median-only round trips do not measure
  physical-drag latency.
- Next: measure input-to-present latency during physical drag and discrete maximize or
  full-screen changes with the window-thread renderer. Compare any cheaper native presentation
  backend under platform.portability.066 against this baseline. Before moving rendering off
  the window thread, keep alpha and validate buffer lifetime during concurrent geometry
  changes.
- Done when: ordinary resize presentation has a measured latency budget and a validated
  ownership contract on the chosen backend.
- Related: std.gui.054, platform.portability.066

### std.gui.058 — A headless host leaves the windows built on its surface alive at shutdown

- Evidence: a full Swag Scope run stopped once with "notnull on null value" in `Array.add` from
  `Application.postEvent`, called by the `Wnd.taskNotifier` closure on a scheduler worker, then
  "#test cannot resume while submitted work is unfinished": a task posted into an application
  that had been dropped. `HeadlessHost.shutdown` destroys `root` only; a window a test creates on
  `&host.surfaceWnd` (every `ViewerWindow` of the Scope tests, `framedViewerWindow`) is never
  destroyed nor deleted, so the `Swag.Task` fields of its viewers are never dropped, never
  joined, and a running load notifies after the host is gone. Nothing detects it before the
  worker writes into freed memory.
- Next: in `HeadlessHost.shutdown`, destroy every child of `surfaceWnd` with the root and pump
  until `postDestroy` and `toDelete` are empty, so deleting the windows joins their tasks while
  the application lives; count the notifications `Wnd.taskNotifier` hands out in an atomic on
  `Application` (add on creation, subtract after the post — a task runs its notify exactly once,
  cancelled or not) and assert it is zero in `Application.opDrop` after the surfaces are deleted.
  Then run the gui suite, the Scope suite twice and the other applications' suites, since every
  headless test tears down through this path.
- Done when: the assert holds across the std and application suites and the Scope suite runs
  twice green with the teardown change.
- Related: app.scope.007

### std.gui.059 — Pack the widgets vector atlas more tightly

- Next: inventory occupied and unused regions in `widgets.svg`, then pack the unique tiles and
  update their `ThemeImageRects` coordinates from one reviewed layout.
- Done when: the atlas has no avoidable gaps, every tile coordinate resolves to its intended
  shape, and GUI rendering goldens pass at the supported scales.
- Evidence: the current 352 × 352 atlas contains substantial unused space between tile groups.

### std.gui.060 — Avoid rebuilding stock icon atlases before the first window is visible

- Evidence: Release Swag Capture spends 402-427 ms in five initial icon-atlas rasterizations
  and another 82-83 ms in its widgets atlas before the first window becomes visible. Three
  unprofiled launches have a 764 ms median to visibility and a 782 ms median to the first
  successful window-message response. A library with no capture still takes about 778 ms to
  visibility. These measurements identify GUI preparation as the dominant observed delay;
  they do not attribute the delay to compiler relocations or capture decoding.
- Next: inventory the stock GUI/Capture atlas and cell-size requests below, then prototype
  build-generated embedded rasters for those sizes using the same rasterizer, supersampling,
  alpha convention and color space as the current runtime path. Compare decoding/upload cost
  with the measured rasterization baseline. Keep SVG sources authoritative and define the
  fallback for custom resources, unsupported sizes and monitor-DPI changes before selecting
  a generated-asset layout. Reuse the existing atlas/cache API rather than adding app-local
  icon handling.
- Done when: normal application startup avoids the measured stock-atlas rasterization work,
  matched Release launches improve visibility and first-present latency, and exact-size
  generated rasters preserve the current pixels or explicitly reviewed visual goldens.
  Validate both palettes, small glyphs, fractional DPI, mixed-DPI monitor changes, custom SVG
  overrides, fallback sizes and cache invalidation. Report executable-size and memory costs
  alongside startup gains; do not exchange established rendering correctness for an earlier
  blank window.
- Related: std.gui.059 (widgets packing), std.gui.057 (layered presentation), std.gui.054
  (input-to-display measurement), compiler.optimization.136 (distinct relocation investigation).

**Measured artifacts and isolation**

The probe launches the actual applications through `tools/apps.bat run swagcapture -bc release`
and the Rust worktree's `tools/capture-rust.ps1 run`; compiler/tool startup is excluded from
application elapsed times. These are pre-existing Release binaries; source provenance must be
established again for a rebuilt baseline. In particular, the Swag image here is not the earlier
size/relocation artifact recorded in compiler.optimization.136.

| Artifact | SHA-256 |
| --- | --- |
| `bin/apps/.output/swagcapture/executable/release/x86_64/swagcapture.exe` | `6ae73aa6fdd34260a1e90b1435195129b8bff50a1d76439636206ad2add3693f` |
| Rust `release/swagcapture-rust-preview.exe` | `d63a6058e5737b112b4331a0b29d43a51eca5eec60cc19db7e1cda953621eda2` |

Each launch gets a private profile. Swag uses `swag.sandbox=<root>`, with copies of the original
`settings.scc` and capture in `<root>/UserDocuments/Swag Capture`; Rust uses `--data-dir` and its
previously imported JSON settings, redirected to that same isolated library. The source settings
hash is `23c8b578a1a05abf6fa76489cef018e6449dbe62404784d492935c500533bcd0`; its modification
precedes the measurements and its bytes match the copied profile. The original library and
settings are not written. Sandbox restrictions suppress Swag's shell-registration side effects,
so this is not an unrestricted personal-profile launch.

The library contains one actual capture,
`10_30_2026_13_59_56_35CF40B6F62B4B10.scc` (677 x 303), rather than all 753 library items.
The no-document variant keeps the same settings but omits the capture. Both applications restore
comparable placement on the left display. DPI-aware physical rectangles are Swag
`[-3383, 135, -818, 1923]` and Rust `[-3356, 162, -845, 1896]`; Swag's outer shadow margin makes
its outer bounds larger. Feature, renderer and settings-schema parity are not established.

**External launch measurements**

All times below are milliseconds from OS process creation, using `GetProcessTimes` creation
FILETIME, `GetSystemTimePreciseAsFileTime` and QPC. The probe polls at approximately 5 ms and
calls `SetProcessDPIAware` before querying geometry. Machine-load admission runs before each
launch. No OS-cache flush or reboot is performed: these are repeated warm launches on a shared
machine, not cold-start numbers. Debugger/profile runs are excluded from the launch medians.

| Milestone | Swag median (range), n=3 | Rust median (range), n=3 |
| --- | ---: | ---: |
| First detected application HWND, possibly hidden | 58.9 (57.3-60.1) | 72.8 (61.9-109.2) |
| First visible application HWND at least 500 x 300 physical pixels | 763.7 (752.6-777.0) | 175.8 (165.2-219.8) |
| First successful `WM_NULL` response after visibility | 782.0 (766.8-791.6) | 364.8 (276.8-437.5) |

Individual retained runs, in the order `(HWND created, visible, message response)`:

- Swag: `(58.9, 777.0, 791.6)`, `(57.3, 752.6, 766.8)`, `(60.1, 763.7, 782.0)`.
- Rust: `(61.9, 175.8, 276.8)`, `(109.2, 219.8, 437.5)`, `(72.8, 165.2, 364.8)`.
- Swag with no capture: visible at 777.7 and 778.6; message response at 795.0 and 795.9.

Visibility is not first pixel presentation, and a successful `WM_NULL` is not proof that the
document is loaded or its final frame displayed. The different visibility/response gaps show
why these milestones must not be conflated. Rust's existing `first_ui_update_ms` starts after
part of application/renderer initialization and cannot replace a process-to-first-frame metric.
Early exploratory runs used a coarser system/monotonic clock; they are excluded from this table.

Process CPU before visibility is 1,468.8-2,250.0 ms for Swag (median 1,968.8) and 93.8-140.6 ms
for Rust (median 109.4). CPU is summed across threads and can exceed elapsed time; it also ends
at different initialization milestones in the two applications. Before the message-response
milestone, the two Rust runs that recorded CPU use 312.5 and 343.8 ms. These are not equivalent
whole-startup work budgets, but they support substantial parallel CPU work before Swag shows.

**Function-level attribution**

Two separate probe-owned Swag launches attach a debugger and place entry/return breakpoints at
functions resolved from the executable's embedded `.swagdbg` table. Handler-processing time is
subtracted from spans, but trap delivery, event polling and scheduling overhead remain. Fast
cache-hit calls are particularly sensitive to that overhead. These approximate spans are not
used to compute the unprofiled launch medians; the traced launches become visible at 792.1 and
833.8 ms. Main-thread stack sampling in two additional runs corroborates icon/widget CPU
rasterization, MSDF glyph generation, and the OpenGL readback/presentation path.

| Function/path | Trace A | Trace B | Scope |
| --- | ---: | ---: | --- |
| `Theme.setupDefault` | 90.4 | 90.4 | Includes widgets and default font initialization |
| `themeWidgetsImage` | 82.6 | 81.8 | One initial rasterization |
| `Theme.setupDefaultFonts` | 3.2 | 3.8 | Typeface/default-font setup, not all later glyph generation |
| `IconAtlas.image`, first five expensive calls | 402.4 | 427.3 | Stock GUI and Capture sheets at several cell sizes |
| `IconAtlas.image`, all nine observed calls | 409.8 | 432.6 | Also includes immediate warm/cache-hit calls |
| `MainWnd.create` | 277.8 | 292.3 | Includes some of the icon work above |
| `Application.loadState` | 204.2 | 224.7 | Includes downstream repaint/icon work; not isolated file I/O |
| `Surface.show` | 246.1 | 270.3 | Includes state restoration and initial presentation |
| `Surface.prepareNativePresentation`, two calls | 55.5 | 48.4 | GPU readback, CPU copy, initial bitmap preparation |
| `Surface.publishNativePresentation`, six observed calls | 29.5 | 34.1 | Includes immediate post-show updates |
| `Capture.load`, two observed attempts | 13.0 | 14.2 | After `Surface.show`; successful document load about 11.1/12.5 |

Spans overlap through nesting: do not add `MainWnd.create`, `Surface.show`, `loadState` and their
icon/readback children to manufacture a startup total. The measured default-font initialization
is small; MSDF glyph generation seen during painting is a separate cost not isolated by these
breakpoints. Capture loading follows the display path in both traces, consistent with the
no-document control not materially shortening time to visibility.

The five initial icon calls request physical cell sizes `32, 32, 40, 48, 28`:

| Request | Trace A | Trace B |
| --- | ---: | ---: |
| GUI sheet at 32 px | 64.4 | 66.1 |
| Capture sheet at 32 px | 38.9 | 40.7 |
| 40 px sheet | 73.7 | 72.1 |
| 48 px sheet | 130.9 | 141.7 |
| 28 px sheet | 94.5 | 106.8 |

The two 32 px requests belong to different atlas owners, as their callers show; they are not
evidence that a same-key cache lookup rerasterizes one sheet. Subsequent 48/28 px requests are
cheap in the trace. The actionable issue is preparing entire sheets for several first-use sizes
before showing the interface.

**Current resource design and the Rust comparison**

`IconAtlas.image` in `paint/iconset.swg` caches by physical cell size. `IconSet.list` rounds the
device scale upward and combines it with logical icon size. A missing size rasterizes the entire
SVG grid with supersampling initially set to four, bounded by an 8192-pixel internal width.
The cache lives only in the process. The theme widgets follow the same general pattern through
`Theme.ensureAtlasScale` and `themeWidgetsImage`, with their own scale and buffer bound.

The present design keeps a vector source for arbitrary sizes/DPI and resource overrides. CPU
rasterization also avoids a recorded hidden-window OpenGL/DisplayLink failure. That history
explains the runtime path; it does not require repeating the stock asset work at every launch
or rule out offline generation using the same CPU renderer.

The Rust prototype does **not** embed prerasterized Capture icons. In its `src/icons.rs`,
`include_bytes!` embeds the original SVG; the first `paint` call parses it with resvg, renders it
into one 768 x 480 texture at scale four, and stores the texture in the egui context. Each
24-unit icon thus has a 96 x 96 source cell. Later paints reuse that one texture with linear
filtering. The prototype also does not reproduce Swag's widgets atlas: egui draws its controls.
It performs less atlas construction, with a different rasterizer and sampling policy. The
complete difference must not be described as Rust using offline images or as a compiler win.

**Quality and generated-asset decision**

A single large atlas resized for all output sizes can change small-stroke coverage and edge
sharpness relative to Swag's size-specific supersampled rasterization. No matched visual/error
measurement establishes that the Rust icons are uniformly inferior, equivalent, or superior.
Do not infer visible quality from startup time alone, or adopt the Rust sampling policy merely
because it is faster in the incomplete clone.

Offline generation of the same target sizes with the same SVG inputs, rasterizer, sample count,
premultiplied alpha and color space can preserve the current raster pixels. Use lossless storage
and deterministic generation, and prove the embedded decode matches the runtime reference.
The timing of generation need not lower quality. Evaluate a bounded stock size/DPI set against
one high-resolution atlas with reviewed resampling; they are distinct quality/size tradeoffs.
Keep custom SVG and ungenerated sizes on a correct runtime fallback. Include source content and
rasterization/version parameters in any persistent-cache key, and avoid stale assets after theme
or renderer changes. Measure added EXE bytes, decode time, retained CPU/GPU pixels and fallback
cost before choosing PNG, raw data, compression, or a persistent disk cache.

Initial presentation is a secondary independent cost. In the measured image,
`prepareNativePresentation` reads the full OpenGL target back to CPU memory and copies it into
the layered window's DIB; `publishNativePresentation` calls `UpdateLayeredWindowIndirect`.
Preserve the existing geometry/pixel publication contract and monitor-adapter correctness when
investigating redundant startup frames under std.gui.057. Do not blindly restore the rejected
hidden-window GPU-rasterization path or assume dirty-region optimizations remove full initial
presentation cost.

The full local reproduction material is under
`%LOCALAPPDATA%/swc-agent-builds/capture-startup-20261030`: `probe.py`, `trace.py`, `summary.json`,
per-run admission/launcher logs, raw timing results and stack/entry-return traces. Reconstruct
the isolated profiles and use the normal launch tools when replaying. Only probe-owned processes
may be debugged, suspended or terminated. No application source or executable was modified on
disk for the measurement. True process-to-first-present and input-to-photon timing remain to be
added before claiming equivalent usable-frame startup or a cold-launch improvement.
