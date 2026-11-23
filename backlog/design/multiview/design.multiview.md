# Multiview

Every entry brings part of Swag Scope to the design in [README.md](README.md). The functional
work it depends on keeps its own entries, named under Related; an entry here is done when the
application matches its pictures. The order is the dependency order: the scene model, tabs,
layouts, comparison, then media played together.

## Entries

### design.multiview.001 — A window holds one document, not a scene of views

- Evidence: `ViewerWindow` owns one active file and viewer; opening another file replaces it
  (app.scope.001). The design's every other part needs documents, views and scenes as separate
  things, with one active view receiving the lens, the sheet, search and the keys.
- Next: separate the per-document state (viewer, host services, privacy, history, loading
  overlay) from the window, then hold a scene of one view with no visible change.
- Done when: a window with one file matches `single.paper.png` and the existing Scope goldens
  unchanged, while its document lives in a view of a scene.
- Related: app.scope.001, std.gui.029

### design.multiview.002 — Scenes are not kept in tabs

- Evidence: there is no tab row and no scene switcher (`tabs.png`).
- Next: turn the centred title into the scene row from the second scene on, with the Arc
  underline and its 180 ms slide; add the `Ctrl Tab` switcher on the lens's floating surface;
  suspend inactive scenes and restore scenes on launch.
- Done when: `tabs.png` is matched whole-screen in Encre, one scene still shows only its title,
  switching keeps every scene's state, and a relaunch restores scenes, layouts and links.
- Related: app.scope.001, app.scope.viewers.003

### design.multiview.003 — A second file cannot be placed beside the first

- Evidence: no layout choice, drop target, explorer multi-selection route or command-line pair
  exists (`lens.paper.png`, `drop.png`, `grid.zoomed.png`).
- Next: add the layouts as one segmented choice in the lens, the five drop targets, Open Beside…,
  the explorer's multi-selection routes, the active-view marks, Maximize View with its map, and
  the `Alt` and `Ctrl Alt` arrows.
- Done when: the three pictures are matched, every route in the README's table opens the scene
  it names, and closing or replacing a view leaves the others' state and input intact.
- Related: app.scope.003

### design.multiview.004 — Two texts cannot be compared side by side

- Evidence: Scope cannot compare two local texts (app.scope.diff.002), and the charter has no
  Removed and Added tokens (`compare.text.png`).
- Next: add Removed and Added to both themes in the charter, then the aligned columns, hatched
  gaps, gutter signs, intraline marks, the difference band and the foot's count.
- Done when: `compare.text.png` is matched, `F7` and `Shift F7` step through the differences, the
  lens holds the comparison options, and the same band and keys serve hexadecimal comparison.
- Related: app.scope.diff.001, app.scope.diff.002, app.scope.hexa.003, app.scope.binary.005

### design.multiview.005 — Two pictures cannot be compared

- Evidence: no comparison mode exists for images (app.scope.image.006); `compare.image.paper.png`
  draws the curtain with the mode word and the dual pixel probe at the foot.
- Next: add Side by Side with linked zoom and pan, then Curtain, Onion Skin, Difference and Flip,
  the mode word as the anchor of their menu, and the dual probe.
- Done when: `compare.image.paper.png` is matched, each mode has a golden, and images of
  different sizes align by fit and pixel for pixel.
- Related: app.scope.image.006, app.scope.video.011

### design.multiview.006 — The sheet describes one file only

- Evidence: `I` shows one file's facts; `compare.sheet.png` draws the wider sheet with Different
  and Identical sections.
- Next: give the sheet a comparison form fed by each viewer's facts, differing facts first.
- Done when: `compare.sheet.png` is matched for two videos, and texts, images and fonts give their
  own comparable facts.
- Related: app.scope.viewers.006, app.scope.video.010

### design.multiview.007 — Media cannot play together in a grid

- Evidence: no grid, scene clock or link exists; the video viewer plays one file
  (`grid.playing.png`, `grid.rest.png`).
- Next: add the grid layouts for media, one scene transport on the video viewer's veil, the cell
  names with offsets, the Linked chip and its menu, the scene clock with Absolute, Relative and
  Leader modes, Align Here, At End, and the decode budget; Align on Sound after them.
- Done when: both pictures are matched; nine 1080p videos play linked in a 3 × 3 grid without
  drift beyond half a frame; mixed frame rates step on the leader's rate; a view that falls
  behind says so without moving the others; one sound plays.
- Release verification covered nine 1920 × 1080 H.264 files at 24 fps in a 3 × 3 native
  window, using Xvfb and Mesa on four CPUs. Over a 4.3 s play segment the leader reached
  frame 102 and the largest observed difference between displayed frames was 13 frames.
  Delayed followers triggered the Behind state. The half-frame acceptance remains open.
- The scene bounds the decoded queue at presentation size and plays one sound stream.
  Software decoding still reconstructs source-resolution pictures. Hardware decoder budgeting
  and container chapter marks depend on app.scope.video.013 and app.scope.video.004.
- Related: app.scope.video.004, app.scope.video.009, app.scope.video.013, app.scope.audio.005
