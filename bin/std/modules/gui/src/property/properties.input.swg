#global public
using Core, Pixel

// Input handling for the property control: hit-testing, the container-level child-event hook
// (mouse wheel routing, column resize, hover/tooltip, keyboard-nav interception), and the
// per-row event handler that opens the context menu and drives the row background paint.
// Keyboard navigation/edition itself lives in properties.keyboard.swg; the context menu in
// properties.menu.swg; the row painting in properties.paint.swg.
internal impl Properties
{
    mtd hitTest(ptLoc: Math.Point)->#null *PropertiesItem
    {
        let pt = ptLoc + .scrollWnd.getScrollPos()
        foreach item in .items
        {
            if !item.line.isVisible() do
                continue
            var r = item.line.position
            r.inflate(item.extendFocus)
            if r.contains(pt) do
                return item
        }

        return null
    }

    func onHookChildEvent(wnd: *Wnd, evt: IEvent)->bool
    {
        let prop = cast(*Properties) wnd
        if prop.editPopup
        {
            // While an editor popup (e.g. the color picker) is open the popup is anchored
            // to a fixed surface position, so the list must not scroll out from under it.
            // Swallow only wheel events aimed at the grid; let everything else through so
            // the popup can still close on an outside click and the trigger button's hover
            // state can clear normally. Wheel events inside the popup are left alone so it
            // can scroll its own content.
            if let mouseEvt = evt as MouseEvent where mouseEvt.kind == .MouseWheel
            {
                let target = mouseEvt.target
                if !(target and (target == prop.editPopup or prop.editPopup.isParentOf(target))) do
                    return true
            }
            return false
        }

        // Mouse wheel anywhere over the list scrolls it, even when the cursor is over an
        // editor (combobox/editbox/slider): those pass the wheel on, but their inner widgets
        // would otherwise swallow the bubble before it reaches the scroll view.
        if let mouseEvt = evt as MouseEvent where mouseEvt.kind == .MouseWheel
        {
            if prop.scrollWnd and prop.edView and mouseEvt.target and prop.edView.isParentOf(mouseEvt.target)
            {
                let sp = prop.scrollWnd.getScrollPos()
                prop.scrollWnd.setScrollPos(sp.x, sp.y - mouseEvt.move.y * prop.scrollWnd.scrollIncrementV)
                return true
            }
        }

        switch evt
        {
        case FocusEvent as focusEvt where focusEvt.kind == .CanSetFocus:
            if prop.cursorSet do
                focusEvt.canChangeFocus = false

        // While a row editor has the focus, intercept the navigation/mode keys
        // before the editor sees them so the grid is always keyboard-drivable.
        case KeyEvent as keyEvt where keyEvt.kind == .KeyPressed:
            if prop.editKeyEvent(keyEvt) do
                return true

        case MouseEvent as mouseEvt where mouseEvt.kind == .MousePressed:
            let pt = prop.surfaceToLocal(mouseEvt.surfacePos)

            prop.selItem = prop.hitTest(pt)
            wnd.invalidate()

            if mouseEvt.button != .Left do
                break

            // On column bar
            if prop.cursorSet
            {
                prop.resizingColumn = true
                return true
            }

            // Toggle/Expand
            if prop.isGridLike() and
               prop.selItem and
               prop.selItem.numChilds and
               pt.x < cast(f32) prop.leftMargin + prop.itemIndent(prop.selItem)
            {
                prop.selItem.flags.toggle(.Expanded)
                prop.updateStates()
            }

            // Clicking a row (but not its editor) puts the keyboard focus on the
            // grid in navigation mode, so the arrows work right after a click.
            if !prop.isEditorWnd(mouseEvt.target) do
                prop.focusNav()

        case MouseEvent as mouseEvt where mouseEvt.kind == .MouseDoubleClick and mouseEvt.button == .Left:

            // Toggle/Expand
            if prop.isGridLike() and
               prop.selItem and
               prop.selItem.numChilds
            {
                prop.selItem.flags.toggle(.Expanded)
                prop.updateStates()
            }

            // Toggle checkbox
            elif prop.selItem.checkBox
            {
                prop.selItem.checkBox.toggle()
            }

        case MouseEvent as mouseEvt where mouseEvt.kind == .MouseReleased:
            prop.resizingColumn = false

        case MouseEvent as mouseEvt where mouseEvt.kind == .MouseLeave:
            if prop.hotItem and prop.isGridLike() do
                ToolTip.hide(prop.hotItem.line)
            prop.hotItem = null

        case MouseEvent as mouseEvt where (mouseEvt.kind == .MouseMove or mouseEvt.kind == .MouseSetCursor):
            var pt = prop.surfaceToLocal(mouseEvt.surfacePos)

            // Resize of the grid column
            if prop.resizingColumn
            {
                prop.setColumnSize(cast() (pt.x - prop.gridMarginColumn * 0.5))
                return true
            }

            // Hot item
            let hit = prop.hitTest(pt)
            if hit != prop.hotItem
            {
                // Leaving a row: drop its tooltip so it does not linger over the next row.
                if prop.hotItem do
                    ToolTip.hide(prop.hotItem.line)
                prop.hotItem = hit

                if hit and hit.label and prop.isGridLike()
                {
                    pt = hit.label.surfaceToLocal(mouseEvt.surfacePos)
                    if hit.label.getClientRect().contains(pt) do
                        ToolTip.show(hit.line, mouseEvt.surfacePos, hit.description)
                }

                wnd.invalidate()
            }

            // On the column size bar
            if prop.isGridLike()
            {
                let x = prop.getColumnX()
                if pt.x >= x - 3 and pt.x <= x + 3 and hit and !hit.flags.has(.NoSeparator)
                {
                    prop.getApp().setFrameCursor(Cursor.from(.SizeWE))
                    prop.cursorSet = true
                    prop.invalidate()
                }
                elif prop.cursorSet
                {
                    prop.cursorSet = false
                    prop.invalidate()
                }
            }
        }

        return false
    }

    mtd onItemEvent(item: *PropertiesItem, wndItem: *Wnd, evt: IEvent)->bool
    {
        if wndItem.childs.isEmpty() do
            return false

        switch evt
        {
        case MouseEvent as mouseEvt where mouseEvt.kind == .MousePressed and mouseEvt.button == .Right:
            .popupMenu(item, mouseEvt.surfacePos)
            return true

        case NotifyEvent as ntfyEvt where ntfyEvt.ntfyKind == .ChildFocusChanged:
            wndItem.invalidate()
            return true

        case PaintEvent as paintEvt where paintEvt.kind == .PrePaint:
            .paintBackItem(paintEvt.bc.painter, item, wndItem)
        }

        return false
    }
}
