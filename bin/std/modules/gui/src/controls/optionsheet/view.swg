#global public
#global namespace OptionSheet

using Core, Pixel

// Selects where an option sheet is presented.
enum Placement
{
    Anchored        // Joined to the button that opened it, like the menu of that button.
    BottomSheet     // Rises from the bottom edge of the window over a veil, for a touch screen.
    SidePanel       // Covers the trailing edge at full height over a veil, for a screen read from afar.
}

// Selects what choosing a value does on a page that holds nothing but choices.
//
// A page that mixes choices with other rows always stays open, so several settings of one group
// can be adjusted in turn.
enum AfterChoice
{
    Back      // Returns to the previous page, which shows the new value.
    Stay      // Keeps the page open, for trying values in turn.
    Close     // Closes the sheet.
}

// Lists settings with their current values, and slides to the choices of the one the reader picks.
//
// A sheet replaces a row of drop-down buttons with one entry point. Its first page names each
// setting with the value in force; activating a row slides the page of its choices in from the
// trailing side, and the header of that page, Left, Backspace or Escape slide back to where the
// reader came from. The height of the sheet follows the page it shows.
//
// Pages are described by [[Gui.OptionSheet.Builder]] callbacks rather than stored: the sheet asks
// for a page each time it shows it, so a value changed by one row is already right on the page
// the reader returns to. A row applies its change at once, and the application keeps painting
// behind the sheet, so the reader sees each choice take effect.
//
// ```swag
// let sheet = OptionSheet.View.create(button, func|player|(page)
// {
//     page.addLink("Speed", player.speedText(), func|player|(speeds)
//     {
//         for rate in Rates do
//             speeds.addChoice(rateText(rate), rate == player.rate, func|player, rate|() { player.setRate(rate) })
//     })
// })
//
// sheet.doModal(button, autoDestroy: true)
// ```
struct View
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        placement:   Placement   = .Anchored     // Where the sheet is presented; read when it opens.
        afterChoice: AfterChoice = .Back         // What choosing a value does on a page of choices.

        readonly
        {
            page: Page     // Page on screen, as its builder last described it.
        }
    }

    levels:   Array'Level     // Pages from the first one to the one on screen.
    leaving:  Page            // Page sliding out while another one slides in.
    focusRow: s32             // Focused row of the page on screen, or `HeaderFocus` for its header.
    pressed:  HitPart         // Part under the pointer when its button went down.

    // Whether the pointer rests on the focused row. Like a menu, the sheet grounds a row under the
    // pointer or under the keyboard, and leaves the focused row bare otherwise.
    pointerOnRow: bool

    // Geometry, in the local coordinates of the sheet.
    body:              Math.Rectangle     // Visible part of the ground, which holds the pages.
    ground:            Math.Rectangle     // Ground of the sheet, which runs past the window edges it covers.
    tab:               Math.Rectangle     // Opening button joined to the body, when anchored to one.
    anchorButton:      *IconButton?       // Button the sheet is joined to.
    anchorSurfaceRect: Math.Rectangle     // Bounds of that button, or the opening point, in surface coordinates.
    opensUp:           bool               // Whether an anchored body stands above its button.
    bodyWidth:         f32                // Width of the body.
    bodyHeight:        f32                // Height of the body as currently drawn.
    maxBodyHeight:     f32                // Tallest the body may grow on its side of the button.

    // Motion.
    slideProgress:  f32 = 1     // Progress of the page change, from zero to one.
    slideDirection: f32 = 1     // One when going deeper, minus one when coming back.
    openProgress:   f32 = 1     // Progress of the arrival of a sheet presented over a veil.
    slideHandle:    AnimationHandle
    heightHandle:   AnimationHandle
    pendingTimer:   *Timer?         // Delay that lets a choice show its check before the sheet moves on.
    pendingClose:   bool            // Whether the pending delay closes the sheet rather than going back.
    deferredRun:    (func||())?     // Action that closed the sheet, to run once it has left the screen.

    ended: bool     // Whether the modal loop must stop.
}

private struct Level
{
    build:  Builder?
    title:  String
    focus:  s32     // Row to focus again when the reader comes back to this page.
    scroll: f32     // Vertical scroll of the rows of this page.
}

// Part of a sheet under a point.
private struct HitPart
{
    row:  s32 = NoRow     // Row index, `HeaderFocus` for the header, or `NoRow`.
    step: s32             // Direction of the stepper arrow under the point, or zero.
}

private const HeaderFocus = -1's32
private const NoRow       = -2's32

private const SlideChannel  = "Gui.OptionSheet.Slide"
private const HeightChannel = "Gui.OptionSheet.Height"
private const OpenChannel   = "Gui.OptionSheet.Open"

// How far the page leaving the sheet travels, as a fraction of the width the arriving page crosses.
private const LeavingTravel = 0.3'f32

// Opacity the arriving page starts from, so it is already legible while it slides.
private const ArrivingOpacity = 0.4'f32

// How long a chosen value stays on screen, checked, before the sheet moves on.
private const ChoiceHold: Time.Duration = 170'ms

impl IWnd for View
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        // A sheet presented over the window dims what it covers, and arrives with its veil.
        if .placement != .Anchored
        {
            painter.fillRect(.clientRect(), fade(colors.veilStrong, .openProgress))
            painter.pushTransform()
            painter.translateTransform(.arrivalOffset().x, .arrivalOffset().y)
        }

        let body       = .body
        let shadowRect = .placement == .Anchored ? .anchoredShadowRect() : .ground
        theme.drawSubRect(painter, shadowRect, &rects.menuPopup_Shadow, colors.menuPopup_Shadow)
        theme.drawSubRect(painter, .ground, &rects.menuPopup_Bk, colors.menuPopup_Bk)

        // Both pages are drawn inside the ground, so a page sliding out of it disappears under
        // its edge instead of crossing the outline.
        var clip = body
        clip.inflate(-metrics.wnd_BorderSize)
        painter.pushClippingRect(clip)
        let width = .bodyWidth
        if .slideProgress < 1
        {
            let leavingX      = -.slideProgress * LeavingTravel * width * .slideDirection
            let arrivingX     = (1 - .slideProgress) * width * .slideDirection
            let leavingLevels = .slideDirection > 0 ? .levels.count - 1 : .levels.count + 1

            // The leaving page fades faster than the arriving one gains, so the two never read as one.
            let leavingOpacity = (1 - .slideProgress) * (1 - .slideProgress)
            .paintPage(painter, &.leaving, leavingLevels, leavingX, leavingOpacity, NoRow, .leavingScroll())
            .paintPage(painter, &.page, .levels.count, arrivingX, Math.lerp(ArrivingOpacity, 1, .slideProgress), .focusRow, .levels.back().scroll)
        }
        else
        {
            .paintPage(painter, &.page, .levels.count, 0, 1, .focusRow, .levels.back().scroll)
        }

        painter.popClippingRect()
        theme.drawSubRect(painter, .ground, &rects.menuPopup_Border, colors.menuPopup_Border, interpol: .Pixel)

        if .placement == .Anchored
        {
            if not .tab.isEmpty()
            {
                paintPopupAnchorTab(me, painter, .tab, body, .opensUp)
                .anchorButton?.paintMenuAnchorContent(painter, .tab, colors.menuBar_SelectedText)
            }
        }
        else
        {
            painter.popTransform()
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed do
            return

        let shift = evt.modifiers.has(.Shift)
        let row   = .focusedRow()
        switch evt.key
        {
        case .Down:                                     .moveFocus(1)
        case .Up:                                       .moveFocus(-1)
        case .Tab:                                      .moveFocus(shift ? -1 : 1)
        case .Home:                                     .focusEdge(first: true)
        case .End:                                      .focusEdge(first: false)
        case .Return, .Space:                           .activate(.focusRow, 0)
        case .Back, .BrowserBack:                       .back()
        case .Escape:                                   .back()
        case .Right where row and row.kind == .Stepper: .activate(.focusRow, shift ? 10 : 1)
        case .Right where row and row.kind == .Link:    .activate(.focusRow, 0)
        case .Left where row and row.kind == .Stepper:  .activate(.focusRow, shift ? -10 : -1)
        case .Left where .levels.count > 1:             .back()
        case .Right, .Left:                             break
        default:                                        return
        }

        evt.accepted  = true
        .pointerOnRow = false
        .app().setFocusVisible(true)
        .invalidate()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        evt.accepted = true
        let pos = .surfaceToLocal(evt.surfacePos) - .arrivalOffset()
        let hit = .hitTest(pos)

        switch evt.kind
        {
        case .Move:
            let moved = evt.delta.x != 0 or evt.delta.y != 0
            if not moved or .slideProgress < 1 do
                break
            let onRow = hit.row != NoRow
            if onRow == .pointerOnRow and (not onRow or hit.row == .focusRow) do
                break
            .pointerOnRow = onRow
            if onRow do
                .focusRow = hit.row
            .invalidate()

        case .Pressed:
            if evt.button != .Left do
                break
            if not .body.contains(pos)
            {
                .close()
                break
            }

            .pressed = hit

        case .Released:
            if evt.button != .Left do
                break
            let pressed = .pressed
            .pressed = {}
            if pressed.row != NoRow and pressed.row == hit.row and pressed.step == hit.step
            {
                .focusRow = hit.row
                .activate(hit.row, hit.step)
            }

        case .Wheel:
            .scrollBy(-evt.delta.y * .themeMetrics().optionSheet_RowHeight)
        }
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        .removePendingTimer()
        if .pendingClose do
            .close()
        else do
            .back()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        // A sheet that changes the theme or the language describes itself again in the new one.
        if evt.kind == .ThemeChanged or evt.kind == .LanguageChanged
        {
            .refresh()
            .place()
        }

        evt.accepted = false
    }
}

impl View
{
    // Creates a hidden sheet whose first page `build` fills.
    //
    // The sheet joins the presentation layer of `parent`, the way a popup menu does, so a sheet
    // opened from the title bar is not clipped by the content of the window. `owner`, or `parent`
    // when omitted, routes the commands of the sheet.
    #[Swag.Discardable]
    func create(parent: *Wnd, build: Builder, owner: *Wnd? = null)->*View
    {
        Swag.assert(parent != null)
        let topView     = parent.topView()
        let sheetParent = parent == topView or topView.isAncestorOf(parent) ? topView : parent.topWindow()
        with let result = Wnd.create'View(sheetParent, null, {})
        {
            .focusPolicy = .Click
            .owner       = owner orelse parent
            .wndFlags    |= .Hidden
            .levels.add(Level{build: build})
        }

        return result
    }

    // Runs the sheet joined to `button` until the reader closes it.
    //
    // With [[Gui.OptionSheet.Placement.Anchored]], the button is repainted as the tab of the
    // sheet, the way [[Gui.MenuCtrl.doModal]] joins a menu to it. The sheet opens above the button
    // when its marker is [[Gui.IconButtonArrowPosition.RightUpward]] or when it sits in the lower
    // half of the window, and below it otherwise. When `autoDestroy` is true, the sheet destroys
    // itself once closed.
    mtd doModal(button: *IconButton, autoDestroy = false)
    {
        .anchorButton      = button
        .anchorSurfaceRect = button.surfaceRect()
        .runModal(autoDestroy)

        // The keyboard comes back to where the reader opened the sheet from.
        if button.focusPolicy != .None and not button.isPendingDestroy do
            button.setFocus()
    }

    // Runs the sheet from the surface position `surfacePos` until the reader closes it.
    //
    // An anchored sheet opens with its corner at that point. When `autoDestroy` is true, the sheet
    // destroys itself once closed.
    mtd doModal(surfacePos: Math.Point, autoDestroy = false)
    {
        .anchorButton      = null
        .anchorSurfaceRect = {surfacePos.x, surfacePos.y, 0, 0}
        .runModal(autoDestroy)
    }

    // Closes the sheet and ends its modal loop.
    mtd close()
    {
        .removePendingTimer()
        .ended = true
    }

    // Reports whether the modal loop of the sheet has ended.
    mtd const isClosed()->bool => .ended

    // Returns how many pages deep the sheet is; the first page is depth one.
    mtd const depth()->u64 => .levels.count

    // Asks the builder of the page on screen to describe it again.
    //
    // Call it when something other than the sheet changed what the page shows. The focus stays on
    // the same row when the page still has it.
    mtd refresh()
    {
        .rebuild()
        .fitHeight(animate: .isVisible())
        .invalidate()
    }

    // Opens the page of the link at `row` on the page on screen, as if the reader activated it.
    mtd openLink(row: u32)
    {
        Swag.assert(row < .page.rows.count and .page.rows[row].kind == .Link)
        .activate(cast(s32, row), 0)
    }

    // Returns to the previous page, or closes the sheet from its first page.
    mtd back()
    {
        .finishMotion()
        if .levels.count == 1
        {
            .close()
            return
        }

        discard .levels.popBack()
        .leaving = #move .page
        .rebuild()
        .focusRow = .levels.back().focus
        .clampFocus()
        .startSlide(-1)
    }

    // Returns the index of the row worded `label` on the page on screen, or `Swag.U32.Max`.
    mtd const findRow(label: string)->u32
    {
        for row, index in .page.rows where row.label.raw == label do
            return cast(u32, index)
        return Swag.U32.Max
    }

    // Activates the row worded `label` as a click would, and reports whether it was found.
    //
    // For a stepper, `step` gives the direction; it is ignored by the other rows.
    mtd activateRow(label: string, step: s32 = 0)->bool
    {
        let index = .findRow(label)
        if index == Swag.U32.Max or not .page.rows[index].isActive() do
            return false
        .focusRow = cast(s32, index)
        .activate(cast(s32, index), step)
        return true
    }
}

private impl View
{
    mtd runModal(autoDestroy: bool)
    {
        let metrics = .themeMetrics()

        .ended         = false
        .slideProgress = 1
        .levels.resize(1)
        .rebuild()
        .focusRow = .initialFocus()

        .decidePlacement()
        if .placement != .SidePanel do
            .bodyHeight = Math.min(.contentHeight(&.page, 1), .maxBodyHeight)
        .place()

        .bringToFront()
        .show()
        .captureMouse()
        .setFocus()
        .startArrival(metrics)

        .app().inModalLoop += 1
        let surface = unwrap .surface
        while not .ended do
            surface.app.runFrame()
        .app().inModalLoop -= 1

        .finishMotion()
        .removePendingTimer()
        .releaseMouse()
        .hide()
        .resetPresentation()

        // An action that opens something else does it once nothing of the sheet is left on screen.
        if .deferredRun
        {
            let run = .deferredRun
            .deferredRun = null
            run()
        }

        if autoDestroy do
            .destroy()
    }

    // Settles the width, the side and the tallest height of the sheet before it is shown.
    mtd decidePlacement()
    {
        let metrics = .themeMetrics()
        let parent  = unwrap .parent
        let bounds  = parent.clientRect()
        let margin  = metrics.menuPopup_WindowMargin

        switch .placement
        {
        case .Anchored:
            let anchor = .anchorSurfaceRect
            let local  = parent.surfaceToLocal(Math.Point{anchor.x, anchor.y})
            let shadow = metrics.menuPopup_ShadowSize
            let tab    = .anchorButton ? anchor.height : 0
            .bodyWidth = Math.min(Math.max(metrics.optionSheet_Width, anchor.width), bounds.width - 2 * margin)

            let roomAbove = local.y - bounds.y - margin - shadow
            let roomBelow = bounds.bottom() - local.y - tab - margin - shadow
            let wanted    = .contentHeight(&.page, 1)
            if .anchorButton and .anchorButton.arrowPosition == .RightUpward do
                .opensUp = true
            elif .anchorButton and .anchorButton.arrowPosition == .RightDownward do
                .opensUp = false
            else do
                .opensUp = local.y + anchor.height * 0.5 > bounds.vertCenter()
            if .opensUp and wanted > roomAbove and roomBelow > roomAbove do
                .opensUp = false
            elif not .opensUp and wanted > roomBelow and roomAbove > roomBelow do
                .opensUp = true
            .maxBodyHeight = Math.max(.opensUp ? roomAbove : roomBelow, metrics.optionSheet_RowHeight * 3)

        case .BottomSheet:
            .bodyWidth     = Math.min(bounds.width, metrics.optionSheet_Width * 2)
            .maxBodyHeight = bounds.height * 0.8

        case .SidePanel:
            .bodyWidth     = Math.min(bounds.width * 0.9, metrics.optionSheet_SidePanelWidth)
            .maxBodyHeight = bounds.height
            .bodyHeight    = bounds.height
        }
    }

    // Moves the window of the sheet around its body, for the height the body has now.
    mtd place()
    {
        let metrics = .themeMetrics()
        let parent  = unwrap .parent
        let bounds  = parent.clientRect()

        switch .placement
        {
        case .Anchored:
            let margin    = metrics.menuPopup_WindowMargin
            let shadow    = metrics.menuPopup_ShadowSize
            let corner    = parent.surfaceToLocal(Math.Point{.anchorSurfaceRect.x, .anchorSurfaceRect.y})
            let anchor    = Math.Rectangle{corner.x, corner.y, .anchorSurfaceRect.width, .anchorSurfaceRect.height}
            let tabHeight = .anchorButton ? anchor.height : 0

            // The body starts under the button and keeps it inside its width, sliding left of it
            // only when the window ends first.
            var left = anchor.x
            if left + .bodyWidth > bounds.right() - margin do
                left = Math.max(anchor.right() - .bodyWidth, bounds.x + margin)

            var bodyTop = .opensUp ? anchor.y - .bodyHeight : anchor.y + tabHeight
            if not .anchorButton and .opensUp do
                bodyTop = anchor.y - .bodyHeight
            let top    = Math.min(bodyTop, anchor.y) - shadow
            let bottom = Math.max(bodyTop + .bodyHeight, anchor.y + tabHeight) + shadow
            .setPosition(Math.Rectangle{left - shadow, top, .bodyWidth + 2 * shadow, bottom - top})

            .body   = {shadow, bodyTop - top, .bodyWidth, .bodyHeight}
            .ground = .body
            .tab    = .anchorButton ? Math.Rectangle{anchor.x - left + shadow, anchor.y - top, anchor.width, anchor.height} : {}

        case .BottomSheet:

            // The body runs past the bottom edge so its lower corners and outline stay out of sight.
            .setPosition(bounds)
            let radius = .themeRects().menuPopup_Bk.radius
            .body   = {(bounds.width - .bodyWidth) * 0.5, bounds.height - .bodyHeight, .bodyWidth, .bodyHeight}
            .ground = {.body.x, .body.y, .body.width, .body.height + radius}
            .tab    = {}

        case .SidePanel:

            // The body runs past the trailing and both horizontal edges for the same reason.
            .setPosition(bounds)
            let radius = .themeRects().menuPopup_Bk.radius
            .body   = {bounds.width - .bodyWidth, 0, .bodyWidth, bounds.height}
            .ground = {.body.x, -radius, .bodyWidth + radius, bounds.height + 2 * radius}
            .tab    = {}
        }

        .invalidate()
    }

    // Shadow of an anchored sheet: everything but the band of the button it is joined to.
    mtd anchoredShadowRect()->Math.Rectangle
    {
        let client = .clientRect()
        if .tab.isEmpty() do
            return client
        let tabBand = .tab.height
        return {0, .opensUp ? 0 : tabBand, client.width, client.height - tabBand}
    }

    // Displacement of a sheet presented over a veil while it arrives.
    mtd arrivalOffset()->Math.Point
    {
        let remaining = 1 - .openProgress
        switch .placement
        {
        case .BottomSheet: return {0, remaining * .bodyHeight}
        case .SidePanel:   return {remaining * .bodyWidth, 0}
        default:           return {}
        }
    }

    // Starts the arrival of the sheet: a fade beside its button, a slide from the edge over a veil.
    mtd startArrival(metrics: const *ThemeMetrics)
    {
        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(metrics.motion_PanelSeconds)
        options.easing   = .EaseOut

        if .placement == .Anchored
        {
            let rise = .opensUp ? metrics.optionSheet_Inset : -metrics.optionSheet_Inset
            .setPresentationOpacity(0)
            .setPresentationOffset({0, rise})
            var group = AnimationGroup.concurrent()
            group.addF32(me, AnimationChannel.from(OpenChannel), 0, 1, func(wnd, value) { wnd.setPresentationOpacity(value) }, options)
            group.addPoint(me, AnimationChannel.from("Gui.OptionSheet.Rise"), {0, rise}, {}, func(wnd, value) { wnd.setPresentationOffset(value) }, options)
            discard .app().animator.start(#move group)
            return
        }

        .openProgress = 0
        discard .app().animator.animateF32(me, AnimationChannel.from(OpenChannel), 0, 1, func(sheet, value) { sheet.openProgress = value }, options)
    }

    // Describes the page on screen again through its builder.
    mtd rebuild()
    {
        let level = .levels.backPtr()
        var page: Page
        page.title = level.title
        let build = unwrap level.build
        build(&page)
        if page.title.isEmpty() and .levels.count == 1 do
            page.title = strings().optionSheet_Title
        .page = #move page
        .clampFocus()
        .clampScroll()
    }

    // Row the keyboard lands on when a page opens: the value in force, else the first row.
    mtd initialFocus()->s32
    {
        for row, index in .page.rows where row.kind == .Choice and row.checked do
            return cast(s32, index)
        for row, index in .page.rows where row.isFocusable() do
            return cast(s32, index)
        return .levels.count > 1 ? HeaderFocus : NoRow
    }

    mtd clampFocus()
    {
        if .focusRow == HeaderFocus and .levels.count > 1 do
            return
        if .focusRow >= 0 and .focusRow < .page.rows.count and .page.rows[.focusRow].isFocusable() do
            return

        // A row that disappeared hands the focus to the closest row above it.
        var index = Math.min(.focusRow, cast(s32, .page.rows.count) - 1)
        while index >= 0
        {
            if .page.rows[index].isFocusable()
            {
                .focusRow = index
                return
            }

            index -= 1
        }

        .focusRow = .initialFocus()
    }

    mtd focusedRow()->const *Row?
    {
        if .focusRow < 0 or .focusRow >= .page.rows.count do
            return null
        return &.page.rows[.focusRow]
    }

    // Moves the focus by `delta` stops, around the page, the header being the stop above the first row.
    mtd moveFocus(delta: s32)
    {
        .finishMotion()
        var stops: Array's32
        if .levels.count > 1 do
            stops.add(HeaderFocus)
        for row, index in .page.rows where row.isFocusable() do
            stops.add(cast(s32, index))
        if stops.isEmpty() do
            return

        var current = 0's64
        for stop, index in stops where stop == .focusRow do
            current = cast(s64, index)
        let count = cast(s64, stops.count)
        let next  = ((current + delta) % count + count) % count
        .focusRow = stops[cast(u64, next)]
        .revealFocus()
        .invalidate()
    }

    mtd focusEdge(first: bool)
    {
        .finishMotion()
        if first and .levels.count > 1
        {
            .focusRow = HeaderFocus
        }
        else
        {
            for row, index in .page.rows where row.isFocusable()
            {
                .focusRow = cast(s32, index)
                if first do
                    break
            }
        }

        .revealFocus()
        .invalidate()
    }

    // Carries out what the row at `index` does; `step` is the direction of a stepper.
    mtd activate(index: s32, step: s32)
    {
        .finishMotion()
        if .pendingTimer do
            return
        if index == HeaderFocus
        {
            .back()
            return
        }

        if index < 0 or index >= .page.rows.count do
            return
        let row = &.page.rows[index]
        if not row.isActive() do
            return

        switch row.kind
        {
        case .Link:
            .levels.backPtr().focus = index
            .levels.add(Level{build: unwrap row.open, title: row.label.raw})
            .leaving = #move .page
            .rebuild()
            .focusRow = .initialFocus()
            .startSlide(1)

        case .Choice:
            let wasChoiceList = .page.isChoiceList()
            let choose        = unwrap row.choose
            choose()
            .refresh()
            if not wasChoiceList do
                break
            switch .afterChoice
            {
            case .Back where .levels.count > 1: .holdThen(close: false)
            case .Close: .holdThen(close: true)
            default:     break
            }

        case .Toggle:
            let toggle = unwrap row.toggle
            toggle(not row.checked)
            .refresh()

        case .Stepper:
            if step == 0 do
                break
            if (step < 0 and not row.canDecrease) or (step > 0 and not row.canIncrease) do
                break
            let stepper = unwrap row.step
            stepper(step)
            .refresh()

        case .Action where row.closesSheet:
            .deferredRun = row.run
            .close()

        case .Action:
            let run = unwrap row.run
            run()
            .refresh()

        case .Heading:
            break
        }
    }

    // Leaves the checked value on screen for a moment, then goes back or closes.
    mtd holdThen(close: bool)
    {
        .pendingClose = close
        .pendingTimer = .app().addTimer(ChoiceHold, me)
    }

    mtd removePendingTimer()
    {
        if not .pendingTimer do
            return
        .app().removeTimer(.pendingTimer)
        .pendingTimer = null
    }

    // Slides the page on screen in over the page that just left; `direction` is one going deeper.
    mtd startSlide(direction: f32)
    {
        let metrics = .themeMetrics()
        .slideDirection = direction
        .slideProgress  = 0
        .pressed        = {}

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(metrics.motion_PanelSeconds)
        options.easing   = .EaseOut

        let completeSlide = func|me|(_: AnimationResult) { me.slideProgress = 1 }
        .slideHandle = .app().animator.animateF32(me, AnimationChannel.from(SlideChannel), 0, 1, func(sheet, value) { sheet.slideProgress = value }, options, completeSlide)

        .fitHeight(animate: true)
        .revealFocus()
        .invalidate()
    }

    // Brings the height of the body to what the page on screen needs.
    mtd fitHeight(animate: bool)
    {
        if .placement == .SidePanel do
            return

        let target = Math.min(.contentHeight(&.page, .levels.count), .maxBodyHeight)
        .app().animator.cancel(.heightHandle)
        if not animate or target == .bodyHeight
        {
            .bodyHeight = target
            .place()
            return
        }

        var options: AnimationOptions
        options.duration = Time.Duration.fromSeconds(.themeMetrics().motion_PanelSeconds)
        options.easing   = .EaseInOut

        func updateHeight(sheet: *View, value: f32)
        {
            sheet.bodyHeight = value
            sheet.place()
        }

        let completeHeight = func|me, target|(_: AnimationResult)
        {
            if me.isPendingDestroy do
                return
            me.bodyHeight = target
            me.place()
            me.clampScroll()
            me.revealFocus()
        }

        .heightHandle = .app().animator.animateF32(me,
                                                   AnimationChannel.from(HeightChannel),
                                                   .bodyHeight,
                                                   target,
                                                   &updateHeight,
                                                   options,
                                                   completeHeight)
    }

    // Brings every running motion to its end, so input acts on the page as it will settle.
    mtd finishMotion()
    {
        .app().animator.cancel(.slideHandle)
        .app().animator.cancel(.heightHandle)
        .slideProgress = 1
    }

    // Height the body needs to show every row of `page`, `levels` pages deep.
    internal mtd contentHeight(page: const *Page, levels: u64)->f32
    {
        var height = .headerHeight(levels) + .rowTopInset() + .rowBottomInset()
        for row in page.rows do
            height += .rowHeight(row)
        return height
    }

    // Anchored tabs paint over the body by `menuPopup_BarItemOverlap`; keep the first row below it.
    mtd rowTopInset()->f32
    {
        let metrics = .themeMetrics()
        if .placement == .Anchored and .anchorButton and not .opensUp do
            return Math.max(metrics.optionSheet_Inset, metrics.menuPopup_BarItemOverlap)
        return metrics.optionSheet_Inset
    }

    mtd rowBottomInset()->f32
    {
        let metrics = .themeMetrics()
        if .placement == .Anchored and .anchorButton and .opensUp do
            return Math.max(metrics.optionSheet_Inset, metrics.menuPopup_BarItemOverlap)
        return metrics.optionSheet_Inset
    }

    // Height of the band above the header: the grip a bottom sheet is pulled by.
    mtd gripHeight()->f32 => .placement == .BottomSheet ? .themeMetrics().optionSheet_Inset * 2 : 0

    mtd headerHeight(levels: u64)->f32
    {
        if levels == 1 and .placement == .Anchored do
            return 0
        return .gripHeight() + Math.round(.themeMetrics().optionSheet_HeaderHeight * .rowScale())
    }

    // How much taller a row is than beside a button: a finger and a remote need larger targets
    // than a pointer, and a screen read from afar needs more air between lines.
    mtd rowScale()->f32
    {
        switch .placement
        {
        case .BottomSheet: return 1.4
        case .SidePanel:   return 1.25
        default:           return 1
        }
    }

    internal mtd rowHeight(row: const *Row)->f32
    {
        let metrics = .themeMetrics()
        switch row.kind
        {
        case .Heading: return metrics.optionSheet_HeadingHeight
        case .Choice where not row.detail.isEmpty(): return Math.round(metrics.optionSheet_DetailRowHeight * .rowScale())
        default:       return Math.round(metrics.optionSheet_RowHeight * .rowScale())
        }
    }

    // Top of the row at `index` relative to the top of the scrolled list.
    internal mtd rowTop(page: const *Page, index: s32)->f32
    {
        var top = .rowTopInset()
        for i in index do
            top += .rowHeight(&page.rows[i])
        return top
    }

    internal mtd listRect(levels: u64)->Math.Rectangle
    {
        var result: #returntype = .body
        let header = .headerHeight(levels)
        result.y      += header
        result.height = Math.max(.bodyHeight - header, 0)
        return result
    }

    mtd leavingScroll()->f32 => .slideDirection > 0 and .levels.count > 1 ? .levels[.levels.count - 2].scroll : 0

    mtd scrollBy(delta: f32)
    {
        .levels.backPtr().scroll += delta
        .clampScroll()
        .invalidate()
    }

    mtd clampScroll()
    {
        let list     = .listRect(.levels.count)
        let overflow = Math.max(.contentHeight(&.page, .levels.count) - .headerHeight(.levels.count) - list.height, 0)
        let level    = .levels.backPtr()
        level.scroll = Math.clamp(level.scroll, 0, overflow)
    }

    // Scrolls the list so the focused row is entirely visible.
    mtd revealFocus()
    {
        if .focusRow < 0
        {
            .levels.backPtr().scroll = 0
            return
        }

        let list   = .listRect(.levels.count)
        let level  = .levels.backPtr()
        let top    = .rowTop(&.page, .focusRow)
        let bottom = top + .rowHeight(&.page.rows[.focusRow]) + .rowBottomInset()
        if top - .rowTopInset() < level.scroll do
            level.scroll = top - .rowTopInset()
        elif bottom > level.scroll + list.height do
            level.scroll = bottom - list.height
        .clampScroll()
    }

    // Finds the part of the page on screen under the local point `pos`.
    mtd hitTest(pos: Math.Point)->HitPart
    {
        var result: #returntype
        if .slideProgress < 1 or not .body.contains(pos) do
            return result

        let levels = .levels.count
        let header = .headerHeight(levels)
        if pos.y < .body.y + header
        {
            if levels > 1 do
                result.row = HeaderFocus
            return result
        }

        let list = .listRect(levels)
        var y    = list.y + .rowTopInset() - .levels.back().scroll
        for row, index in .page.rows
        {
            let height = .rowHeight(row)
            if pos.y >= y and pos.y < y + height
            {
                if row.isFocusable() do
                    result.row = cast(s32, index)
                if row.kind == .Stepper do
                    result.step = .stepperHit(.rowRect(list, y, height), pos)
                return result
            }

            y += height
        }

        return result
    }

    // Ground of a row whose top is `y`, inset from the edges of the body.
    internal mtd rowRect(list: Math.Rectangle, y, height: f32)->Math.Rectangle
    {
        let inset = .themeMetrics().optionSheet_Inset
        return {list.x + inset, y, list.width - 2 * inset, height}
    }

    // Reports which arrow of a stepper row `rect` lies under `pos`: `-1`, `1`, or zero for neither.
    mtd stepperHit(rect: Math.Rectangle, pos: Math.Point)->s32
    {
        let parts = .stepperParts(rect)
        if parts.decrease.contains(pos) do
            return -1
        if parts.increase.contains(pos) do
            return 1
        return 0
    }

    // Lays out the two step buttons and the value between them at the trailing end of a row.
    internal mtd stepperParts(rect: Math.Rectangle)->{decrease: Math.Rectangle, value: Math.Rectangle, increase: Math.Rectangle}
    {
        let metrics = .themeMetrics()
        let side    = Math.round(rect.height * 0.75)
        let top     = Math.round(rect.vertCenter() - side * 0.5)
        let value   = metrics.optionSheet_ValueMaxWidth * 0.45
        let right   = rect.right() - metrics.optionSheet_Inset
        let inc     = Math.Rectangle{right - side, top, side, side}
        let val     = Math.Rectangle{inc.x - value, rect.y, value, rect.height}
        let dec     = Math.Rectangle{val.x - side, top, side, side}
        return {dec, val, inc}
    }

    // Reports whether the pointer holds down the step button of direction `step` on the focused row.
    mtd pressedStep(step: s32)->bool => .pressed.row == .focusRow and .pressed.step == step

    // Paints one step button: a square outline holding a minus or, when `increase`, a plus.
    mtd paintStepButton(painter: *Painter, box: Math.Rectangle, increase, enabled, hot: bool, opacity: f32)
    {
        let theme  = .theme()
        let colors = .themeColors()
        let rects  = .themeRects()
        if hot and enabled do
            theme.drawSubRect(painter, box, &rects.btnIcon_RoundSquareBk, fade(colors.optionSheet_HotBk, opacity))
        let border = enabled ? colors.optionSheet_StepBorder : colors.popupItem_DisabledSubmenuMarker
        let radius = rects.btnIcon_RoundSquareBk.radius
        var frame  = box
        frame.inflate(-0.5)
        painter.drawRoundRect(frame, radius, radius, Pen.createSolid(fade(border, opacity)))

        // The glyph is drawn rather than taken from the atlas, so its stroke stays crisp at every
        // size a row gives the button.
        let ink  = fade(enabled ? colors.popupItem_Text : colors.popupItem_DisabledText, opacity)
        let pen  = Pen.createSolid(ink, 1.5)
        let half = Math.round(box.width * 0.22)
        let cx   = Math.round(box.horzCenter())
        let cy   = Math.round(box.vertCenter())
        painter.drawLine(cx - half, cy, cx + half, cy, pen)
        if increase do
            painter.drawLine(cx, cy - half, cx, cy + half, pen)
    }

    // Paints `page`, `levels` pages deep, shifted by `offsetX` and faded to `opacity`.
    mtd paintPage(painter: *Painter, page: const *Page, levels: u64, offsetX: f32, opacity: f32, focus: s32, scroll: f32)
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()
        let ring    = focus != NoRow and .showsFocusRing()
        let focused = ring or (focus != NoRow and .pointerOnRow)

        // The header names the page and leads back from it.
        let header = .headerHeight(levels)
        if header
        {
            let grip = .gripHeight()
            if grip
            {
                let width = metrics.optionSheet_HeaderHeight
                let line  = Math.Rectangle{.body.horzCenter() - width * 0.5 + offsetX, .body.y + grip * 0.5, width, 4}
                painter.fillRoundRect(line, 2, 2, fade(colors.optionSheet_StepBorder, opacity))
            }

            var band = Math.Rectangle{.body.x + offsetX, .body.y + grip, .body.width, header - grip}
            if focused and focus == HeaderFocus
            {
                var ground = band
                ground.inflate(-metrics.optionSheet_Inset, -metrics.optionSheet_Inset * 0.5)
                theme.drawSubRect(painter, ground, &rects.menuPopup_HotBk, fade(colors.optionSheet_HotBk, opacity))
                if ring do
                    theme.drawFocusRing(painter, ground, rects.menuPopup_HotBk.radius, colors.optionSheet_HotBk)
            }

            var x = band.x + metrics.optionSheet_Inset + metrics.optionSheet_RowPadding
            if levels > 1
            {
                let chevron = theme.icon(.ChevronLeft, metrics.chevron_Size)
                chevron.paint(painter, x, opticalTop(.font(), band.vertCenter(), chevron.sizeY), fade(colors.popupItem_SubmenuMarker, opacity))
                x += metrics.menuPopup_IconSize + metrics.menuPopup_IconTextMargin * 0.5
            }

            var title: RichString
            title.set(page.title)
            .drawText(painter, {x, band.y, band.right() - x - metrics.optionSheet_RowPadding, band.height}, &title, fade(colors.popupItem_Text, opacity), bold: true)
            painter.drawLine(band.x, band.bottom() - 0.5, band.right(), band.bottom() - 0.5, Pen.createSolid(fade(colors.menuPopup_Separator, opacity)))
        }

        // The rows scroll under the header.
        var list = .listRect(levels)
        painter.pushClippingRect(list)
        list.x += offsetX
        var y = list.y + .rowTopInset() - scroll
        for row, index in page.rows
        {
            let height = .rowHeight(row)
            if y + height > list.y and y < list.bottom()
            {
                let rect = .rowRect(list, y, height)
                let hot  = focused and focus == cast(s32, index)
                .paintRow(painter, row, rect, hot, hot and ring, opacity)
            }

            y += height
        }

        painter.popClippingRect()
    }

    mtd paintRow(painter: *Painter, row: const *Row, rect: Math.Rectangle, hot, ring: bool, opacity: f32)
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        // A heading labels its group rather than being a row: small spaced capitals, quiet as a
        // caption, so the eye skips it on its way to the settings.
        if row.kind == .Heading
        {
            var label: RichString
            label.set(row.label.raw.toUpper(.Unicode))
            var text = rect
            text.x      += metrics.optionSheet_RowPadding
            text.y      += metrics.optionSheet_Inset
            text.width  -= 2 * metrics.optionSheet_RowPadding
            text.height -= metrics.optionSheet_Inset

            var format = .textFormat(fade(colors.popupItem_Heading, opacity), .Left)
            format.font          = theme.createDefaultFontFamily(metrics.defaultFontSize - 2)
            format.fontStyle     = .Bold
            format.letterSpacing = 0.8
            painter.drawRichString(text, &label, format)
            return
        }

        if hot
        {
            theme.drawSubRect(painter, rect, &rects.menuPopup_HotBk, fade(colors.optionSheet_HotBk, opacity))
            if ring do
                theme.drawFocusRing(painter, rect, rects.menuPopup_HotBk.radius, colors.optionSheet_HotBk)
        }

        let textColor   = fade(row.disabled ? colors.popupItem_DisabledText : (hot ? colors.popupItem_HotText : colors.popupItem_Text), opacity)
        let valueColor  = fade(row.disabled ? colors.popupItem_DisabledText : (hot ? colors.popupItem_HotRightText : colors.popupItem_RightText), opacity)
        let markerColor = fade(row.disabled ? colors.popupItem_DisabledSubmenuMarker : (hot ? colors.popupItem_HotSubmenuMarker : colors.popupItem_SubmenuMarker), opacity)

        // The leading column holds the glyph of a link or the check of the value in force, so the
        // wording of every row of a page starts at the same place.
        let leadX  = rect.x + metrics.optionSheet_RowPadding
        let iconSz = metrics.menuPopup_IconSize
        let center = row.detail.isEmpty() ? rect.vertCenter() : rect.y + rect.height * 0.32
        if row.kind == .Link and row.icon.isValid()
        {
            var icon = row.icon
            icon.sizeX, icon.sizeY = iconSz
            icon.paint(painter, leadX, opticalTop(.font(), center, iconSz), valueColor)
        }
        elif row.kind == .Choice and row.checked
        {
            let mark  = Math.Rectangle{leadX, opticalTop(.font(), center, iconSz), iconSz, iconSz}
            let color = row.disabled ? colors.popupItem_DisabledMarker : colors.optionSheet_Marker
            theme.drawSubRect(painter, mark, &rects.btnCheck_CheckedMark, fade(color, opacity))
        }

        // The trailing end says what the row holds and where it leads.
        var right = rect.right() - metrics.optionSheet_RowPadding
        switch row.kind
        {
        case .Link:
            let chevron = theme.icon(.ChevronRight, metrics.chevron_Size)
            right -= chevron.sizeX
            chevron.paint(painter, right, opticalTop(.font(), center, chevron.sizeY), markerColor)
            right -= metrics.menuPopup_IconTextMargin * 0.5
            right = .drawValue(painter, row, right, rect, valueColor)

        case .Choice where row.icon.isValid():
            var icon = row.icon
            icon.sizeX, icon.sizeY = iconSz
            right -= iconSz
            icon.paint(painter, right, opticalTop(.font(), center, iconSz), valueColor)

        case .Toggle:
            right = .paintSwitch(painter, row, rect, right, hot, opacity)

        case .Stepper:
            let parts = .stepperParts(rect)
            .paintStepButton(painter, parts.decrease, increase: false, enabled: row.canDecrease, hot: .pressedStep(-1), opacity: opacity)
            .paintStepButton(painter, parts.increase, increase: true, enabled: row.canIncrease, hot: .pressedStep(1), opacity: opacity)
            var value = row.value
            .drawText(painter, parts.value, &value, textColor, align: .Center)
            right = parts.decrease.x

        default:
            break
        }

        // The wording fills what is left between the two ends.
        let labelX     = leadX + iconSz + metrics.menuPopup_IconTextMargin
        let labelW     = Math.max(right - metrics.menuPopup_IconTextMargin - labelX, 0)
        var label      = row.label
        let labelColor = row.kind == .Action and not row.disabled ? fade(colors.url_Text, opacity) : textColor
        if row.detail.isEmpty()
        {
            .drawText(painter, {labelX, rect.y, labelW, rect.height}, &label, labelColor)
        }
        else
        {
            var detail = row.detail
            let half   = rect.height * 0.5
            .drawText(painter, {labelX, rect.y + 2, labelW, half}, &label, labelColor)
            .drawText(painter, {labelX, rect.y + half - 2, labelW, half}, &detail, valueColor)
        }
    }

    // Writes the current value of `row` right-aligned before `right`, and returns where it starts.
    mtd drawValue(painter: *Painter, row: const *Row, right: f32, rect: Math.Rectangle, color: Color)->f32
    {
        if row.value.isEmpty() do
            return right

        // Measured the way it is drawn, at the density of the surface, so a value that fits is
        // never shortened by the rounding of a second measure.
        var value  = row.value
        let format = .textFormat(color, .Right)
        value.compute()
        Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &value, format, .deviceScale())
        let width = Math.min(Math.ceil(value.boundRect.width) + 1, .themeMetrics().optionSheet_ValueMaxWidth)
        painter.drawRichString({right - width, rect.y, width, rect.height}, &value, format)
        return right - width
    }

    // Paints the switch of a toggle row before `right`, and returns where it starts.
    mtd paintSwitch(painter: *Painter, row: const *Row, rect: Math.Rectangle, right: f32, hot: bool, opacity: f32)->f32
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        let height = Math.round(rect.height * 0.56)
        let width  = Math.round(height * metrics.btnToggle_Width / metrics.btnToggle_Height)
        let track  = Math.Rectangle{right - width, Math.round(rect.vertCenter() - height * 0.5), width, height}

        var ground, border, mark: Color
        switch
        {
        case row.disabled:
            ground = colors.btnToggle_DisabledBk
            border = colors.btnToggle_DisabledBorder
            mark   = colors.btnToggle_DisabledMark

        case hot:
            ground = row.checked ? colors.btnToggle_OnHotBk : colors.btnToggle_OffHotBk
            border = row.checked ? colors.btnToggle_OnHotBorder : colors.btnToggle_OffHotBorder
            mark   = row.checked ? colors.btnToggle_OnHotMark : colors.btnToggle_OffHotMark

        default:
            ground = row.checked ? colors.btnToggle_OnBk : colors.btnToggle_OffBk
            border = row.checked ? colors.btnToggle_OnBorder : colors.btnToggle_OffBorder
            mark   = row.checked ? colors.btnToggle_OnMark : colors.btnToggle_OffMark
        }

        theme.drawSubRect(painter, track, &rects.btnToggle_Bk, fade(ground, opacity))
        theme.drawSubRect(painter, track, &rects.btnToggle_Border, fade(border, opacity))
        let side = track.height
        var knob = Math.Rectangle{track.x, track.y, side, side}
        if row.checked do
            knob.x = track.right() - side
        theme.drawSubRect(painter, knob, &rects.btnToggle_Mark, fade(mark, opacity))
        return track.x
    }

    mtd drawText(painter: *Painter, rect: Math.Rectangle, text: *RichString, color: Color, align = StringHorzAlignment.Left, bold = false)
    {
        if rect.width <= 0 do
            return
        var format = .textFormat(color, align)
        if bold do
            format.fontStyle = .Bold
        painter.drawRichString(rect, text, format)
    }

    mtd textFormat(color: Color, align: StringHorzAlignment)->RichStringFormat
    {
        var result: #returntype
        .theme().setTextColors(&result, color)
        result.horzAlignment = align
        result.vertAlignment = .OpticalCenter
        result.flags         = .Ellipsis
        result.font          = .font()
        return result
    }
}

// Scales the alpha of `color` by `opacity`.
private func fade(color: Color, opacity: f32)->Color => opacity >= 1 ? color : color.withAlpha(cast(u8, color.a * Math.saturate(opacity)))
