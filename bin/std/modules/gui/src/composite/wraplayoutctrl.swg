#global public

using Core

// Flows visible children left to right and wraps them into additional rows.
struct WrapLayoutCtrl
{
    using wnd: Wnd     // Embedded wnd state.

    spacing:    f32 = 5      // Horizontal and vertical gap between items.
    itemWidth:  f32 = 64     // Fallback width when a child has no preferred width.
    itemHeight: f32 = 64     // Fallback height when a child has no preferred height.
    readonly contentHeight: f32     // Height occupied by the latest layout pass.
}

impl IWnd for WrapLayoutCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .contentHeight = 0
        if !.children.count
        {
            .wnd.IWnd.onResizeEvent(evt)
            return
        }

        let client = .paddedClientRect()

        var x         = client.x
        var y         = client.y
        var rowHeight = 0'f32
        for c in .children
        {
            if c.wndFlags & .Hidden do
                continue

            let margin = c.layoutMargin()
            let hint   = c.measure({client.width, client.height})
            var width  = .itemWidth
            var height = .itemHeight
            if hint.preferred.x > 0 do
                width = hint.preferred.x
            if hint.preferred.y > 0 do
                height = hint.preferred.y

            let outerWidth = width + margin.x + margin.z
            let outerHeight = height + margin.y + margin.w
            if x != client.x and x + outerWidth > client.right()
            {
                x = client.x
                y += rowHeight + .spacing
                rowHeight = 0
            }

            var rect = Math.Rectangle{x + margin.x, y + margin.y, width, height}
            c.arrange(rect)
            x += outerWidth + .spacing
            rowHeight = Math.max(rowHeight, outerHeight)
            .contentHeight = y + rowHeight + .padding.w
        }

        .wnd.IWnd.onResizeEvent(evt)
    }
}

impl WrapLayoutCtrl
{
    // Creates an empty wrapping layout.
    func create(parent: *Wnd, position: Math.Rectangle = {})->*WrapLayoutCtrl
    {
        let res = Wnd.create'WrapLayoutCtrl(parent, position)
        return res
    }

    // Recomputes the flow of all visible children.
    mtd computeLayout()
    {
        .sendResizeEvent()
    }
}
