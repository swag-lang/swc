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
| Edit reflected properties | [[Gui.PropertiesCtrl]] |

Controls expose signals for local reactions and command IDs for application-wide
actions. Prefer command IDs when the same operation appears in menus, toolbars,
shortcuts, and context menus.

Dialogs own a temporary surface and run a modal loop while keeping the
application responsive. [[Gui.MessageDlg]], [[Gui.FileDlg]], and [[Gui.EditDlg]]
cover common interactions; derive from [[Gui.Dialog]] when a workflow needs a
custom arrangement or validation.
