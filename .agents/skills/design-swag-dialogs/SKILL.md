---
name: design-swag-dialogs
description: Compose, review, or change a modal box — the predefined dialog family under bin/std/modules/gui/src/dialogs, a composite hosted inside one, or an application's own modal — to the Silence charter's floating sheet. Use whenever a dialog's width, height, inset, title, severity mark, field labels, actions, their order or wording, or the bottom-left slot changes.
---

# Design Swag Dialogs

A modal box is one composition, and the family is recognized before a word of it is read: **a
floating sheet** over a dimmed window, its title as the first line of the body, the content in one
column, and the actions at the bottom right of the same surface, the primary rightmost. What changes
between an error, a question, a prompt, a form, a file browser and an About box is the content.
Nothing else changes, and almost nothing below is a dialog's to choose.

The visual target is the Dialogs section of the Silence charter,
[backlog/design/README.md](../../../backlog/design/README.md#dialogs), and its two pictures,
[dialogs.ink](../../../backlog/design/imgs/dialogs.ink.png) and
[dialogs.paper](../../../backlog/design/imgs/dialogs.paper.png). Where a picture and a rule
disagree, the rule wins. [design-swag-themes](../design-swag-themes/SKILL.md) governs the colours,
the controls and the measures a dialog uses;
[build-swag-standard-apps](../build-swag-standard-apps/SKILL.md) governs the application surface a
box opens over and the wording of its commands. This governs the box.

Within the body, use the proximity, alignment, and visible-gap review in
[build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#make-space-describe-relationships).
The dialog metrics below own the body and the actions; do not replace them with application
spacing literals.

The measurable half is enforced:
[`dialogs.charter.test.swg`](../../../bin/std/modules/gui/src/tests/dialogs.charter.test.swg)
builds every predefined box and measures it, and
[`dialogs.layout.test.swg`](../../../bin/std/modules/gui/src/tests/dialogs.layout.test.swg)
pins what each one fits itself to. A number argued here without a line there is a number that
drifts back within a release.

## A Dialog Is A Floating Sheet

- **Surface, corner 12, the floating shadow, over a dimmed window.** It is the same object as the
  lens and the sheet: something that floats above the work for as long as it is needed. The dim
  says the window behind cannot be acted on; nothing else needs to.
- **No caption band and no close cross.** A band is chrome around a box that already has an
  outline, and it spent a line saying "this is a dialog" — which the dim and the shadow already
  say. The cross was a second way out beside Cancel, in a corner the eye does not visit when it
  reads a question. A box is dismissed by its own actions and by `Esc`.
- **Padding 28, gap 16.** One inset around the whole body, one gap between its pieces.
- **Body text 13.5/21 in soft.** The title is in text colour; what follows is quieter.

## Take Every Number From The Theme

A dialog never writes a spacing, a button size or a minimum width. All of them live in
[`ThemeMetrics`](../../../bin/std/modules/gui/src/paint/thememetrics.swg), so a theme moves the
whole family at once and no box can disagree with the box beside it.

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

`dialogs.charter.test.swg` asserts the four charter values (28, 16, 34, 440) where every box reads
them.

A literal in a dialog is a measurement no theme can answer for, exactly as a literal color is a
color no palette can answer for. Beyond the floor, a dialog authors no width and no height: it
sizes itself from its content.

## The Title Is The First Line Of The Body

Every box names itself, and the name is the first line of its body, set 17/650 in text colour. The
predefined helpers supply a default — `dlg_InfoTitle`, `dlg_ConfirmTitle`, `dlg_ErrorTitle` — and a
caller with something more specific to say passes it in `MessageDlgOptions.title`, or
`Dialog.setTitle` for a box it composes itself. Prefer the
specific one: the charter's boxes lead with what happened ("The file changed on disk.", "Cannot
open this file.") and leave the body to say what the reader can do about it.

- A title that **reports a situation** is a sentence: sentence case, closing full stop.
- A title that **names the command the box carries out** ("Go to Address", "Change Password",
  "Open File") repeats that command's label as the lens shows it, so it follows the command
  capitalization of [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#word-the-commands):
  title-style in English, the language's own convention in a translation.

Titles are keys in [`Strings`](../../../bin/std/modules/gui/src/localization.swg), and a key added
there without its line in `src/lang/<tag>/gui.tweak` ships half translated with nothing to report
it.

## Severity Is One Dot

A failure puts an **8 px critical dot** before the title (`Dialog.setTitle(title, failure: true)`,
`MessageDlgOptions.failure`), and the technical detail — an error code, the system's own report —
on a **mono faint line** under the sentence (`MessageDlgOptions.detail`; `MessageDlg.error` takes a
`Swag.SystemError`'s message there). That is the whole severity
vocabulary of a box: no icon tile, no coloured band, no three-colour status icon. The sentence says
what went wrong in the reader's language; the mono line is for whoever files the report, and a box
without a detail shows none. See *Tell A Reader What Went Wrong* in
[build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#tell-a-reader-what-went-wrong-not-how).

An information or a question needs no mark: the absence of the dot is the information.

## The Actions End The Body

The actions are not a bar. They sit at the bottom right **inside the same surface**, after the
last piece of the body, separated from it by the body gap — no separator, no band, no ground of
their own.

- **The primary action is rightmost.** The eye finishes a box at its bottom right, and that is
  where the answer it came to give belongs. Other actions sit to its left, the dismissing one
  nearest the primary ("Ignore · Reload", "Cancel · Go").
- **One primary per box.** Exactly one carries `.Default` and takes the primary form of
  [design-swag-themes](../design-swag-themes/SKILL.md#controls) — Voltage fill on Encre, ink fill
  on Papier. Every other action is secondary (line ring). A destructive answer is the destructive
  form, and its wording says what it destroys.
- **Two actions are separated by `dialog_BtnPadding`** and by nothing else.
- **Every action is at least `btnPush_Width` wide and widens to its caption**
  (`PushButton.fitWidthToLabel`) rather than clipping it. A translation is longer; a button that is
  right in English and cut in French was authored, not measured.
- **Captions are commands** and follow the command capitalization rule
  ([build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#word-the-commands)): "Save as
  Image…", "Open With…" in English; sentence case in French. An ellipsis means the action asks for
  more before acting.

### The bottom-left slot

The bottom left of the actions row is empty, or holds one quiet control that belongs to the
actions without being one of them, such as the file dialog's type filter (`▾`):
`Dialog.setLeadingControl`.

A box does not print the name of the Escape key. Escape cancelling a modal box is a desktop
convention, and the Cancel (or Close) button already says the box can be left without answering;
a faint `Esc` beside it repeats that and reads as a leftover. The key hint belongs to surfaces with
no button to leave by, such as the lens.

## Forms Put Labels Above Fields

A form in a dialog stacks each label **above** its field, 12.5 in soft, and a help line under the
field in faint when the field needs one. A label beside a field splits the box into two columns
whose widths are decided by the longest label in the longest language; above, every field takes
the full measure and the labels cost one line each. An option that carries its own wording (a
check box) takes no label above it — see *Let An Option Carry Its Own Wording* in
[build-swag-standard-apps](../build-swag-standard-apps/SKILL.md#let-an-option-carry-its-own-wording).

## The Predefined Boxes

| Box | Composition |
| --- | --- |
| Message, question (`MessageDlg`) | Title, body sentence, actions |
| Error | Critical dot and title, sentence, mono faint detail line, one Close |
| Prompt (`EditDlg.createSingleLine`) | Title, the field with its focus ring, help line in faint, Cancel · primary |
| Form (`FormDlg`) | Title, labels above fields, help, Cancel · Apply |
| File (`FileDlg`) | Title, places as text tabs, a path field that filters, rows, type filter bottom left, Cancel · Open |
| About (`AboutDlg.createApplication`) | Tile, name, version and date, capability line, links, copyright, one Close |

- **The file dialog** shows places (Desktop, Documents, drives…) as text tabs with the Arc
  underline; one path field that filters as the reader types, matched characters in the highlight
  colour; rows of 30–32 with the name, then date and size in mono faint, the chosen row on the Arc
  selection ground; and the type filter as a quiet `▾` at the bottom left. Places, field and rows
  sit on the dialog surface inside the same inset, so the title, the tabs, the field and the rows
  share one left edge. A list never brings a panel of its own into a box: a panel with its own
  ground inside a sheet reads as a card adrift in a margin.
- **About** shows the application tile (52, corner 12, the two-colour tile of the taskbar), the name
  21/800, version and date in mono beside it, the capability line in body text, then the links
  (in Arc) and the copyright, and one Close at the bottom right.

## The Body Owns One Inset, And Owns It Once

[`Dialog`](../../../bin/std/modules/gui/src/dialogs/dialog.swg) is the only place the outer inset
is expressed: its padding holds the inset and the room of the title, and the actions row keeps one
gap above it. [`Dialog.createContentView`](../../../bin/std/modules/gui/src/dialogs/dialog.swg)
gives the body between them; a dialog — predefined or an application's own — puts its content
there, sets no padding of its own on it, and states only the spacing *between its own pieces* — one
gap, `dialog_BtnPadding * 2`. A form an application asks for is a `FormDlg`, not controls laid on a
bare `Dialog` at authored coordinates.

## A Box Is As Tall As What It Holds

`Dialog.fitHeightToContent` takes the content height and adds the shared layers — body inset,
title, actions row, border, shadow. A dialog passes what its content measured and never a number:
a height authored by hand is right in the language it was tuned in and cuts the last paragraph off
in every other one, and it is stale the day a shared metric moves.

Measure with the window's own measurement (`Wnd.measure`, `IWnd.measureContent`), not with a
second copy of the layout written beside it. A duplicate is a copy that has to be kept in step
with the paint, and it never is: the one the message box carried measured without the label's own
string format and answered for a wrapping the label did not do.

## A Box Has A Floor And A Measure

- **A floor.** A box fitted to a short question and to nothing else comes out barely wider than
  its own actions, and reads as a pair of buttons with a title. Every box opens at no less than
  `MinMessageWidth`, so a question and a prompt are one object on screen.
- **A measure.** A message wraps at `MaxMessageWidth`. Text set wider than that is read by moving
  the head, and the box stops being a box.
- Between the two, the content decides, and the box hugs it. A run that wrapping cannot break — a
  path, a URL — is cut with an ellipsis at the measure instead of widening the box to its own
  length.

## Commit The Size Before Measuring What Goes In It

A window is placed on whole physical pixels and the tree inside it is laid out on whole logical
units. A box fitted to the exact fractional extent of its content therefore comes back a fraction
smaller than it asked for — and a fraction is enough: a message sized to its own longest line
wraps one line more than the box was made tall for, and the box clips the very text it was
fitted to. Every two-sentence error box did this.

Two rules close it, and both live in `Dialog`:

1. Round out to the grid. `Dialog.physicalRoom` gives whole logical units on whole physical
   pixels; a fitted box never hands `setPosition` a raw measurement.
2. **Commit one axis, then measure the other against what came back.** The message box sets its
   width first and asks the label how tall it is at the width it really got. Anything that fits
   itself to wrapped text follows the same order.

## One Column, One Left Edge

Everything stacked in one column shares one left edge and one right edge: the title, the body, the
fields, a list's rows, and the right edge of the primary action. A composite made of parts — tabs,
a field, a list, a hint — gives them **one** inset, not one each: given an inset apiece they line
up on none, and the difference between two paddings is exactly the kind of near-miss a reader sees
without being able to name.

The same rule holds inside a stack:
[`StackLayoutCtrl`](../../../bin/std/modules/gui/src/controls/composite/stacklayoutctrl.swg) centers the
axis it is named for and leaves the other alone. A heading and a paragraph stacked with
`VerticalCenter` are centered vertically **as a group** and both start on the stack's left edge —
centered individually, each hugs its own text and the box reads as set on nothing.

## Verify

1. `swc tools/std.swgs dm test gui --test-file dialogs.charter.test.swg --test-file dialogs.layout.test.swg`
   — the charter and layout tests. Add the exact dialog test file when its behavior changed.
2. The dialog goldens, **in Encre and in Papier**, against
   [dialogs.ink](../../../backlog/design/imgs/dialogs.ink.png) and
   [dialogs.paper](../../../backlog/design/imgs/dialogs.paper.png): no band, no cross, the title
   on the first line, the primary rightmost, the hint or the filter bottom left, one left edge.
3. `swc tools/examples.swgs run gui9` — the instrument. It opens every predefined box and the
   file browser composite beside them. **Look at each one**: an assertion cannot see an action row
   wider than its content, a hint where no dismissing action exists, or two left edges that nearly
   agree.
4. Look at a box holding two sentences, not only at one holding four words, in French as well as
   English, and at a display scale other than 100 percent. All three are where a fitted box fails,
   and none shows up in the case a change is usually tried on.

Use [validate-swag-changes](../validate-swag-changes/SKILL.md) for any additional configuration,
consumer, or golden coverage; do not run unrelated GUI tests.
