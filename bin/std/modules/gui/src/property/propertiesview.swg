using Core, Pixel

#[Swag.Opaque]
public struct PropertiesView
{
    using stackWnd:     StackLayoutCtrl
    ed:                 *Properties
}

impl IWnd for PropertiesView
{
    // The edView owns the keyboard focus while navigating the grid; forward keys
    // to the owning Properties so it can move the selection and start edition.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if .ed do
            .ed.navKeyEvent(evt)
        else do
            evt.accepted = false
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .stackWnd.IWnd.onResizeEvent(evt)
        if !.ed or !.ed.items.count do
            return

        .ed.refreshGridColumnLayout()

        // List mode: confine every row to the edit column (edit size + margins), left-aligned. The
        // editors already cap there; capping the row makes the name and description wrap to the
        // same width and the trailing revert arrow line up with it, so the whole row is coherent.
        if !.ed.isGridLike()
        {
            let cw = cast(f32) .ed.sizeEditValue + .ed.leftMargin + .ed.rightMargin
            foreach item in .ed.items do
                item.line.maxSize.x = cw
        }

        .computeLayout()

        var lastItem: *PropertiesItem
        foreach item in .ed.items
        {
            if item.label do
                item.label.autoHeight()
            if item.labelDesc do
                item.labelDesc.autoHeight()
            item.sigResize.call(item)
            item.line.applyLayout()

            // Line the list-mode revert arrow up with the right edge of the edit column now that
            // the value widgets are positioned (grid docks it, so this is a no-op there).
            .ed.positionListRevert(item)

            // The validation bar is sized to the editor column (and, in grid mode, grows the
            // row) only once the value widgets are positioned, so do it after the first pass
            // and lay the row out again when it changed the sizing.
            if item.validationLabel and .ed.syncValidationBar(item) do
                item.line.applyLayout()

            item.line.sendResizeEvent()
            if item.line.isVisible() do
                lastItem = item
        }

        .computeLayout()

        // Vertical size is the bottom position of the last line
        if lastItem do
            .ed.scrollWnd.setScrollSize(0, lastItem.line.position.bottom() + 10)
        else do
            .ed.scrollWnd.setScrollSize(0, 0)
    }
}
