#global public
using Core, Pixel

// One level of the path shown by a BreadcrumbCtrl (e.g. a folder). The app fills
// 'name'/'icon'/'userData'; the rectangles are computed by the control's layout and
// used for hit-testing. 'hasArrow' controls whether the level shows a drop-down chevron
// (the chevron of a level lists that level's children, the level to its right being the
// currently selected one).
struct BreadcrumbItem
{
    name:        String
    icon:        Icon
    userData:    u64
    tag:         String     // free app-defined string payload (e.g. a folder path)
    hasArrow     = true

    // Computed by layout(), in control-local coordinates.
    bodyRect:    Math.Rectangle
    arrowRect:   Math.Rectangle
}

// A horizontal breadcrumb / path bar. Each level is drawn as "[icon] name >". Clicking a
// level body navigates to it (sigItemPressed); clicking its chevron opens a drop-down that
// the app fills with the level's children (sigFillMenu) and reports the chosen entry id
// (sigMenuSelected). The control is data-only: it knows nothing about what the levels mean,
// so it works for folders, categories, or any other hierarchy.
struct BreadcrumbCtrl
{
    using wnd:          Wnd

    items:              Array'BreadcrumbItem
    hotItem             = Swag.U64.Max
    hotArrow:           bool
    pressItem           = Swag.U64.Max
    pressArrow:         bool

    // Horizontal padding inside a level body, gap between icon and text, and the padding
    // on each side of a chevron.
    padX                = 7.0'f32
    iconGap             = 5.0'f32
    arrowPad            = 6.0'f32

    // Clicking a level body: navigate to the level at this index.
    sigItemPressed:     SigArray'func||(*BreadcrumbCtrl, u64)
    // Opening a level's chevron: the app fills 'menu' with the level's children.
    sigFillMenu:        func||(*BreadcrumbCtrl, u64, *MenuCtrl)
    // A child was picked from a level's chevron menu; 'id' is the chosen menu item id.
    sigMenuSelected:    SigArray'func||(*BreadcrumbCtrl, u64, String)
}

impl BreadcrumbCtrl
{
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId = null)->*BreadcrumbCtrl
    {
        Debug.assert(parent != null)
        var pos = position
        if pos.height == 0 do
            pos.height = parent.getThemeMetrics().btnPush_Height
        let res = Wnd.create'BreadcrumbCtrl(parent, null, pos, id)
        return res
    }

    // Remove every level.
    mtd clear()
    {
        .items.clear()
        .hotItem = Swag.U64.Max
        .invalidate()
    }

    // Append a level. 'hasArrow' shows its drop-down chevron (default true). 'tag' is an
    // arbitrary string the app can read back (e.g. the level's folder path).
    mtd addItem(name: string, icon: Icon = {}, userData: u64 = 0, hasArrow = true, tag: string = null)
    {
        var it: BreadcrumbItem
        it.name     = name
        it.icon     = icon
        it.userData = userData
        it.tag      = tag
        it.hasArrow = hasArrow
        .items.add(#move it)
        .invalidate()
    }

    // Compute the per-level rectangles from the current items, in control-local space.
    mtd layout()
    {
        let font   = nnFont(.getFont().regular)
        let m      = .getThemeMetrics()
        let client = .getClientRect()

        var x = client.x
        for i in .items.count
        {
            let it = &.items[i]

            var w = .padX
            if it.icon.isValid() do
                w += it.icon.sizeX + .iconGap
            w += Painter.measureString(it.name.toString(), font).width + .padX

            it.bodyRect = {x, client.y, w, client.height}
            x += w

            if it.hasArrow
            {
                let aw = .arrowPad + m.btnIcon_HeightArrow + .arrowPad
                it.arrowRect = {x, client.y, aw, client.height}
                x += aw
            }
            else
            {
                it.arrowRect = {}
            }
        }
    }

    // Open the drop-down for the level at 'index', letting the app fill it, and report the
    // chosen entry (if any) through sigMenuSelected.
    mtd openMenu(index: u64)
    {
        if index >= .items.count do
            return

        let menu = MenuCtrl.createPopup(me)
        if .sigFillMenu do
            .sigFillMenu(me, index, menu)

        // Nothing to show: drop the empty popup rather than flashing an empty box.
        if menu.items.isEmpty()
        {
            menu.destroy()
            return
        }

        let ar  = .items[index].arrowRect
        let sr  = .getSurfaceRect()
        let sp  = Math.Point{sr.x + ar.horzCenter(), sr.y + ar.bottom()}
        let sel = menu.doModal(sp, .AnchorTopCenter, autoDestroy: true)
        if @countof(sel) != 0 do
            .sigMenuSelected.call(me, index, sel)
    }
}

impl IWnd for BreadcrumbCtrl
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .MouseLeave
        {
            if .hotItem != Swag.U64.Max
            {
                .hotItem = Swag.U64.Max
                .invalidate()
            }
            return
        }

        .layout()
        let pos = .surfaceToLocal(evt.surfacePos)

        var nh      = Swag.U64.Max
        var nhArrow = false
        for i in .items.count
        {
            let it = &.items[i]
            if it.hasArrow and it.arrowRect.contains(pos)
            {
                nh      = i
                nhArrow = true
                break
            }
            if it.bodyRect.contains(pos)
            {
                nh = i
                break
            }
        }

        if nh != .hotItem or nhArrow != .hotArrow
        {
            .hotItem  = nh
            .hotArrow = nhArrow
            .invalidate()
        }

        // Act on a completed click (press then release over the same target), like a
        // button. Opening the chevron popup on press would start its modal loop while the
        // button is still down, and the release would dismiss it immediately.
        if evt.kind == .MousePressed and evt.button == .Left
        {
            if nh != Swag.U64.Max
            {
                .pressItem  = nh
                .pressArrow = nhArrow
                .captureMouse()
            }
        }
        elif evt.kind == .MouseReleased and evt.button == .Left and .pressItem != Swag.U64.Max
        {
            let pi = .pressItem
            let pa = .pressArrow
            .pressItem = Swag.U64.Max
            .releaseMouse()

            if pi == nh and pa == nhArrow
            {
                if pa do
                    .openMenu(pi)
                else do
                    .sigItemPressed.call(me, pi)
            }
        }
    }

    mtd impl onPaintEvent(evt: *PaintEvent)
    {
        .layout()

        let painter = evt.bc.painter
        let theme   = .getTheme()
        let colors  = .getThemeColors()
        let rects   = .getThemeRects()
        let m       = .getThemeMetrics()
        let font    = nnFont(.getFont().regular)

        painter.setParams(.Antialiased)

        for i in .items.count
        {
            let it      = &.items[i]
            let hotBody = i == .hotItem and !.hotArrow
            let hotArr  = i == .hotItem and .hotArrow

            // Body background + text
            if hotBody do
                painter.fillRoundRect(it.bodyRect, 4, 4, colors.btnIcon_HotBk)

            let textColor = hotBody ? colors.btnIcon_HotText : colors.btnIcon_Text
            let iconColor = hotBody ? colors.btnIcon_HotText : colors.btnIcon_Icon

            var cx = it.bodyRect.x + .padX
            if it.icon.isValid()
            {
                it.icon.paint(painter, cx, it.bodyRect.vertCenter() - it.icon.sizeY * 0.5, iconColor)
                cx += it.icon.sizeX + .iconGap
            }

            painter.drawString(cx, it.bodyRect.vertCenter() - font.height * 0.5, it.name.toString(), font, textColor)

            // Chevron (right-pointing), same orientation as the icon-button right arrow.
            if it.hasArrow
            {
                if hotArr do
                    painter.fillRoundRect(it.arrowRect, 4, 4, colors.btnIcon_HotBk)

                var posArrow: Math.Rectangle
                posArrow.width  = m.btnIcon_HeightArrow
                posArrow.height = m.btnIcon_WidthArrow
                posArrow.x      = it.arrowRect.horzCenter() - posArrow.width * 0.5
                posArrow.y      = it.arrowRect.vertCenter() - posArrow.height * 0.5
                let arrowColor  = hotArr ? colors.btnIcon_HotText : colors.btnIcon_Icon
                theme.drawSubRect(painter, posArrow, &rects.btnIcon_ArrowRight, arrowColor)
            }
        }
    }
}
