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

Call [[Gui.Wnd.destroy]] from handlers. Destruction is deferred until dispatch is
safe; do not retain control pointers after their destroy event.
