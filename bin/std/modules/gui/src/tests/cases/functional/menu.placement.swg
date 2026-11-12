#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Window clearance wins over content alignment, while the opener keeps its exact position.
// The same placement contract holds for narrow icons, wide text and both opening directions.
#test
{
    for width in [44'f32, 120'f32, 220'f32]
    {
        for edge in [0, 1, 2]
        {
            for up in [false, true]
            {
                var host: Testing.HeadlessHost
                host.setup(540, 300, 1.5)
                let x      = edge == 0 ? 0'f32 : (edge == 1 ? 160'f32 : 540 - width)
                let button = IconButton.createQuiet(&host.root)
                if width > 44 do
                    button.setQuietText("Projects")
                else do
                    button.setIcon(host.theme.icon(.Folder, 16))
                button.setArrowPosition(up ? .RightUpward : .RightDownward)
                button.setPosition({x, up ? 258 : 6, width, 34})
                let original = button.surfaceRect()
                let popup    = MenuCtrl.createPopup(&host.root)
                popup.addItem("Illustrations", "open", host.theme.icon(.Folder, 16))
                popup.addItem("Documents", "documents", host.theme.icon(.Folder, 16))
                var checked: bool
                host.app.sigFrame += func|host = &host, popup, button, original, up, checked = &checked|(_)
                {
                    if checked[] do
                        return
                    let body   = popup.localToSurface(popup.getPopupBodyRect())
                    let gap    = popup.themeMetrics().menuPopup_AnchorGap
                    let margin = popup.themeMetrics().menuPopup_WindowMargin
                    Swag.require(button.surfaceRect() == original)
                    Swag.require(body.x >= margin and body.right() <= host.root.position.width - margin)
                    Swag.require(body.y >= margin and body.bottom() <= host.root.position.height - margin)
                    Swag.require(Math.abs((up ? original.y - body.bottom() : body.y - original.bottom()) - gap) < 0.01)
                    checked[] = true
                    popup.setEndModal(null)
                }

                discard popup.doModal(button, autoDestroy: true)
                Swag.require(checked)
            }
        }
    }
}

// A button inset into a floating bar must not pull the popup into that bar's border.
#test
{
    var host: Testing.HeadlessHost
    host.setup(540, 300)
    let bar = FloatingPanel.create(&host.root, {120, 230, 180, 44})
    bar.padding = 4
    let button = IconButton.createQuiet(bar)
    button.setQuietText("Options")
    button.setArrowPosition(.RightUpward)
    button.setPosition({4, 4, 100, 36})
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("First choice", "first")
    popup.addItem("Second choice", "second")
    host.app.sigFrame += func|popup, bar|(_)
    {
        let body = popup.localToSurface(popup.getPopupBodyRect())
        Swag.require(Math.abs(bar.surfaceRect().y - body.bottom() - popup.themeMetrics().menuPopup_AnchorGap) < 0.01)
        popup.setEndModal(null)
    }

    discard popup.doModal(button, autoDestroy: true)
}

// A popup menu keeps fractional measured rows when Wnd commits its rounded frame size.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)
    host.theme.metrics.menuPopup_ItemHeight = 30.4

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("A caption measured at a fractional width", "open")
    popup.computeLayoutPopup()

    var checked: bool
    host.app.sigFrame += func|popup, checked = &checked|(_)
    {
        if checked[] do
            return
        let item      = unwrap popup.items[0]
        let body      = popup.getPopupBodyRect()
        let metrics   = popup.themeMetrics()
        let textWidth = body.width - popup.padding.x - popup.padding.z - metrics.menuPopup_IconMargin - metrics.menuPopup_IconSize
        Swag.require(item.pos + item.size <= body.bottom() - popup.padding.w)
        Swag.require(item.name.boundRect.width <= textWidth)
        checked[] = true
        popup.setEndModal(null)
    }

    discard popup.doModal({40, 40})
    Swag.require(checked)
}
