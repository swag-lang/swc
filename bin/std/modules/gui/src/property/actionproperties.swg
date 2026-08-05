#global public

using Core, Pixel

// The property grid's built-in context-menu commands, exposed through the shared gui action
// system (IActionUI) rather than a hardcoded addItem+doModal+switch(result). Registered on every
// Properties control in create(); the context menu (properties.menu.swg) just declares item ids,
// and doModal dispatches update()/execute() here. The target row is read from Properties.menuItem,
// so the very same commands could also be driven by a toolbar button or a keyboard shortcut
// (same WndId).
internal struct ActionProperties {}

internal impl ActionProperties
{
    newCmdId("Copy")
    newCmdId("Paste")
    newCmdId("ResetDefault")
    newCmdId("MoveUp")
    newCmdId("MoveDown")
    newCmdId("Remove")
    newCmdId("RemoveAll")
}

internal impl IActionUI for ActionProperties
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case ActionProperties.Copy, ActionProperties.Paste, ActionProperties.ResetDefault, ActionProperties.MoveUp, ActionProperties.MoveDown, ActionProperties.Remove, ActionProperties.RemoveAll: return true
        }

        return false
    }

    // Provide each item's label, icon and enabled state from the current target row. This is the
    // logic that used to live inline in popupMenu next to each addItem.
    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let prop = cast(*Properties) cxt.wnd!
        let item = prop.menuItem
        if !item do
            return false

        let theme = prop.theme()
        let arr   = prop.menuArrayContext()

        switch cxt.id
        {
        case ActionProperties.Copy:
            evt.updatedFields |= .Name | .Icon
            evt.name          = strings().prop_Copy
            evt.icon          = theme.icon(.Copy)

        case ActionProperties.Paste:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = strings().prop_Paste
            evt.icon          = theme.icon(.Paste)
            evt.disabled      = !prop.canChangeItem(item!) or !Clipboard.hasTypedValue(item.type!)

        case ActionProperties.ResetDefault:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = strings().prop_ResetDefault
            evt.icon          = theme.icon(.Undo)
            evt.disabled      = !item.isModified

        case ActionProperties.MoveUp:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = strings().prop_MoveUp
            evt.icon          = theme.icon(.SortArrowUp)
            evt.disabled      = !arr.arrElem or !prop.canChangeItem(arr.arrItem!) or prop.arrayElementIndex(arr.arrElem!) == 0

        case ActionProperties.MoveDown:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = strings().prop_MoveDown
            evt.icon          = theme.icon(.SortArrowDown)
            var atEnd = true
            if arr.arrElem
            {
                let info = prop.arrayElementInfo(arr.arrItem!)
                atEnd = prop.arrayElementIndex(arr.arrElem) + 1 >= info.count
            }

            evt.disabled = !arr.arrElem or !prop.canChangeItem(arr.arrItem!) or atEnd

        case ActionProperties.Remove:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = strings().prop_Remove
            evt.icon          = theme.icon(.Remove)
            evt.disabled      = !arr.arrElem or !prop.canChangeItem(arr.arrItem!)

        case ActionProperties.RemoveAll:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = strings().prop_RemoveAll
            evt.icon          = theme.icon(.RemoveAll)
            var empty = true
            if arr.arrItem
            {
                let arrData = cast(*Array'u8) arr.arrItem.data!
                empty = arrData.isEmpty()
            }

            evt.disabled = !arr.arrItem or !prop.canChangeItem(arr.arrItem) or empty
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let prop = cast(*Properties) cxt.wnd!
        let item = prop.menuItem
        if !item do
            return false

        let arr = prop.menuArrayContext()

        switch cxt.id
        {
        case ActionProperties.Copy:
            Clipboard.addTypedValue(item.data!, item.type!)

        case ActionProperties.Paste:
            if Clipboard.getTypedValue(item.data!, item.type!)
            {
                prop.refreshItem(item)
                prop.commitItemChange(item)
            }

        case ActionProperties.ResetDefault:
            prop.resetItemDefault(item)

        case ActionProperties.MoveUp:
            if arr.arrElem do
                prop.moveArrayValue(arr.arrElem, -1)

        case ActionProperties.MoveDown:
            if arr.arrElem do
                prop.moveArrayValue(arr.arrElem, 1)

        case ActionProperties.Remove:
            if !arr.arrElem do
                break
            if MessageDlg.confirm(prop.wnd.surface!, strings().prop_ConfirmRemove) != Dialog.BtnYes do
                break
            prop.removeArrayValue(arr.arrElem)

        case ActionProperties.RemoveAll:
            if !arr.arrItem do
                break
            if MessageDlg.confirm(prop.wnd.surface!, strings().prop_ConfirmRemoveAll) != Dialog.BtnYes do
                break
            prop.clearArray(arr.arrItem)
        }

        return true
    }
}
