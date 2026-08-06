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
