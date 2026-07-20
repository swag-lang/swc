#global public
using Core

struct WrapLayoutCtrl
{
    using wnd:        Wnd

    spacing:          f32 = 5
    wrapWidth:        f32 = 64
    wrapHeight:       f32 = 64
    resultHeight:     f32
}

impl IWnd for WrapLayoutCtrl
{
    mtd impl onResizeEvent(evt: #nonull *ResizeEvent)
    {
        if !.childs.count
        {
            .wnd.IWnd.onResizeEvent(evt)
            return
        }

        let client = .getClientRectPadding()

        var x = .padding.x
        var y = .padding.y
        for c in .childs
        {
            if c.wndFlags & .Hidden do
                continue

            let margin = c.getLayoutMargin()
            let hint = c.measure({client.width, client.height})
            var width = .wrapWidth
            var height = .wrapHeight
            if hint.preferred.x > 0 do
                width = hint.preferred.x
            if hint.preferred.y > 0 do
                height = hint.preferred.y

            let outerWidth = width + margin.x + margin.z
            if x != .padding.x and x + outerWidth > client.right()
            {
                x = .padding.x
                y += height + margin.y + margin.w + .spacing
            }

            .resultHeight = y + height + margin.y + margin.w
            var rect = Math.Rectangle{x + margin.x, y + margin.y, width, height}
            c.arrange(rect)
            x += outerWidth + .spacing
        }

        .wnd.IWnd.onResizeEvent(evt)
    }
}

impl WrapLayoutCtrl
{
    // Create a layout control
    func create(parent: #nonull *Wnd, position: Math.Rectangle = {})->#nonull *WrapLayoutCtrl
    {
        let res = Wnd.create'WrapLayoutCtrl(parent, position)
        return res
    }

    // Recompute layout of all childs
    mtd computeLayout()
    {
        .sendResizeEvent()
    }
}
