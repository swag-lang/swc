# Silence migration

Every entry moves part of `bin/` to the charter in [README.md](README.md). The order is the
dependency order: themes and controls, window chrome and shared components, property grid and
dialogs, then each application, then the written rules.


## Entries

### design.silence.002 — Scroll bars are always visible

- Evidence: `ScrollWnd` bars are thin (`scrollBar_NormalSize` 10, a 6 px thumb) but are drawn
  whenever the content overflows, and they take their width from the view (`paddingZ`,
  `paddingW` in `ScrollWnd.computeLayout`). Fading them needs two things the control does not
  have: the bar must overlay the view instead of narrowing it, and `ScrollWnd` must learn that the
  pointer is over its content, which only its view's children receive (`Enter`/`Leave` reach the
  deepest window). Every list, tree, document and application golden that shows a thumb moves.
- Next: lay the bars over the view in `ScrollWnd.computeLayout`, track pointer presence through a
  hook on the view, and drive the thumb alpha with the animator — shown on a scroll or a hover,
  faded after a short idle.
- Done when: the charter wall and a scrolled list golden show no thumb at rest and one under the
  pointer, in both themes.

### design.silence.004 — The applications do not use the shared components

- Evidence: the toolkit has the lens (`Gui.Lens.View`), the information sheet (`Gui.InfoSheet`),
  the inspector (`Gui.Inspector`), the mini-bar (`Gui.MiniBar`), the dock (`Gui.ToolDock`) and the
  hint line (`Gui.HintLine`), with `floating.test.swg`, `lens.test.swg` and their goldens, and
  `AppearanceButton.addToLens`. The window strip floats over the view, and the four applications
  still inset their whole root by `Wnd.stripInset()` to keep their old bands clear of it.
- Next: per application, register every command and `addToLens` on one lens bound to `Space` or
  `Ctrl K`, move readings to the sheet, tools to the dock and the mini-bar, properties to the
  inspector, and let the work reach into the strip where its picture shows it.
- Done when: the four applications use the components, every command is a lens entry, and no
  application re-implements one or insets its whole root under the strip.
- Related: design.silence.007, design.silence.008, design.silence.009, design.silence.010

### design.silence.005 — The property grid control still lacks search marks and the layout menu

- Evidence: the rows follow the charter (`properties.{grid,condensed,list,panel}.{ink,paper}`
  goldens: Arc dot after a changed name, faint revert glyph, padlock of a read-only value, section
  labels in faint spaced capitals with a faint chevron and, in Panel, a hairline; Condensed rows of
  26 with a hairline; validation as a dot and a line in the tone; notes as the Arc notice).
  `PropertiesCtrl` does not: search marks no matched characters and shows no result count, the
  section list shows no counts, and the `•••` menu offers no Presentation choice, because
  `Properties.kind` is fixed at creation. In Panel the self-labelled editors carry no changed-value
  dot, a Condensed warning shows its line instead of a caution mark in the left margin, and the
  Panel golden shows `Opacity` at 0 while the data holds 0.4 (it did before this restyle too).
- Next: let `Properties` switch kind by rebuilding its rows, put List, Grid, Condensed and Panel
  under a Presentation section of the joined `•••` menu with `✓` in Arc, mark matched characters
  with the highlight colour and count results in the search field and the section list; then fix
  the Panel slider refresh.
- Done when: `gui.properties.ctrl.paper` is reproduced by a `properties.ctrl.{ink,paper}` golden.
- Related: design.silence.002

### design.silence.006 — The file dialog still hosts the old browser bands

- Evidence: every predefined box and the applications' own forms are floating sheets
  (`dialogs.{message,error,prompt,form,about}.{ink,paper}` goldens, `dialogs.charter.test.swg`),
  but `FileDlg` puts `FileBrowserCtrl` in the body as it was: a navigation bar, a list on the view
  ground, a status line and a label-beside-field name form, each band with its own padding.
- Next: rebuild `FileBrowserCtrl` for the box — places as text tabs with the Arc underline, one
  path field that filters, rows of 30–32 with mono faint dates and sizes on the dialog ground, and
  the type filter as a quiet `▾` given to `Dialog.setLeadingControl` — and keep it usable embedded
  (`gui9`).
- Done when: a `dialogs.file.{ink,paper}` golden matches the file box of the dialog pictures.

### design.silence.007 — Swag Scope still shows its bands

- Next: rebuild the Scope window on the Silence chrome, lens and sheet, then each viewer.
- Done when: every Scope golden matches its picture and every former band control is a lens
  entry or a sheet reading.
- Related: design.silence.004

### design.silence.008 — Swag Capture still shows menus, panels and a strip

- Next: rebuild the editor on the dock, mini-bar and inspector; the area capture and the library
  per their pictures; every menu command as a lens entry.
- Done when: the Capture goldens match the Capture pictures.
- Related: design.silence.004, design.silence.005

### design.silence.009 — Swag Prism still frames its panes

- Next: rebuild Prism as two columns with quiet text menus, the stage frieze and the comparison.
- Done when: the Prism goldens match the Prism pictures.
- Related: design.silence.004

### design.silence.010 — Swag Vault is still a banner over tabs

- Next: rebuild Vault as the list of vaults with in-place unlock, and create, progress and
  options as pages.
- Done when: the Vault goldens match the Vault pictures and privacy mode keeps the list empty.
- Related: design.silence.004, design.silence.006

### design.silence.011 — Examples and other consumers use removed APIs

- Evidence: `gui2` to `gui9` and `gui11` lay out their header from the top edge of a view that now
  reaches under the floating strip, so their first line meets the window glyph and title; `gui10`
  reads `Wnd.stripInset()` and shows the components on its Components page.
- Next: move every `bin/examples` program and other consumer to the two themes and the new
  components, and inset their headers by `Wnd.stripInset()`.
- Done when: the examples build and smoke clean in both themes.

### design.silence.012 — The skills still describe the old identity

- Next: rewrite `design-swag-identity`, `design-swag-themes`, `design-swag-dialogs` and
  `build-swag-standard-apps` so they state this charter and nothing that contradicts it.
- Done when: a new control, dialog or application written from the skills alone matches the
  charter.

### design.silence.014 — Command labels are in sentence case

- Next: move every English command label of `bin/` string tables (menus, lens entries, buttons,
  dialog actions, tabs, command tooltips) to the title-style capitalization of the charter,
  leaving sentences and French translations alone.
- Done when: a search of the English reference tables finds no command label in sentence case.

### design.silence.015 — Notices and the folding inspector still appear at once

- Evidence: the floating surfaces, menus, dialogs and the switch knob follow the Motion section
  of the charter through `Animator.arrive`, `Animator.leave` and the sheet surface fade. An
  `InfoBar` still takes its height at once, and `Inspector.setFolded` shows or hides its rows in
  one frame.
- Next: open a notice over `motion_PanelSeconds` with `Animator.animateLayoutHeight`, then fade
  its words in; fold and unfold the inspector body with the same arrival and departure as a
  floating surface.
- Done when: no shared component changes its place or presence in one frame on a user action.
- Related: design.silence.002
