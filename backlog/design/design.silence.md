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

### design.silence.003 — Content does not start in the top strip

- Evidence: `SurfaceWnd` draws the Silence chrome (`surfacewnd.chrome.*` goldens) and no
  application keeps a rail, but the top strip is still the frame's `padding.y`
  (`wnd_BigCaptionCY` 42), so the view starts below it, and Swag Capture lays its menu bar inside
  it.
- Next: give the view the whole body and let the strip float over it at the charter's 52 px,
  keeping `SurfaceWnd.hitTestCaption` answering for the parts no control covers.
- Done when: a document's first lines can sit in the strip, as `scope.read.png` shows, and the
  strip stays draggable there.
- Related: design.silence.008

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
