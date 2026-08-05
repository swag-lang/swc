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

## Let the content decide

An axis you leave unsized belongs to the content. [[Gui.Wnd.measure]] asks the
window through [[Gui.IWnd.measureContent]], and the answer becomes its preferred
size: a caption widens its button, a list of entries widens its combo box, a
wrapped paragraph reports the height it needs at the width it is offered, and a
band docked with no height is as tall as what it holds. An axis carrying a size
the caller stated keeps it, unmeasured.

```swag
// The height is a design decision; the width is the caption's business.
let action = PushButton.create(bar, "Create encrypted vault", {0, 0, 0, 36})
```

This is what keeps a surface correct when its text changes — a translation, a
document title, a user-supplied name. Implement `measureContent` on a custom
control that draws its own text or items; the default reports nothing, which
keeps the authored size on both axes.

Use coordinate conversion methods on [[Gui.Wnd]] when crossing local, surface,
and screen spaces. Keep hit testing and painting in the coordinate system named
by the event or drawing API.
