#global internal

using Core, Gui

// Keeps source actions together, wrapping them when the editor column becomes narrow.
struct SourceActions
{
    using wnd: Wnd
}

impl SourceActions
{
    mtd layoutFields(width: f32, place: bool)->Math.Point
    {
        let available = Math.max(width - .padding.x - .padding.z, 0.0)
        var x, y, rowHeight, usedWidth = 0.0'f32
        for child in .children
        {
            let size = child.measure({}).preferred
            if x > 0 and x + size.x > available
            {
                x         = 0
                y         += rowHeight + 8
                rowHeight = 0
            }

            if place do
                child.arrange({.padding.x + x, .padding.y + y, size.x, size.y})
            usedWidth = Math.max(usedWidth, x + size.x)
            x         += size.x + 8
            rowHeight = Math.max(rowHeight, size.y)
        }

        return {usedWidth + .padding.x + .padding.z, y + rowHeight + .padding.y + .padding.w}
    }
}

impl IWnd for SourceActions
{
    mtd impl measureContent(available: Math.Point)->Math.Point => .layoutFields(available.x, false)
    mtd impl onLayout() { discard .layoutFields(.clientRect().width, true) }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard .layoutFields(.clientRect().width, true)
        .wnd.IWnd.onResizeEvent(evt)
    }
}
