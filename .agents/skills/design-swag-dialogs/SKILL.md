---
name: design-swag-dialogs
description: Compose, review, or change a modal box — the predefined dialog family under bin/std/modules/gui/src/dialogs, a composite hosted inside one, or an application's own modal. Use whenever a dialog's width, height, inset, alignment, action bar, button, or title changes.
---

# Design Swag Dialogs

A modal box is one composition, and the family is recognized before a word of it is read: a body
over a quiet action bar, one inset, one gap, one row of actions ending on one edge. What changes
between an error, a question, a prompt, a form and a file browser is the content. Nothing else
changes, and almost nothing below is a dialog's to choose.

[design-swag-identity](../design-swag-identity/SKILL.md) governs the cut, the palette and the
voice; [build-swag-standard-apps](../build-swag-standard-apps/SKILL.md) governs an application
surface. This governs the box that opens on top of one.

The measurable half is enforced:
[`dialogs.charter.test.swg`](../../../bin/std/modules/gui/src/tests/unittests/dialogs.charter.test.swg)
builds every predefined box and measures it, and
[`dialogs.layout.test.swg`](../../../bin/std/modules/gui/src/tests/unittests/dialogs.layout.test.swg)
pins what each one fits itself to. A number argued here without a line there is a number that
drifts back within a release.

## Take Every Number From The Theme

A dialog never writes a spacing, a button size or a bar height. All of them live in
[`ThemeMetrics`](../../../bin/std/modules/gui/src/paint/thememetrics.swg), so a theme moves the
whole family at once and no box can disagree with the box beside it.

| What | Where it comes from | Today |
| --- | --- | --- |
| Air a body keeps around loose content | `dialog_Padding` | 24 |
| Air above and below the actions, and between two of them | `dialog_BtnPadding` | 8 |
| Air between two pieces of one body | `dialog_BtnPadding * 2` | 16 |
| An action | `btnPush_Width` × `btnPush_Height` | 100 × 30 |
| The action bar | `btnPush_Height + 2 * dialog_BtnPadding` | 46 |
| Narrowest a message box opens | `MessageDlg.MinMessageWidth` | 450 |
| Widest a message runs before it wraps | `MessageDlg.MaxMessageWidth` | 512 |

A literal in a dialog is a measurement no theme can answer for, exactly as a literal color is a
color no palette can answer for.

## The Body Owns One Inset, And Owns It Once

[`Dialog.createContentView`](../../../bin/std/modules/gui/src/dialogs/dialog.swg) is the only
place the outer inset is expressed. A dialog sets no padding of its own on the body and states
only the spacing *between its own pieces* — one gap, `dialog_BtnPadding * 2`.

One case takes no inset at all. A body that is **one panel carrying its own ground and its own
edge paddings** — a file browser, a list, an editor — asks for `createContentView(inset: false)`.
Set inside the inset instead, the panel reads as a card adrift in a margin, and the box has to
grow by twice that inset to show the same rows. That is what made the file dialog look padded
out: the browser's own 15-unit edges sat inside another 24, and 48 units of each axis went to
nothing.

The inverse holds too: a panel that takes the full body must reach the frame on all four sides,
never on three.

## The Action Bar Is A Row, Not A Panel

- Its height is the button plus the air above and below it. Never author it.
- The row is trailing-aligned and ends on `dialog_Padding`, so the last action's right edge is
  the right edge of whatever the body holds. A bar inset differently from the body is the most
  visible misalignment a box can have, because the eye has two straight edges to compare.
- Two actions are separated by `dialog_BtnPadding` and by nothing else — no separator, no group.
- Every action is at least `btnPush_Width` × `btnPush_Height` and **widens to its caption**
  (`PushButton.fitWidthToLabel`) rather than clipping it. A translation is longer; a button that
  is right in English and cut in French was authored, not measured.
- **One dominant action per box.** Exactly one carries `.Default`; every other one is `.Normal`.
  A bar of filled buttons says nothing about what Enter decides.
- The confirming action comes first and the dismissing one last. `Dialog.addButton` is what puts
  the close cross on the caption, and only when a `BtnCancel` or `BtnNo` is there to mean the same
  thing: a box offering no way out other than answering it shows no cross.

## A Box Is As Tall As What It Holds

`Dialog.fitHeightToContent` takes the content height and adds the shared layers — body inset,
action bar, caption, border, shadow. A dialog passes what its content measured and never a
number: a height authored by hand is right in the language it was tuned in and cuts the last
paragraph off in every other one, and it is stale the day a shared metric moves.

Measure with the window's own measurement (`Wnd.measure`, `IWnd.measureContent`), not with a
second copy of the layout written beside it. A duplicate is a copy that has to be kept in step
with the paint, and it never is: the one the message box carried measured without the label's own
string format and answered for a wrapping the label did not do.

## A Box Has A Floor And A Measure

- **A floor.** A box fitted to a short question and to nothing else comes out barely wider than
  its own action bar, and reads as a pair of buttons with a caption. The message family opens at
  no less than `MinMessageWidth`, which is the width of the single-line prompt beside it, so a
  question and a prompt are one object on screen.
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

Everything stacked in one column shares one left edge and one right edge. A composite made of
bands — a navigation bar, a list, a status line, a form — gives them **one** inset, not one each:
given an inset apiece they line up on none, and the difference between two paddings is exactly
the kind of near-miss a reader sees without being able to name.

The same rule holds inside a stack:
[`StackLayoutCtrl`](../../../bin/std/modules/gui/src/composite/stacklayoutctrl.swg) centers the
axis it is named for and leaves the other alone. A heading and a paragraph stacked with
`VerticalCenter` are centered vertically **as a group** and both start on the stack's left edge —
centered individually, each hugs its own text and the box reads as set on nothing.

## Every Box Names Itself

The caption takes its band whether or not anything is written in it, so a box opened without a
title reads as one the application forgot to finish. The predefined helpers supply one —
`dlg_InfoTitle` for a message, `dlg_ConfirmTitle` for a question, `dlg_ErrorTitle` for a failure —
and a caller with something more specific to say passes it in `MessageDlgOptions.title`.

Titles are keys in [`Strings`](../../../bin/std/modules/gui/src/localization.swg), and a key added
there without its line in `src/lang/<tag>/gui.tweak` ships half translated with nothing to report
it.

## Verify

1. `swc tools/std.swgs dm test gui` — the charter and layout tests.
2. `swc tools/examples.swgs run gui9` — the instrument. It opens every predefined box and the
   file browser composite beside them. **Look at each one**: an assertion cannot see a caption
   band with nothing in it, a bar wider than its content, or two left edges that nearly agree.
3. Look at a box holding two sentences, not only at one holding four words, and at a display
   scale other than 100 percent. Both are where a fitted box fails, and neither shows up in the
   case a change is usually tried on.
