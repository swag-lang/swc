using Core, Pixel

// Hosts layout, painting, and keyboard navigation for property rows.
#[Swag.Opaque]
#[Swag.NoDoc]
public struct PropertiesView
{
    public
    {
        using stackWnd: StackLayoutCtrl     // Embedded stack wnd state.
    }

    // The grid this view paints for. 'Properties' establishes it when it builds the view.
    late ed: *Properties
}

internal impl IWnd for PropertiesView
{
    // The edView owns the keyboard focus while navigating the grid; forward keys
    // to the owning Properties so it can move the selection and start edition.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if .ed != null do
            .ed.navKeyEvent(evt)
        else do
            evt.accepted = false
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .stackWnd.IWnd.onResizeEvent(evt)
        if !(.ed != null) or !.ed.items.count do
            return

        .ed.refreshGridColumnLayout()

        // List mode: every row owns the complete useful width (selection/hot/hit-test), and
        // the name/description labels re-wrap over the full content width. The value editors
        // keep their own maxSize cap, so they don't stretch with the row.
        if !.ed.isGridLike()
        {
            let cw       = .ed.listUsefulWidth()
            let contentW = .ed.listContentWidthFromUseful(cw)
            for itemIt in .ed.items
            {
                let item = itemIt!
                item.line.maxSize.x = cw
                if item.label != null do
                    item.label.position.width = contentW
                if item.labelDesc != null do
                    item.labelDesc.position.width = contentW
            }
        }

        .computeLayout()

        var lastItem: *PropertiesItem?
        for itemIt in .ed.items
        {
            let item = itemIt!
            if item.label != null do
                item.label.updateAutomaticHeight()
            if item.labelDesc != null do
                item.labelDesc.updateAutomaticHeight()
            item.sigResize.call(item)
            item.line.applyLayout()

            // Line list-mode row action buttons up with the right edge of the value column
            // now that the row label has its final size (grid docks them, so this is a no-op).
            if item.arrayAddButton != null do
                .ed.positionListActionButton(item!, item.arrayAddButton)

            // The validation bar is sized to the editor column (and, in grid mode, grows the
            // row) only once the value widgets are positioned, so do it after the first pass
            // and lay the row out again when it changed the sizing.
            if (item.validationLabel != null) and .ed.syncValidationBar(item!) do
                item.line.applyLayout()

            item.line.sendResizeEvent()
            if item.line.isVisible() do
                lastItem = item
        }

        .computeLayout()

        // Vertical size is the bottom position of the last line
        if lastItem do
            .ed.scrollWnd.setScrollSize(0, lastItem!.line.position.bottom() + 10)
        else do
            .ed.scrollWnd.setScrollSize(0, 0)
    }
}
