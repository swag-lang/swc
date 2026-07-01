#global public
using Core, Pixel

// Right-click context menu of the property control. The menu only declares which command ids are
// relevant for the clicked row; label/icon/enabled state and execution go through the shared gui
// action system (IActionUI) via ActionProperties (actionproperties.swg). Custom items contributed
// by IPropertyNotify.fillPopupMenu are dispatched back through Properties.onCommandEvent (in
// properties.swg) -> onPopupCommand.
moduleprivate impl Properties
{
    // Resolve, for the current context-menu row (.menuItem), the enclosing array item and the
    // clicked element row (either may be null). Right-clicking an element's field still targets
    // the element, via resolveArrayElement walking ancestors.
    mtd menuArrayContext()->{ arrItem: #null *PropertiesItem, arrElem: #null *PropertiesItem }
    {
        var result: retval
        if !.menuItem do
            return result

        result.arrElem = .resolveArrayElement(.menuItem)
        if .isArrayItem(.menuItem) do
            result.arrItem = .menuItem
        elif result.arrElem do
            result.arrItem = result.arrElem.parent

        return result
    }

    mtd popupMenu(item: *PropertiesItem, pt: Math.Point)
    {
        ToolTip.hide(item.line)

        let menu = MenuCtrl.createPopup(me)

        // Custom items first, contributed by the notify interface(s) along the parent chain.
        var scan = item
        while scan
        {
            if scan.ntfyItf do
                scan.ntfyItf.fillPopupMenu(me, item, menu)
            scan = scan.parent
        }

        // The row the commands operate on. Set before building/showing so ActionProperties.update
        // can compute each item's label/icon/enabled state, and before doModal since the command
        // is dispatched asynchronously afterwards.
        .menuItem = item

        // Built-in items: we only declare WHICH commands are relevant for this row by id. Their
        // label, icon and enabled state come from ActionProperties.update, and choosing one runs
        // ActionProperties.execute via the shared action system — no inline state, no result switch.
        let arr = .menuArrayContext()

        if item.data and item.type
        {
            menu.addSeparator()
            menu.addItem(ActionProperties.Copy)
            menu.addItem(ActionProperties.Paste)
        }

        if arr.arrItem
        {
            if arr.arrElem
            {
                menu.addSeparator()
                menu.addItem(ActionProperties.MoveUp)
                menu.addItem(ActionProperties.MoveDown)
            }

            if Reflection.isStructArray(arr.arrItem.type)
            {
                menu.addSeparator()
                if arr.arrElem do
                    menu.addItem(ActionProperties.Remove)
                menu.addItem(ActionProperties.RemoveAll)
            }
        }

        if !menu.items.count
        {
            menu.destroy()
            return
        }

        .editPopup = menu
        discard menu.doModal(pt)
        .editPopup = null
    }
}
