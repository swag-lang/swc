# Instrument design migration

Every entry moves the standard applications, the shared GUI toolkit, and every modal box under
`bin/` to the Instrument direction described in [README.md](README.md). The mockups and their
renders live beside this file; the current state is the application goldens they link to.

The order below is the dependency order: the charter, then the toolkit, then the dialogs, then
each application. An application migration may start once the toolkit entries it names are done.


## Entries

### design.instrument.001 — The Instrument direction is not yet the written charter

- Next: review [README.md](README.md) and the renders with the owner, settle the open decisions it
  lists, then rewrite in one change the four skills that contradict it:
  `design-swag-identity` (the full-width rail, the single lit plane),
  `build-swag-standard-apps` ("exactly one four-pixel accent rail", toolbar bands, readout line,
  ink chrome), `design-swag-themes` (chrome and plane tokens), and `design-swag-dialogs` (three
  layers, severity glyph, ink action bar).
- Done when: the four skills state the Instrument rules, none of them asks for a full-width accent
  rail or for a toolbar band separate from the caption, and the rules in [README.md](README.md)
  are either in a skill or deliberately dropped.
- Evidence: `build-swag-standard-apps` § Build The Standard Surface requires "exactly one
  four-pixel accent rail across the top edge of the application surface".

### design.instrument.002 — The palettes have no chrome/plane split

- Next: in `bin/std/modules/gui/src/paint/themepalette.swg` and `themecolors.swg`, make the bar
  grounds (`toolBar`, `commandBar`, `informationBar`) resolve to the chrome ground and `view` to
  the document plane, with the values in [README.md § Tokens](README.md#tokens) for
  `swagDarkPalette` and a new paper pair for the light palette; pin them in
  `theme.colors.test.swg`.
- Done when: gui10 `--palettes` shows chrome, plane, raised and line as the only grounds of the
  Swag palettes; every mark still clears `MarkContrast` on every ground; the golden campaign is
  reviewed and accepted.
- Evidence: `swagDarkPalette` writes five distinct grounds (`0B0B0D`, `15151A`, `1A1A20`,
  `25252D`, `2A2A32`); the goldens read as grey bands stacked over a darker card
  ([Scope](../../bin/apps/modules/swagscope/src/tests/goldens/viewer.dark.png),
  [Prism](../../bin/apps/modules/swagprism/src/tests/goldens/surface.png)).
- Decision: whether the neutral dark and light palettes adopt the split or keep following the
  desktop. The mockups assume only the two Swag palettes (ink and paper) do.

### design.instrument.003 — An application cannot place its bar in the caption

- Next: give `SurfaceWnd` a public caption contract with three groups — leading (after the mark),
  centered (on the window, not on the free space), trailing (before the Appearance button) — and
  keep the empty caption area draggable with double-click to maximize. Port Swag Capture's menu
  bar to it first.
- Done when: Capture's menu bar uses the contract with no negative margin; a gui test asserts the
  drag region, the window-centered group, and the collapse order at the minimum window width.
- Evidence: `MainWnd.createTopMenu` in `bin/apps/modules/swagcapture/src/mainwnd.layout.swg`
  docks the bar with `.margin.y = -parentWnd.padding.y` and recomputes the mark's width by hand.
- Related: design.instrument.009, design.instrument.010, design.instrument.011,
  design.instrument.012

### design.instrument.004 — Every application draws a full-width accent rail

- Next: let the caption draw the notch (64 × 3 logical units at the leading edge, its trailing end
  cut at 45°, `signature.ground`, plus the deepened `signature.mark` hairline under it on paper)
  as a palette decision like `captionGlow`; then delete the four rail separators.
- Done when: no `Separator.create(…, .Top, .Accent)` remains under `bin/apps`, and a caption golden
  shows the notch in the Swag ink and paper palettes and its absence in the neutral ones.
- Evidence: the rail is created in `swagscope/src/viewerwindow.layout.swg`,
  `swagcapture/src/mainwnd.swg`, `swagprism/src/mainwindow.swg` and `swagvault/src/mainwindow.swg`.

### design.instrument.005 — There is no shared readout line

- Next: add a 28-unit readout control to `bin/std/modules/gui` (name it through
  `design-swag-bin-modules`): chrome ground, fixed-width 11-unit segments made of a faint label and a
  soft value, column stops that can align with a panel/document split, and a trailing options
  trigger opening a popup.
- Done when: the control has layout and golden tests, survives French at minimum width by
  dropping trailing segments in a declared order, and Swag Scope uses it.
- Evidence: each application reports measurements its own way — Scope's `ViewerInfoBar` plus a
  bottom band holding one options button, Prism's "Ready" label, Vault's status card, Capture's
  size and zoom in the toolbar.
- Related: design.instrument.009

### design.instrument.006 — Panels, lists and labels do not share one measure

- Next: audit list, tree and property rows against the panel rules in
  [README.md § Panels](README.md#panels) — 28-unit rows, selection by alternate-tone ground with no
  rail, uppercase section labels, kind chips with a 4-unit cut — and move the differing metrics
  into `ThemeMetrics`.
- Done when: Scope's outline, Capture's library sidebar, Vault's recent vaults and the file dialog's
  places use the same row control and metrics, checked by one gui golden.

### design.instrument.007 — Popup menus are not on the raised ground

- Next: set popup ground to the raised token, its border to the line token, a 6-unit corner joined
  to its trigger, alternate-tone hover and selection, and a check mark for a stored value.
- Done when: `menu.test.swg` and `properties.test.swg` goldens show the joined popup in ink and
  paper, and the joined-tab rule of `design-swag-identity` still holds.

### design.instrument.008 — The predefined dialogs are one flat surface

- Next: in `bin/std/modules/gui/src/dialogs/dialog.swg`, paint the caption and the action bar on
  chrome and the content view on the plane; replace the round icon of the message and About boxes
  with the 20-unit severity glyph or the application tile; lay out `AboutDlg` as tile, name,
  fixed-width version and date, sections, links; give `FileDlg` its places on chrome and its list on
  the plane; align `FormDlg` labels on one column.
- Done when: `dialogs.charter.test.swg` and `dialogs.layout.test.swg` pass with reviewed goldens,
  `gui9` shows every predefined box in ink and paper, and no dialog metric changed value.
- Evidence: [aboutdlg.identity.dark.png](../../bin/std/modules/gui/src/tests/goldens/aboutdlg.identity.dark.png)
  still carries the full-width rail and a round information icon.
- Related: design.instrument.002

### design.instrument.009 — Swag Scope still stacks four chrome bands

- Next: move the action bar (open, explore, search, viewer selector, panels, full screen) into the
  caption, the file identity into the caption's leading group, the information bar's readings and
  the bottom options band into the readout line, and let every viewer reach the window edges;
  move the explorer's navigation band into the caption and its information panel to a chrome
  sheet; give the empty surface its recent files.
- Done when: the Scope goldens (`surface`, `viewer.dark`, `viewer.light`, `search.*`,
  `explorer.*`, `error`, `loading`) are regenerated to match
  [scope.code](imgs/scope.code.png), [scope.explorer](imgs/scope.explorer.png),
  [scope.hex](imgs/scope.hex.png), [scope.markdown.paper](imgs/scope.markdown.paper.png) and
  [scope.home](imgs/scope.home.png), in English and French, at the minimum window size.
- Evidence: [surface.png](../../bin/apps/modules/swagscope/src/tests/goldens/surface.png) and
  [explorer.gallery.png](../../bin/apps/modules/swagscope/src/tests/goldens/explorer.gallery.png).
- Related: design.instrument.003, design.instrument.004, design.instrument.005

### design.instrument.010 — Swag Capture splits its modes with two filled buttons

- Next: replace the Capture/Library filled buttons by a segmented mode switch centered in the
  caption, put the capture command in the caption as the one Voltage split button, keep the tool
  rail with its leading rule, put the property sheet and the recent-captures strip on chrome and the
  canvas on the plane, and move size, object count, link, pointer and zoom to the readout line.
  In the library, the View and Filter menus join the caption's trailing group and Folders becomes
  a sidebar section.
- Done when: `surface.png`, `library.surface.png` and the menu goldens match
  [capture.editor](imgs/capture.editor.png) and [capture.library](imgs/capture.library.png).
- Evidence: [surface.png](../../bin/apps/modules/swagcapture/src/tests/goldens/surface.png) fills
  the Capture button in Voltage and the Library button in Arc side by side.
- Related: design.instrument.003, design.instrument.005

### design.instrument.011 — Swag Prism frames every pane as a card

- Next: put the example selector in the caption as the document identity, Compile and Auto in the
  centered group, the view count and build options in the trailing group; make source and views
  full-height planes separated by one chrome step, each with an in-pane header of borderless
  selectors (viewer, stage, optimization level); report position, instruction counts and compile
  time on the readout line.
- Done when: the four Prism goldens match [prism.compare](imgs/prism.compare.png) in layout and
  palette, including the 2D-render and GUI viewers.
- Evidence: [surface.comparison.png](../../bin/apps/modules/swagprism/src/tests/goldens/surface.comparison.png).
- Related: design.instrument.003, design.instrument.005

### design.instrument.012 — Swag Vault is a banner over a card of tabs

- Next: move the four tabs into the caption as a segmented control, drop the title and subtitle
  banner (the subtitle and the WinFsp notice go to About), list recent vaults and mounted drives in
  a chrome panel, set the active form on the plane in one 680-unit column, present Password, Key
  files, Capacity and Hidden volume as alternate-tone actions beside the one Voltage action, and
  move the status card to the readout line.
- Done when: `surface.png` and `surface.open.png` match [vault.open](imgs/vault.open.png), the
  recent-vault panel is empty and hidden while privacy mode is on, and the window keeps every
  form usable at its minimum size.
- Evidence: [surface.open.png](../../bin/apps/modules/swagvault/src/tests/goldens/surface.open.png).
- Decision: Vault's default window size; the mockup assumes it opens like the other applications.
- Related: design.instrument.003, design.instrument.005, design.instrument.006

### design.instrument.013 — Application dialogs author their own sizes

- Next: remove the literal sizes from Swag Capture's boxes — New image (`actionfile.swg`, 350 ×
  235), File details (`actionfile.swg`, 600 × 400), Resize and Expand (`actionimage.swg`, 350 ×
  265), Options (`actionoptions.swg`, 800 × 600) — and fit them with `fitHeightToContent` on the
  `FormDlg` label column; give Options a chrome section list beside a plane of property rows.
  Check that Swag Vault's six `FormDlg` boxes (`mainwindow.operation.swg`,
  `mainwindow.startup.swg`) need nothing beyond design.instrument.008.
- Done when: no `Dialog.create` under `bin/apps` passes an authored height, every application box
  appears in an application golden or in a dialog test, and the result matches
  [dialogs.apps](imgs/dialogs.apps.png) in ink and paper.
- Related: design.instrument.008

### design.instrument.014 — The backlog validator does not read this folder

- Next: let `auditBacklog` in `tools/src/backlog.swg` also enumerate `backlog/design/*.md`, match
  index rows that carry the folder prefix, and resolve allocation history under that path.
- Done when: `bin\swc.exe --num-cores 6 tools\tests\repository.swgs .` reports a broken link or a
  reused identifier in this file.
- Evidence: `auditBacklog` calls `Directory.enumerateFiles` without `recurse`, so identifiers and
  links here are not checked.
