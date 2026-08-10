# Findings — Gui

`std/gui`, and the widgets and dialogs it ships. Intent for the same unit is
[todo.gui.md](todo.gui.md).

An entry noticed while working on an application belongs here when `std/gui` is where it will be
fixed; an entry that will be fixed inside the application goes to that application's own file, such
as [findings.scapture.md](findings.scapture.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Declarative UI and headless automation

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

### F-020 — Arming the headless modal driver for an absent button fails silently

- Area: std/gui
- Found while: the two `sCapture` dialog tests that did not pass — both armed a button their
  dialog does not offer (`BtnYes` for `AboutDlg`, `BtnOk` for File Details), while each of those
  boxes carries exactly one `Close` button under `BtnCancel`. Fixed in the tests.
- Observation: `clickModalButtonWhenShown(id)` accepts any `WndId`. When no modal surface ever
  exposes that id, the driver spins to `autoMaxFrames`, cancels the dialog, and leaves
  `autoHandled` false — so the test fails on an assertion far from the mistake, and the failure
  reads exactly like "the dialog never opened" even though it opened and was answered.
- Evidence: `swc tools/apps.swgs dm test sCapture` before the fix reported 2 of 126 not passing on
  `@assert(autoHandled)`; the dialogs did open. `runAutoStage` returns false for both a missing
  modal surface and a missing button ([headless.swg:191](../bin/std/modules/gui/src/tests/framework/headless.swg#L191)),
  and only the frame ceiling distinguishes them, after the fact.
- Next step: separate the two outcomes in the driver. Remember, per stage, whether any modal
  surface was ever seen while it was armed; on the timeout path report which of the two happened —
  a modal that never appeared, or a modal that appeared without the requested button (naming the
  ids it did offer). A `Debug.assert` on the second case turns a silent 60-frame spin into a
  message that names the mistake.

## Keyboard interaction and focus

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

## Layout invalidation and alignment

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
  edit borders of the middle card start at x=572 and the check box ink starts at x=575. The same
  inset exists vertically on other atlas glyphs: in `scrypt.surface.png` the folder icon of the
  container-file field is drawn in a 17-unit cell whose middle lands on the middle of the box, and
  its ink still comes out about a pixel above that middle.
- Next step: decide who owns the difference. Either the tiles fill their cell and `btnCheck_Size`
  becomes the ink (which changes the drawn box everywhere, from about 16.5 to 24 logical pixels),
  or the widgets learn the inset and place the cell so the ink lands on the rectangle they were
  given. The second keeps the drawn size and is the smaller change, but it needs the inset to come
  from the theme rather than from a constant in the widget — `ThemeImageRect` is where the atlas
  already describes itself.

### F-044 — `Wnd.invalidateLayout` marks a window dirty and nothing ever reads the mark

- Area: std/gui
- Found while: making a `FormLayoutCtrl` answer for its own height, so a card's help paragraph stops
  being cut off in a longer translation
- Observation: `invalidateLayout` sets `Wnd.layoutDirty`, `measure` clears it, and **nothing else in
  the repository reads it**. So there is no deferred layout pass: a window whose content changed
  without its rectangle changing is never re-arranged. `resize` returns early when the size is
  unchanged, which is the common case for a re-labelled control — the band keeps its width and the
  caption inside it needs more room.
- Evidence: `grep -rn layoutDirty bin --include=*.swg` returns three sites, all writes
  ([wnd.swg:301](../bin/std/modules/gui/src/wnd/wnd.swg#L301),
  [wnd.swg:914](../bin/std/modules/gui/src/wnd/wnd.swg#L914),
  [wnd.swg:980](../bin/std/modules/gui/src/wnd/wnd.swg#L980)). Measured directly: with
  `FormLayoutCtrl` arranging only from `onResizeEvent`, sCrypt's French "Parcourir" button stayed at
  its English 104 while its own measure asked for 115, and `Testing.assertContentFits` caught it.
  `VaultCard.endForm` now calls `form.computeLayout()` by hand for exactly this reason, and every
  other container that arranges children carries the same latent hole — `invalidateLayout` reads
  like a request and is a no-op.
- Next step: decide whether the toolkit wants a layout pass at all. Either drain the dirty windows
  once per frame — `Application.runFrame` already walks the surfaces, and the flag exists — which
  makes `invalidateLayout` mean what it says and lets the hand-written `computeLayout` calls go; or
  delete `layoutDirty` and `invalidateLayout` and make every mutator arrange immediately, which is
  honest but pays the cost on each of the twenty-odd setters that call it today. Do not add a third
  state. Pin whichever way it goes with a headless test that re-labels a control inside a docked
  band and asserts the band re-measured without anything being resized.

## Native resources and error reporting

### F-074 — A Windows call that fails without setting a last error is reported as success

- Area: std/win32
- Found while: asking GDI for the `ttcf` table of a font that is not part of a collection
- Observation: every checked wrapper in `win32`, `gdi32`, `kernel32` and their siblings ends the
  same way — test the documented failure value, then `failWinError(GetLastError())`. But
  [win32.swg:6](../bin/std/modules/win32/src/win32.swg#L6) opens with
  `if errorMessageID == 0 do return`. When Windows answers a failure value without setting a last
  error, the wrapper raises nothing and hands the failure value back as a result. There are 126
  call sites, in `core`, `gui`, `ogl` and `pixel` as well as in the bindings themselves.
- Evidence: measured with `GetFontData(hdc, 'ttcf', 0, null, 0)` on Segoe UI and on Arial — neither is
  in a collection — returns `GDI_ERROR`, sets no last error, and the wrapper reports no failure. The
  caller receives `4294967295` as a byte count. `Array.resize` on it then failed four gigabytes
  down, and the failure surfaced as an access violation in an unrelated destructor rather than as
  the refusal it was. `TypeFace.readHfontData` now tests `GDI_ERROR` itself, which is correct at
  that call site in any case, but the other 125 sites carry the same hole untested.
- Why it is not simply a missing `else`: a zero last error after a failure value is normal on
  Windows, not exceptional. `GetFontData`, `GetGlyphOutline` and the `Get*` family document a
  sentinel and say nothing about `SetLastError`.
- Next step: make `failWinError` raise for a zero code instead of returning — a generic
  `Swag.SystemError` carrying zero still fails, which is what every one of its call sites already
  means. Then sweep for the wrappers that call it *without* first testing a failure value, because
  those depend on the current early return and would start failing on success. Validate with the
  whole Windows-facing set: `core`, `gui`, `ogl`, `pixel` and the applications.

### F-075 — A cached typeface keeps a second copy of the whole font file

- Area: std/pixel
- Found while: reordering `TypeFace.createFromHfont` so its failure path stops dropping an
  unassigned face
- Observation: `TypeFace.buffer` holds the bytes GDI returned, described as "kept alive for the
  native face". `Face.load` does not borrow them: it copies the whole file into its own
  `FaceImpl.fontData` and every slice it hands out points there. So each cached typeface holds the
  font twice.
- Evidence: `Face.loadAt` in `bin/std/modules/truetype/src/face.swg` resizes `faceData.fontData` to
  `@countof(bytes)` and copies into it before parsing anything. For a collection the cost is the
  whole collection: `msgothic.ttc` is 8.99 MB, so `MS Gothic`, `MS PGothic` and `MS UI Gothic`
  cached together hold about 54 MB where 27 MB is reachable.
- Next step: decide which of the two owns the bytes. Either drop `TypeFace.buffer` and let the face
  own its copy, which is one line and costs nothing; or give `truetype` a borrowing entry point
  that keeps the caller's slice and does not copy, which removes the duplicate on every path and
  not just this one — but it makes the face's lifetime depend on the caller's buffer, which is a
  contract change worth stating deliberately.

## Text presentation and semantics

### F-083 — Text outside a framed field is still centered on its line box, so its height follows the face

- Area: std/gui
- Found while: fixing the vertical alignment of the sCrypt container-file field, which is set in
  the fixed-width theme family and read as riding high inside its own box.
- Observation: a single line was centered by putting its *line box* on the middle of the rectangle,
  which hands the placement to the internal leading of the face. Measured on the shipped theme:
  Segoe UI at 13 has `ascent 14.03, descent -3.27, capHeight 9.11`, so its capitals sit 0.83
  logical pixels below the middle of its line box; the fixed family at 14 has
  `ascent 10.40, descent -3.60, capHeight 8.94` and sits 1.07 above. Two fields of one form set in
  the two families therefore put their words 1.9 pixels apart, and neither on the middle of the
  frame the reader compares them against. `EditBox` and `ComboBox` now center on the capitals
  through `StringVertAlignment.OpticalCenter`; every other widget still centers on the line box.
- Evidence: `Pixel.Font.opticalLineTop` and the `OpticalCenter` case in
  [drawstring.swg](../bin/std/modules/pixel/src/painter/drawstring.swg). Before the fix, in
  `bin/apps/modules/sCrypt/src/tests/goldens/scrypt.surface.png`: the "256" digits of the capacity
  field spanned rows 352..360 in a box spanning 342..373, one pixel above its middle, while the
  password placeholder below it sat exactly on the middle of its own box.
- Next step: decide whether the rest of the toolkit follows. A label, a menu entry and a list row
  are read against their neighbours rather than against a frame, and they all share the interface
  family, so line-box centering is consistent among them today — the defect only shows where a
  frame is drawn or where two families meet. If it does follow, `Gui.opticalTop` degenerates to a
  plain centering and its twenty-odd call sites go with it, and every golden holding text moves by
  the offset of its face; that is the whole cost, and it is why the change stopped at the two
  widgets that draw a frame. Pin the decision with a headless test that puts one field of each
  family side by side and asserts their capitals share a center.

### F-086 — A tooltip is presented as an editable field inside another frame

- Area: std/gui
- Found while: visually testing the sCapture library view at 150% display scale in the French
  Swag dark theme
- Observation: hovering the icon-only Library command showed its explanatory text inside a second
  edit-style frame, with a trailing control-shaped end cap that read like an unrelated button.
  The tooltip therefore looked interactive and assembled from nested widgets instead of reading
  as one passive annotation attached to its owner.
- Evidence: [`tooltip.swg`](../bin/std/modules/gui/src/tooltip.swg) builds a square `FrameWnd`, then
  puts a word-wrapped `RichEditCtrl` in it and explicitly gives that control `.Edit` form. Its
  two-pixel padding, raw 12-pixel pointer offset, editable-field chrome and auto-sized rich-edit
  viewport are combined without a tooltip-specific content/layout contract. Reproduce by hovering
  any action tooltip in sCapture; the former Library glyph made the nested trailing element
  especially visible beside the French text “Afficher la bibliothèque de captures”.
- Next step: render tooltip content with a passive text view, then define its padding, maximum
  width, corner, pointer offset and screen-edge placement as one themed tooltip contract. Add a
  visual/headless case with long translated text at 100%, 150% and 200% scale, and verify that no
  edit border, scrollbar or focusable child is present.
