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
        .computeLayout()

        var lastItem: *PropertiesItem
        foreach item in .ed.items
        {
            if item.label do
                item.label.autoHeight()
            if item.labelDesc do
                item.labelDesc.autoHeight()
            if item.validationLabel do
                item.validationLabel.autoHeight()
            item.sigResize.call(item)
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
