# Findings — Gui And Applications

`std/gui`, the widgets and dialogs it ships, and the applications built on it. Intent for the same
units is [todo.gui.md](todo.gui.md), [todo.scapture.md](todo.scapture.md) and
[todo.scrypt.md](todo.scrypt.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-006 — Data-driven UI resource for `std/gui`

- Area: bin/std
- Found while: simplifying the sCrypt vault cards after `FormCtrl` was judged too heavy
- Observation: a UI described by a data string is only worth it when the caller never needs the
  controls back. The removed `FormCtrl` proved the opposite case: every consumer built an
  `Array'FormFieldDefinition`, then immediately recovered typed pointers by string identifier
  (`notnull (notnull form.findField("create.size")).accessoryChoice`), so the data layer added a
  stringly-typed boundary without removing a single control pointer. A full markup would extend
  that boundary from four fields to the whole window unless the resource is resolved at compile
  time into typed members.
- Evidence: commits 3b382e68a and 8009467a0 removed `FormCtrl`, `FormFieldDefinition`,
  `FormFieldKind`, `FormChoice`, and `FormField` (177 lines) and replaced three consumers with
  `FormLayoutCtrl` builders that return the concrete control. sCrypt's two cards lost their two
  field-description functions and every `findField` lookup. `Core.File.TweakFile` already parses a
  text format onto struct fields through reflection, and `ThemeStyle.addStyleSheetColors` shows the
  existing string-resource precedent in `std/gui`.
- Next step: prototype the compile-time half first, since it is what decides the design. Parse a
  small UI resource in a `#run` block with `TweakFile` as the model, and check whether the parsed
  tree can emit typed member declarations for a window struct through `#code`/generated source. If
  typed accessors cannot be generated at compile time, a UI resource reintroduces exactly the
  lookup boundary the builders just removed, and a resource editor would ship that cost to every
  window. Only then evaluate the editor.

### F-017 — sCapture keeps a dark editor matte after switching to the light theme

- Area: bin/apps
- Found while: comparing sCapture in both Swag palettes through the gui10 theme inspector
- Observation: the matte around the capture is `EditorOptions.editBackColor`, whose default was a
  fixed `0xFF2E2E2E`. It now defaults to transparent, meaning "follow the theme", and `EditView`
  resolves it to `view_Bk` — but an existing installation has the old opaque value persisted, so
  it keeps a near-black matte under a white interface.
- Evidence: [editview.swg](../bin/apps/modules/sCapture/src/editview.swg),
  [options.swg](../bin/apps/modules/sCapture/src/options.swg). A fresh profile picks up the theme; a
  profile written before this change does not.
- Next step: decide whether the options loader should migrate the one legacy value to transparent,
  or whether an application is expected to version its settings. The same question applies to any
  future option whose default becomes theme-derived.

### F-020 — Arming the headless modal driver for an absent button fails silently

- Area: std/gui
- Found while: the two `sCapture` dialog tests that did not pass — both armed a button their
  dialog does not offer (`BtnYes` for `AboutDlg`, `BtnOk` for File Details), while each of those
  boxes carries exactly one `Close` button under `BtnCancel`. Fixed in the tests.
- Observation: `clickModalButtonWhenShown(id)` accepts any `WndId`. When no modal surface ever
  exposes that id, the driver spins to `autoMaxFrames`, cancels the dialog, and leaves
  `autoHandled` false — so the test fails on an assertion far from the mistake, and the failure
  reads exactly like "the dialog never opened" even though it opened and was answered.
- Evidence: `tools/apps.bat dm test sCapture` before the fix reported 2 of 126 not passing on
  `@assert(autoHandled)`; the dialogs did open. `runAutoStage` returns false for both a missing
  modal surface and a missing button ([headless.swg:191](../bin/std/modules/gui/src/tests/framework/headless.swg#L191)),
  and only the frame ceiling distinguishes them, after the fact.
- Next step: separate the two outcomes in the driver. Remember, per stage, whether any modal
  surface was ever seen while it was armed; on the timeout path report which of the two happened —
  a modal that never appeared, or a modal that appeared without the requested button (naming the
  ids it did offer). A `Debug.assert` on the second case turns a silent 60-frame spin into a
  message that names the mistake.

### F-023 — A per-frame event can be sent but never asked for

- Area: std/gui
- Found while: making the sCapture property panel follow a live language switch
- Observation: `Application.sendFrameEvents` walks `Application.frameEvents`, and nothing in
  the repository ever adds to it. `registerFrameEvent` and `unregisterFrameEvent` are declared
  `internal` and have no caller, so the array is empty for the whole run and the call is a
  no-op every frame. The only `FrameEvent` a window actually receives is the single
  `firstFrame` one `Application.run` sends to each surface view before the loop starts, which
  means `IWnd.onFrameEvent` is a first-frame hook wearing the name of a per-frame one.
- Evidence: `grep -rn registerFrameEvent bin --include=*.swg` returns the two declarations and
  no call. Two consumers already depend on the missing half: `MainWnd.onFrameEvent` in
  sCapture only tests `evt.firstFrame`, so it works by accident, while
  `PropWnd.needRebuild` never drains — `PropWnd.onFrameEvent` is the only place that clears
  it ([propwnd.swg:1025](../bin/apps/modules/sCapture/src/propwnd.swg#L1025)) and PropWnd is not
  a surface view, so the deferred rebuild that
  [propwnd.swg:998](../bin/apps/modules/sCapture/src/propwnd.swg#L998) asks for after a
  `FormImage.kind` change silently never happens.
- Next step: decide which of the two the interface means. Either publish the registration —
  a `Wnd` flag next to `BeforeChildrenPaint`, or a public `registerFrameEvent` — and send the
  event from `runFrame` to everything registered, which makes `PropWnd.needRebuild` work as
  written; or drop `frameEvents` and `sendFrameEvents` and rename the hook for what it is,
  which then needs a different deferral for a rebuild asked for from inside the grid's own
  change notification (a posted event is the obvious one). Whichever way it goes, the
  `FormImage.kind` rebuild has to end up actually running.

### F-026 — Escape in the property grid commits the edit it is supposed to cancel

- Area: std/gui
- Found while: putting the dialog keyboard model on its feet. `EditBox` now reverts to the text it
  was given when it took the focus if — and only if — it carries
  `EditBoxFlags.ReleaseFocusOnEnterOrEscape`, which is the flag that says the box is an edit of its
  own. The property grid never lets its editors see either key, so its own answer to Escape is the
  one that counts, and that answer is wrong.
- Observation: `Properties.editKeyEvent` maps `Return` and `Escape` to the same
  `commitEdit()` ([properties.keyboard.swg:186](../bin/std/modules/gui/src/property/properties.keyboard.swg#L186)),
  which moves the focus back to the grid view; the editor's `sigFocusLost` then writes the typed
  value through. So typing over a value and pressing Escape stores what was typed. Every grid the
  reader has ever used undoes it instead, and the undo stack makes the write a second surprise.
- Evidence: `commitEdit()` is the only exit from edition mode; the two cases share one `case` arm.
  `EditBox.restoreOriginalText` already exists and does exactly what cancelling needs, and
  `EditBox.originalText` is captured on `FocusEvent.Gained`, so the value to put back is on hand.
- Next step: split the arm. `Return` keeps `commitEdit()`; `Escape` restores the editor to the
  value the row held before edition, then returns to navigation without notifying — for an
  `EditBox` that is `restoreOriginalText()`, and a `ComboBox`/`Slider` row needs the equivalent
  captured on the same focus event. Pin it with a headless test that types into a grid row, presses
  Escape, and asserts both the stored value and the empty undo stack.

### F-030 — A control can hold the keyboard on a surface that refuses input

- Area: std/gui
- Found while: making the file box answer Escape and give the keyboard back on the way out.
- Observation: `Wnd.setFocus` checks that the window itself is enabled and never that its surface
  is ([wnd.swg:1651](../bin/std/modules/gui/src/wnd/wnd.swg#L1651)). While a box is up, every other
  surface is disabled by `Application.doModalLoop`, yet anything still running on one of them — a
  timer, a frame handler, a signal from a background job — can call `setFocus` and take
  `keyboardFocusWnd` with it. Delivery is filtered afterwards by `Application.skipDisabled`, so the
  keys are simply dropped: the box under the reader's hands goes deaf with nothing to say why.
- Evidence: a surface now records its own focus (`Surface.noteFocus`), so a steal also writes a
  control of the wrong surface into that record, and the box hands the keyboard to it when it
  closes — the failure this file's neighbours were just fixed for, reachable by another route.
- Next step: refuse the focus in `setFocus` when the target surface is disabled, then confirm no
  legitimate caller places the focus before the surface it belongs to is enabled — the construction
  paths and the `Surface.enable` ordering at the end of `doModalLoop` are what to check first. Pin
  it with a headless test whose frame handler focuses a control of the caller surface while a
  dialog runs, and which asserts the box still answers Escape.

### F-031 — A rich edit inside a dialog makes the box unanswerable from the keyboard

- Area: std/gui
- Found while: fixing the same defect in `ListView`, which is what a file box opens the keyboard on.
- Observation: `RichEditView.onKeyEvent` marks every pressed key handled
  ([richeditview.swg:133](../bin/std/modules/gui/src/richedit/richeditview.swg#L133)) and declines
  Escape and Enter only when the editor carries `RichEditFlags.AutoLoseFocus`. An editor without
  that flag therefore eats Escape, Tab, and Shift+Tab, so a box built around one can be neither
  dismissed nor traversed without the pointer.
- Evidence: `Application.sendKeyboardEvents` reaches `routeUnhandledKey` — and through it the
  shortcut chain and `Surface.navigateKey` — only for a key nobody accepted, which is exactly the
  route `ListView` was blocking until this task.
- Next step: decide which keys a rich edit really claims. Tab is deliberate and documented;
  Escape is not obviously so while the surface names a cancel action. Mark only what was used, the
  way `EditBox.keyPressed` already does ([editbox.swg:372](../bin/std/modules/gui/src/widgets/editbox.swg#L372)).

### F-038 — A check box does not line up with the fields of the form it stands in

- Area: std/gui
- Found while: adding the read-only option to the sCrypt open-vault card, which put the first
  check box of that surface directly under a column of edit boxes.
- Observation: `ThemeMetrics.btnCheck_Size` is 24 and is what `CheckButton` and `RadioButton`
  place their marker with, but the atlas tiles behind it carry their shape inset inside their cell
  (`check_bk` is a 22-unit square at 5,5 of a 32-unit tile), so the *ink* of the box starts about
  3.75 logical pixels inside the rectangle the widget was given. A box placed at the left edge of a
  form column therefore reads as indented against every field above it.
- Evidence: measured on the rendered surface, `bin/apps/modules/sCrypt` in `swagLightPalette`: the
  edit borders of the middle card start at x=572 and the check box ink starts at x=575.
- Next step: decide who owns the difference. Either the tiles fill their cell and `btnCheck_Size`
  becomes the ink (which changes the drawn box everywhere, from about 16.5 to 24 logical pixels),
  or the widgets learn the inset and place the cell so the ink lands on the rectangle they were
  given. The second keeps the drawn size and is the smaller change, but it needs the inset to come
  from the theme rather than from a constant in the widget — `ThemeImageRect` is where the atlas
  already describes itself.

### F-039 — The sCapture main window cannot be painted headlessly

- Area: apps/sCapture
- Found while: photographing both shipped surfaces in every palette, to review them without a
  desktop. sCrypt renders; sCapture faults.
- Observation: a headless host that builds the real window with `MainWnd.create(&gui.root)` — the
  same call `dialogs.test.swg` already makes and which succeeds — dies with an access violation
  (0xC0000005) as soon as that window is laid out and painted. Creating it and never painting it is
  fine, which is what every existing test does.
- Evidence: reproduced four times, in release, with and without a `Capture` set on the edit view,
  with and without `Library.init` through `testUseScratchLibrary`, and with and without a theme
  broadcast — the fault survives all six combinations, so it is neither the capture, nor the
  library, nor the harness change made in the same task. The 127 other tests of the module pass in
  the same binary.
- Next step: bisect the paint rather than the setup. `MainWnd.create` builds a command row, a tool
  rail, an edit window, a recent bar and a right bar; hide them one at a time before the first
  `settleAnimations` and find which subtree faults. The likely shapes are a renderer resource a
  real start creates and the fixture does not, or a monitor list — `Env.getMonitors()` is read at
  construction and is empty on a headless run.
- Why it matters beyond the crash: sCapture has 128 tests and none of them can see the window, so
  no appearance regression in the one application that *is* a visual tool can ever fail a test.
  The same photograph is one test away for sCrypt and impossible here.

### F-040 — sCapture dies when its window is moved and resized in one call

- Area: apps/sCapture, std/gui
- Found while: driving the shipped window from a script to photograph its pages. The window opens
  maximized across a two-monitor desktop, so a capture has to bring it back onto one screen first.
- Observation: `SetWindowPos(hwnd, HWND_TOPMOST, 40, 40, 2400, 1500, 0)` — one call that moves,
  resizes and raises — kills the process three times out of four. The same call with `SWP_NOSIZE`
  (move only) has never killed it. Dragging the window by hand does not either, which is why the
  application looks healthy in normal use.
- Evidence: reproduced from a plain PowerShell driver against the packaged build, four attempts,
  three deaths, no window left behind. `GetWindowRect` on the survivor returns the requested
  rectangle, so the call itself succeeds before the process goes.
- Suspicion, not conclusion: the two monitors of this desktop are at different scales, so that one
  call crosses a DPI boundary *and* changes the client size in the same message. The surface
  rebuilds its render target on a size change and re-reads its scale on a DPI change; doing both
  from one message is the path a hand-drag never takes.
- Next step: reproduce with a minimal `gui2`-sized example under the same two-monitor arrangement,
  then bisect: move-only across the boundary, resize-only on one screen, then both. If it is the
  DPI crossing, `Surface` is where the ordering of the two rebuilds is decided.
