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

        // List mode: every row owns the complete useful width (selection/hot/hit-test). Children
        // add the internal content margins, so labels, editors, validation bars and action buttons
        // all derive from the same rectangle.
        if !.ed.isGridLike()
        {
            let cw = .ed.listUsefulWidth()
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

            // Line list-mode row action buttons up with the right edge of the selected useful
            // area now that the row label has its final size (grid docks them, so this is a no-op).
            .ed.positionListRevert(item)
            .ed.positionListActionButton(item, item.arrayAddButton)

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
