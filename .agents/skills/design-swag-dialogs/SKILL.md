---
name: design-swag-dialogs
description: Compose, review, or change a modal box — the predefined dialog family under bin/std/modules/gui/src/dialogs, a composite hosted inside one, or an application's own modal — to the Silence charter's floating sheet. Use whenever a dialog's width, height, inset, title, severity mark, field labels, actions, their order or wording, or the bottom-left slot changes.
---

# Design Swag Dialogs

A modal box is one composition. The family is recognized before a word of it is read: **a
floating sheet** over a dimmed window, the title as the first line of the body, the content in
one column, and the actions at the bottom right of the same surface, with the primary action
rightmost. An error, a question, a prompt, a form, a file box and an About box differ only in
their content.

The visual target is the Dialogs section of the Silence charter,
[backlog/design/README.md](../../../backlog/design/README.md#dialogs), with its pictures
[dialogs.ink](../../../backlog/design/imgs/dialogs.ink.png),
[dialogs.paper](../../../backlog/design/imgs/dialogs.paper.png) and, for the file box in every
mode, [dialogs.file.modes.paper](../../../backlog/design/imgs/dialogs.file.modes.paper.png) and
[dialogs.file.modes.ink](../../../backlog/design/imgs/dialogs.file.modes.ink.png). What still
differs from those pictures is tracked in
[design.silence.md](../../../backlog/design/design.silence.md).

Other skills govern the parts around the box:

- [design-swag-themes](../design-swag-themes/SKILL.md): the colours, controls and measures a
  dialog uses.
- [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md): the window a box opens over,
  the wording of its commands, and the spacing review inside its body
  ([Make Space Describe Relationships](../build-swag-standard-apps/SKILL.md#make-space-describe-relationships)).

This skill governs the box itself. The measurable half is enforced by
[`dialogs.charter.test.swg`](../../../bin/std/modules/gui/src/tests/dialogs.charter.test.swg),
which builds and measures every predefined box, and by
[`dialogs.layout.test.swg`](../../../bin/std/modules/gui/src/tests/dialogs.layout.test.swg),
which pins what each box fits itself to. A number argued here with no line in those tests will
drift back within a release.

## A Dialog Is A Floating Sheet

- **Surface, corner 12, the floating shadow, over a dimmed window.** It is the same kind of
  object as the lens and the sheet. [`Dialog`](../../../bin/std/modules/gui/src/dialogs/dialog.swg)
  stands on a `SurfaceFlags.Sheet` surface, which is drawn on the surface ground.
- **No caption band and no close cross.** The dim and the shadow already say "this is a dialog".
  A box is dismissed by its own actions, and by `Esc`, which presses Cancel.
- **One inset, one gap.** The body keeps an inset of 28 and puts a gap of 16 between its pieces.
  Body text is quieter than the title.

## Take Every Number From The Theme

A dialog never writes a spacing, a button size or a minimum width:

| What | Where it comes from | Charter |
| --- | --- | --- |
| Air the body keeps around its content | `dialog_Padding` | 28 |
| Air between two pieces of one body | `dialog_BtnPadding * 2` | 16 |
| Air between two actions | `dialog_BtnPadding` | 8 |
| An action's height, and a field's | `control_DialogHeight` | 34 |
| An action's width | `btnPush_Width`, widened to its caption | — |
| Narrowest a box opens | `MessageDlg.MinMessageWidth` | 440 |
| Widest a message runs before it wraps | `MessageDlg.MaxMessageWidth` | 512 |
| Title size | `dialog_TitleFontSize` | 17 |
| Critical dot | `dialog_MarkSize` | 8 |
| About tile, product name | `dialog_TileSize`, `dialog_NameFontSize` | 52, 21 |

Apart from that floor, a dialog sets no width and no height of its own: it sizes itself from its
content.

## The Title Is The First Line Of The Body

Every box names itself in the first line of its body: 17, bold, in the text ink. Set it with
`MessageDlgOptions.title`, or with `Dialog.setTitle` for a box you compose yourself. The
predefined helpers fall back to `dlg_InfoTitle`, `dlg_ConfirmTitle` and `dlg_ErrorTitle`; prefer a
specific title that says what happened ("The file changed on disk.").

- A title that **reports a situation** is a sentence: sentence case and a closing full stop.
- A title that **names the command the box carries out** ("Go to Address") repeats that command's
  label as the lens shows it, following
  [Word The Commands](../build-swag-standard-apps/SKILL.md#word-the-commands).

Titles are keys in [`Strings`](../../../bin/std/modules/gui/src/localization.swg). A key added
without its line in `src/lang/<tag>/gui.tweak` ships half translated, and nothing reports it.

## Severity Is One Dot

A failure puts an **8 px critical dot** before the title (`Dialog.setTitle(title, failure: true)`
or `MessageDlgOptions.failure`). The technical detail goes on a **mono faint line** under the
sentence (`MessageDlgOptions.detail`; `MessageDlg.error` puts a `Swag.SystemError`'s message
there). That is the whole severity vocabulary: no icon tile, no coloured band, no three-colour
icon. An information box or a question has no mark. See
[Tell A Reader What Went Wrong](../build-swag-standard-apps/SKILL.md#tell-a-reader-what-went-wrong-not-how).

## The Actions End The Body

The actions are not a bar. They sit at the bottom right, inside the same surface, one body gap
under the last piece. They have no separator and no ground of their own.

- **The primary action is rightmost.** The other actions sit to its left, with the dismissing one
  next to it ("Cancel · Go").
- **One primary per box.** Exactly one action carries `.Default` and takes the primary form
  (Voltage on Encre, ink on Papier). The others are secondary. A destructive answer takes the
  destructive form, and its wording says what it destroys.
- **Two actions are separated by `dialog_BtnPadding` and by nothing else.**
- **Every action is at least `btnPush_Width` wide and widens to its caption**
  (`PushButton.fitWidthToLabel`). A translation is longer than the English.
- **Captions are commands.** They follow the command capitalization; an ellipsis means the action
  asks for more before acting.

### The bottom-left slot

The bottom left is empty, or it holds one quiet control that belongs with the actions without
being one of them (`Dialog.setLeadingControl`). In the file box it holds the type filter, the
folder that will be chosen, or the count of what is chosen. A box never prints an `Esc` hint
there: the Cancel or Close button already says the box can be left. Key hints belong to surfaces
with no button to leave by, such as the lens.

## Forms Put Labels Above Fields

A form stacks each label **above** its field, 12.5 in soft ink, with a faint help line under the
field when one is needed. A label beside a field would split the box into two columns sized by
the longest label in the longest language. An option that carries its own wording (a check box)
has no label above it; see
[Let An Option Carry Its Own Wording](../build-swag-standard-apps/SKILL.md#let-an-option-carry-its-own-wording).

A form that an application needs is a `FormDlg`, not controls placed on a bare `Dialog` at
hand-written coordinates.

## The Predefined Boxes

| Box | Composition |
| --- | --- |
| Message, question (`MessageDlg`) | Title, body sentence, actions |
| Error (`MessageDlg.error`) | Critical dot and title, sentence, mono faint detail line, one Close |
| Prompt (`EditDlg.createSingleLine`) | Title, the field, faint help line, Cancel · primary |
| Form (`FormDlg`) | Title, labels above fields, help, Cancel · primary |
| File (`FileDlg`, `FileDlgMode`) | Title, places as text tabs, a path field that filters, rows, the bottom-left slot, Cancel · primary |
| About (`AboutDlg.createApplication`) | Tile, name, mono line of version and date under it, capability line, links, one Close |

- **The file box** keeps places, field and rows on the dialog surface inside the same inset, so
  they share one left edge. Its rows show the name, then date and size in faint mono, with the
  chosen row on the Arc selection ground. Each mode (`SelectFolder`, `CreateFile`, `SelectFiles`)
  and its two questions (`FileDlg.askNewFolderName`, `FileDlg.askReplace`) follow the charter's
  *The file box, in every mode*. A list never brings a panel with its own ground into a box: it
  would read as a card adrift in a margin.
- **About** has no title line, because the name beside the tile names the box. The tile is the
  two-colour application tile of the taskbar. Links are in Arc.

## The Body Owns One Inset, Once

`Dialog` is the only place the outer inset is expressed. `Dialog.createContentView` returns the
body between the title and the actions. A dialog, predefined or from an application, puts its
content there and sets no padding on it. It only states the spacing *between its own pieces*,
which is one gap, `dialog_BtnPadding * 2`.

## A Box Is As Tall As What It Holds

`Dialog.fitHeightToContent` takes the content height and adds the shared layers: the body inset,
the title, the actions row, the border and the shadow. Pass it what the content measured, never
a number. Measure with the window's own measurement (`Wnd.measure`, `IWnd.measureContent`), not
with a second copy of the layout.

- **A floor.** Every box opens at least `MinMessageWidth` wide, so a question and a prompt read
  as the same object.
- **A measure.** A message wraps at `MaxMessageWidth`. A run that wrapping cannot break, such as
  a path, is cut with an ellipsis instead of widening the box.
- **Commit one axis, then measure the other.** A window is placed on whole physical pixels, so a
  box fitted to a fractional extent comes back a little smaller and clips the text it was fitted
  to. Round out with `Dialog.physicalRoom`, set the width first, then ask the content how tall it
  is at the width it actually got.

## One Column, One Left Edge

Everything in the column shares one left edge and one right edge: the title, the body, the
fields, a list's rows, and the right edge of the primary action. A composite made of parts gives
them **one** inset, not one each. Inside a stack,
[`StackLayoutCtrl`](../../../bin/std/modules/gui/src/controls/composite/stacklayoutctrl.swg)
centres along the axis it is named for and leaves the other axis alone. A heading and a paragraph
stacked with `VerticalCenter` are centred as a group and both start on the left edge.

## Verify

1. `tools/std.bat dm test gui --test-file dialogs.charter.test.swg --test-file dialogs.layout.test.swg`,
   plus the test file of the dialog whose behaviour changed.
2. Review the `dialogs.*` goldens in `bin/std/modules/gui/src/tests/goldens/`, **in Encre and in
   Papier, each as a whole screen against its charter picture**, not only the diff. Check: no
   band, no cross, the title on the first line, the primary rightmost, the bottom-left slot empty
   or holding its one quiet control, and one left edge. A golden that changed in a part you did
   not touch is a finding. Promote each reviewed `.actual.png` on its own by moving it over its
   golden. Never run `tools/goldens.bat accept`, which promotes everything on disk.
3. `tools/examples.bat run gui9`, the dialogs instrument. It opens every predefined box,
   every mode of the file box and its two questions, and the file browser composite. **Look at
   each one.** An assertion cannot see an action row wider than its content, or two left edges
   that nearly agree.
4. Look at a box holding two sentences, not only one holding four words. Look at it in French as
   well as English, and at a display scale other than 100 %.

Use [validate-swag-changes](../validate-swag-changes/SKILL.md) for any further coverage.
