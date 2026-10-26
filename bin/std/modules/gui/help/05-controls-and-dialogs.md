# Controls and dialogs

GUI supplies primitive controls, composite controls, and modal dialogs. Start
with the narrowest control that represents the user's intent:

| Need | Control |
|---|---|
| Trigger a command | [[Gui.PushButton]] or [[Gui.Button]] |
| Display text or an icon | [[Gui.Label]] |
| Edit a short value | [[Gui.EditBox]] |
| Edit structured text | [[Gui.RichEditCtrl]] |
| Present rows or hierarchy | [[Gui.ListCtrl]] or tree controls |
| Scroll arbitrary content | [[Gui.ScrollWnd]] |
| Present commands | [[Gui.MenuCtrl]] |
| Group settings behind one button | [[Gui.OptionSheet.View]] |
| Edit reflected properties | [[Gui.PropertiesCtrl]] |

Controls expose signals for local reactions and command IDs for application-wide
actions. Prefer command IDs when the same operation appears in menus, toolbars,
shortcuts, and context menus.

An option sheet replaces a row of drop-down buttons. Its first page names each
setting with the value in force, and a row slides the page of its choices in;
the header, Left, Backspace or Escape slide back. Pages are described by
builder callbacks that read the current state, so a value the reader changed is
already right on the page they return to:

```swag
let sheet = OptionSheet.View.create(button, func|player|(page)
{
    page.addLink("Speed", player.rateText(), func|player|(rates)
    {
        for rate in [0.5, 1.0, 2.0] do
            rates.addChoice(Format.toString("%x", rate), rate == player.rate, func|player, rate|() { player.rate = rate })
    })

    page.addToggle("Loop", player.loop, func|player|(on) { player.loop = on })
})

sheet.doModal(button, autoDestroy: true)
```

A sheet joins its button like a menu, or covers the bottom or the trailing
edge of the window over a veil ([[Gui.OptionSheet.Placement]]) for a touch
screen or a screen read from afar. Rows can also be bound to command IDs with
[[Gui.OptionSheet.Page.addCommand]].

Dialogs own a temporary surface and run a modal loop while keeping the
application responsive. [[Gui.MessageDlg]], [[Gui.FileDlg]], and [[Gui.EditDlg]]
cover common interactions; derive from [[Gui.Dialog]] when a workflow needs a
custom arrangement or validation.
