#global public
using Core, Pixel

// The property grid's built-in context-menu commands, exposed through the shared gui action
// system (IActionUI) rather than a hardcoded addItem+doModal+switch(result). Registered on every
// Properties control in create(); the context menu (properties.menu.swg) just declares item ids,
// and doModal dispatches update()/execute() here. The target row is read from Properties.menuItem,
// so the very same commands could also be driven by a toolbar button or a keyboard shortcut
// (same WndId).
struct ActionProperties {}

impl ActionProperties
{
    newCmdId("Copy")
    newCmdId("Paste")
    newCmdId("ResetDefault")
    newCmdId("MoveUp")
    newCmdId("MoveDown")
    newCmdId("Remove")
    newCmdId("RemoveAll")
}

impl IActionUI for ActionProperties
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case Copy, Paste, ResetDefault, MoveUp, MoveDown, Remove, RemoveAll:
            return true
        }

        return false
    }

    // Provide each item's label, icon and enabled state from the current target row. This is the
    // logic that used to live inline in popupMenu next to each addItem.
    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let prop = cast(*Properties) notnull cxt.wnd
        let item = prop.menuItem
        if !item do
            return false

        let theme = prop.getTheme()
        let arr   = prop.menuArrayContext()

        switch cxt.id
        {
        case Copy:
            evt.setFlags |= .Name | .Icon
            evt.name     = "Copy"
            evt.icon     = theme.getIcon24(.Copy)

        case Paste:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.name     = "Paste"
            evt.icon     = theme.getIcon24(.Paste)
            evt.disabled = !prop.canChangeItem(notnull item) or !Clipboard.hasTypedValue(notnull item.type)

        case ResetDefault:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.name     = "Reset to default"
            evt.icon     = theme.getIcon24(.Undo)
            evt.disabled = !item.isModified

        case MoveUp:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.name     = "Move Up"
            evt.icon     = theme.getIcon24(.SortArrowUp)
            evt.disabled = !arr.arrElem or !prop.canChangeItem(notnull arr.arrItem) or prop.arrayElementIndex(notnull arr.arrElem) == 0

        case MoveDown:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.name     = "Move Down"
            evt.icon     = theme.getIcon24(.SortArrowDown)
            var atEnd = true
            if arr.arrElem
            {
                let info = prop.arrayElementInfo(notnull arr.arrItem)
                atEnd = prop.arrayElementIndex(arr.arrElem) + 1 >= info.count
            }
            evt.disabled = !arr.arrElem or !prop.canChangeItem(notnull arr.arrItem) or atEnd

        case Remove:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.name     = "Remove"
            evt.icon     = theme.getIcon24(.Remove)
            evt.disabled = !arr.arrElem or !prop.canChangeItem(notnull arr.arrItem)

        case RemoveAll:
            evt.setFlags |= .Name | .Icon | .Disabled
            evt.name     = "Remove All"
            evt.icon     = theme.getIcon24(.RemoveAll)
            var empty = true
            if arr.arrItem
            {
                let arrData = cast(#null *Array'u8) arr.arrItem.data
                empty = arrData.isEmpty()
            }
            evt.disabled = !arr.arrItem or !prop.canChangeItem(arr.arrItem) or empty
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let prop = cast(*Properties) notnull cxt.wnd
        let item = prop.menuItem
        if !item do
            return false

        let arr = prop.menuArrayContext()

        switch cxt.id
        {
        case Copy:
            Clipboard.addTypedValue(notnull item.data, notnull item.type)

        case Paste:
            if Clipboard.getTypedValue(notnull item.data, notnull item.type)
            {
                prop.refreshItem(item)
                prop.hasChanged(item)
            }

        case ResetDefault:
            prop.resetItemDefault(item)

        case MoveUp:
            if arr.arrElem do
                prop.moveArrayValue(arr.arrElem, -1)

        case MoveDown:
            if arr.arrElem do
                prop.moveArrayValue(arr.arrElem, 1)

        case Remove:
            if !arr.arrElem do
                break
            if MessageDlg.confirm(notnull prop.wnd.surface, "This will remove the element") != Dialog.BtnYes do
                break
            prop.removeArrayValue(arr.arrElem)

        case RemoveAll:
            if !arr.arrItem do
                break
            if MessageDlg.confirm(notnull prop.wnd.surface, "This will remove all elements") != Dialog.BtnYes do
                break
            prop.clearArray(arr.arrItem)
        }

        return true
    }
}
