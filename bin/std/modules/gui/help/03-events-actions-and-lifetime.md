# Events, actions, and lifetime

GUI events implement [[Gui.IEvent]] and travel through a target window and its
owners. A control can implement the typed handlers from [[Gui.IWnd]], or install a
[[Gui.HookEvent]] for lightweight interception.

Common event families include:

| Event | Purpose |
|---|---|
| [[Gui.CreateEvent]] and [[Gui.DestroyEvent]] | Lifetime transitions |
| [[Gui.ResizeEvent]] | Geometry changes |
| [[Gui.PaintEvent]] | Drawing passes |
| [[Gui.KeyEvent]] and [[Gui.MouseEvent]] | User input |
| [[Gui.CommandEvent]] | Semantic commands |
| [[Gui.TimerEvent]] and [[Gui.FrameEvent]] | Scheduled and per-frame work |
| [[Gui.NotifyEvent]] | Control-specific notifications |

Events are synchronous unless posted with [[Gui.Application.postEvent]] or
[[Gui.Wnd.postEvent]]. A handler can mark an event unaccepted so it continues to
an owner.

Actions and command IDs decouple menus, buttons, and shortcuts from the code that
performs an operation. Compute command state in one place so every presentation
receives the same enabled, checked, name, and icon state.

## Reaching every control from the keyboard

A key goes to the focused window, then to its owners, and what none of them accepts
becomes navigation: a shortcut registered on the chain first, then Tab and Shift+Tab
through the traversal stops of the surface, then Enter and Escape for
[[Gui.Surface.defaultButton]] and [[Gui.Surface.cancelButton]]. A control that wants
one of those keys for itself only has to accept the event — that is how the rich
editor keeps its tabulation and the property grid keeps its row-to-row Tab.

Two declarations put a control in that order:

- [[Gui.Wnd.focusPolicy]] says whether a pointer press focuses the window and whether
  the traversal stops on it. A plain container declares nothing and is walked through.
- [[Gui.Wnd.focusDelegate]] points at the inner window that reads the keys, so a
  composite is one stop however many windows it is built from. Its parts declare
  [[Gui.FocusPolicy.Inner]] and disappear from the order.

The order itself is [[Gui.FocusOrder]]: depth first, and between siblings the order
their rectangles read, because a container does not place its children in the order it
created them. Nothing has to be numbered, and nothing has to be renumbered when a
control is inserted.

Call [[Gui.Wnd.setInitialFocus]] once a surface is built so it opens ready for the
keyboard; [[Gui.Wnd.hasVisibleFocus]] is true only while the keyboard is what moved the
focus, and [[Gui.Wnd.showsFocusRing]] is what a widget paints its focus ring from: it
adds the diagnostic that draws every ring of a surface at once.

Call [[Gui.Wnd.destroy]] from handlers. Destruction is deferred until dispatch is
safe; do not retain control pointers after their destroy event.

## Taking a drop from the desktop

Every surface is a drop target from the moment it is created, so a window takes drags
from Explorer and from other applications without asking for anything. A gesture
carrying a payload is delivered as a [[Gui.DragDropEvent]] to the window under the
pointer, and it bubbles to the ancestors exactly like a mouse event: a control that
ignores drops costs nothing, and a container can answer for the whole of its content.

Four phases bracket one gesture. `Enter` and `Leave` say when the pointer is over the
window, which is what a drop highlight is turned on and off by — `Leave` is delivered
when the drag is cancelled or dropped elsewhere too, so a highlight is never stuck on.
`Over` repeats while the pointer moves inside the window, and `Drop` is the release.

A target claims the gesture by setting [[Gui.DragDropEvent.effect]] to one member of
[[Gui.DragDropEvent.allowed]]; leaving it at `None` rejects the drop and lets the event
bubble further. [[Gui.pickDropEffect]] answers the desktop convention — `Control`
copies, `Shift` moves, both together link — restricted to what the source permits, so a
target that has no policy of its own is one line:

```swag
mtd impl onDragDropEvent(evt: *DragDropEvent)
{
    let path = evt.data.singleFile()
    if !path or !Path.hasExtension(path!, ".scrypt")
    {
        evt.accepted = false
        return
    }

    if evt.kind == .Drop do
        .openContainer(path)
    evt.effect = pickDropEffect(evt.allowed & (DropEffect.Copy | DropEffect.Link), evt.modifiers)
}
```

[[Gui.DragData]] is the payload, borrowed for the duration of one callback: a target
that wants to keep a path, a text or an image copies it out. It answers safely whatever
the drag carries — [[Gui.DragData.hasFiles]], [[Gui.DragData.singleFile]],
[[Gui.DragData.hasText]] and [[Gui.DragData.hasImage]] are all cheap, and only
[[Gui.DragData.image]] pays for a decode. That matters because a drag hovering a window
asks the same questions on every mouse move.

Two controls already answer for themselves. An [[Gui.EditBox]] takes dropped text at the
character under the pointer, and with [[Gui.EditBoxFlags.AcceptFileDrop]] a single
dropped file replaces its content with that path — which is what a field naming a
document wants, and what `Properties.FilePath` declares on a property-grid row.

A test drives the whole path with no desktop under it:
`Testing.HeadlessHost.dropFilesOnWnd` releases a payload on one control,
`Testing.HeadlessHost.dragFilesOver` moves a gesture across the tree, and
`Testing.HeadlessHost.cancelDrag` ends one the way Escape does.

## Dragging out of a window

[[Gui.Wnd.startDrag]] carries a payload to whatever the pointer is released on, and answers with
the single effect the target settled on. The same [[Gui.DragData]] is what a source fills:
[[Gui.DragData.addFile]], [[Gui.DragData.setText]] and [[Gui.DragData.setImage]] say what is on
offer, and offering several is the useful case rather than a redundant one — a folder takes the
file, a picture editor takes the bitmap, and each target picks what it understands.

```swag
var data: DragData
data.addFile(exportedPath)
try data.setImage(picture)
discard thumbnail.startDrag(&data, DropEffect.Copy)
```

A press only becomes a drag once the pointer has travelled far enough, which
[[Gui.Wnd.exceedsDragThreshold]] answers from the distance the desktop is configured with, so a
shaky hand on a click does not start dragging.

Two consequences of the desktop running the gesture are worth knowing before writing the handler.
The call does not return until the drop, and the window stops painting for that whole time — every
application that drags behaves this way. And the button that started the drag comes back up
*inside* that loop, so the control has to forget its own press before calling, rather than waiting
for a release event that will never arrive:

```swag
if evt.kind == .Move and .pressedItem != Swag.U64.Max
{
    if .exceedsDragThreshold(.pressOrigin, evt.surfacePos)
    {
        .pressedItem = Swag.U64.Max     // no release event follows the gesture
        .dragOutItem()
        return
    }
}
```
