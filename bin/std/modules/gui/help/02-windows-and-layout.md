# Windows and layout

[[Gui.Wnd]] is the common base of controls. A window belongs to a
[[Gui.Surface]], can own child windows, and stores its position in its parent's
local coordinate system.

Create concrete controls with their `create` function. The generic
[[Gui.Wnd.create]] helper is useful when defining a custom control.

## Choose a layout mechanism

| Need | API |
|---|---|
| Attach a child to one edge | [[Gui.DockStyle]] |
| Preserve distances while the parent resizes | [[Gui.AnchorStyle]] |
| Express content, fill, and expansion preferences | [[Gui.LayoutSpec]] |
| Place rows, columns, stacks, or split regions | Layout controls |
| Perform one-off absolute placement | [[Gui.Wnd.setPosition]] |

Margins occupy space outside a control; padding reduces its client content area.
Call [[Gui.Wnd.invalidateLayout]] after changing a value that affects measurement.
The framework then measures and arranges the affected tree.

Use coordinate conversion methods on [[Gui.Wnd]] when crossing local, surface,
and screen spaces. Keep hit testing and painting in the coordinate system named
by the event or drawing API.
