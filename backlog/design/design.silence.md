# Silence migration

Every entry moves part of `bin/` to the charter in [README.md](README.md). The order is the
dependency order: themes and controls, window chrome and shared components, property grid and
dialogs, then each application, then the written rules.


## Entries

### design.silence.002 — A few controls still differ from the charter pictures

- Evidence: `controls.charter.test.swg` renders every control of the Controls section in both
  themes (`controls.charter.ink.png`, `controls.charter.paper.png`). What it does not show yet:
  the menu check sits in the leading glyph column instead of the trailing edge; the chosen segment
  on Papier is white without its soft lift shadow; the toolkit has no numeric stepper (`− 48 +`);
  scroll bars are thin but always visible rather than shown while scrolling or on hover.
- Next: move the menu check to the trailing edge of its row in `MenuCtrl.paintPopup` and
  `computeLayoutPopup`, then add the lift shadow under a chosen Papier segment.
- Done when: the two charter wall goldens match the two controls pictures control by control.

### design.silence.003 — Windows still draw a caption band

- Next: make `SurfaceWnd` draw the Silence chrome (no band, faint glyph and title, faint window
  buttons, draggable top strip, no accent rail or glow) and remove every application rail.
- Done when: no `Separator.create(…, .Top, .Accent)` remains under `bin/` and the window goldens
  show the Silence chrome in both themes.

### design.silence.004 — There is no lens, sheet, inspector, mini-bar or dock

- Next: add the shared components of the charter to `bin/std/modules/gui` with tests and
  goldens, each a reusable control an application composes.
- Done when: the four applications use them and no application re-implements one.
- Related: design.silence.003

### design.silence.005 — The property grid predates the charter

- Next: restyle the four `PropertiesKind` layouts and `PropertiesCtrl` to the Property grid
  section: marks, notes, validation, search, sections and the layout menu.
- Done when: the property goldens match the two property pictures in both themes.
- Related: design.silence.002

### design.silence.006 — Dialogs still have a caption and a separate action bar

- Next: move the dialog family of `bin/std/modules/gui/src/dialogs` to the Dialogs section, then
  the dialogs the applications build.
- Done when: `dialogs.charter.test.swg` and `dialogs.layout.test.swg` pin the new composition
  and every dialog golden matches the dialog pictures.
- Related: design.silence.003

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

- Next: move every `bin/examples` program and other consumer to the two themes and the new
  components.
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

### design.silence.013 — The backlog validator does not read this folder

- Next: let `auditBacklog` in `tools/src/backlog.swg` also enumerate `backlog/design/*.md`.
- Done when: `bin\swc.exe --num-cores 6 tools\tests\repository.swgs .` reports a broken link or a
  reused identifier in this file.
