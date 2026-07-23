using Core, Pixel

#[Swag.Opaque]
public struct PropertiesView
{
    using stackWnd:     StackLayoutCtrl
    ed:                 #late *Properties
}

impl IWnd for PropertiesView
{
    // The edView owns the keyboard focus while navigating the grid; forward keys
    // to the owning Properties so it can move the selection and start edition.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if @isset(.ed) do
            .ed.navKeyEvent(evt)
        else do
            evt.accepted = false
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .stackWnd.IWnd.onResizeEvent(evt)
        if !@isset(.ed) or !.ed.items.count do
            return

        .ed.refreshGridColumnLayout()

        // List mode: every row owns the complete useful width (selection/hot/hit-test), and
        // the name/description labels re-wrap over the full content width. The value editors
        // keep their own maxSize cap, so they don't stretch with the row.
        if !.ed.isGridLike()
        {
            let cw       = .ed.listUsefulWidth()
            let contentW = .ed.listContentWidthFromUseful(cw)
            for item in .ed.items
            {
                item.line.maxSize.x = cw
                if @isset(item.label) do
                    item.label.position.width = contentW
                if @isset(item.labelDesc) do
                    item.labelDesc.position.width = contentW
            }
        }

        .computeLayout()

        var lastItem: #null *PropertiesItem
        for item in .ed.items
        {
            if @isset(item.label) do
                item.label.autoHeight()
            if @isset(item.labelDesc) do
                item.labelDesc.autoHeight()
            item.sigResize.call(item)
            item.line.applyLayout()

            // Line list-mode row action buttons up with the right edge of the value column
            // now that the row label has its final size (grid docks them, so this is a no-op).
            if @isset(item.arrayAddButton) do
                .ed.positionListActionButton(notnull item, item.arrayAddButton)

            // The validation bar is sized to the editor column (and, in grid mode, grows the
            // row) only once the value widgets are positioned, so do it after the first pass
            // and lay the row out again when it changed the sizing.
            if @isset(item.validationLabel) and .ed.syncValidationBar(notnull item) do
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
