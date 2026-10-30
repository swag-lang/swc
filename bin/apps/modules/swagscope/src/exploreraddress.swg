#global internal

using Core, Gui, Pixel

// The breadcrumb that names the explored location above the title of the page.
//
// It reads as the path, one level per segment, with no ground of its own, until the reader asks
// to type: a click past the last segment, or Ctrl+L, turns it into a field holding the whole
// location, selected, so a path can be copied out or pasted in. Enter goes there; Escape, or the
// focus leaving, puts the path back.
struct ExplorerAddress
{
    using wnd: Wnd

    late
    {
        explorer:   *Explorer
        navigation: *StackLayoutCtrl
        actions:    *StackLayoutCtrl
        pathScroll: *ScrollWnd
        breadcrumb: *BreadcrumbCtrl
        edit:       *EditBox
    }

    returnFocus: bool     // Whether ending the edit gives the keyboard back to the listing.
}

impl ExplorerAddress
{
    // Room kept past the last segment of a long path, so there is always somewhere to click to
    // type one.
    const TypingRoom = 32.0

    func create(parent: *Wnd, explorer: *Explorer)->*ExplorerAddress
    {
        with let result = Wnd.create'ExplorerAddress(parent, "scope.explorer.address")
        {
            .explorer        = explorer
            .backgroundStyle = .Transparent
        }

        // Navigation stays next to the location, including while a path is being typed.
        with result.navigation = StackLayoutCtrl.create(result, .Left)
        {
            .dockStyle       = .Left
            .backgroundStyle = .Transparent
            .margin.z        = 8
            .spacing         = 4
        }

        for command, index in [ViewerCommands.Back, ViewerCommands.Forward, ViewerCommands.Up]
        {
            let glyphs      = [ThemeIcons.ChevronLeft, .ChevronRight, .ParentFolder]
            with let button = IconButton.create(result.navigation,
                                                result.theme().icon(glyphs[index], result.themeMetrics().menuPopup_IconSize),
                                                {0, 0, Explorer.AddressHeight, Explorer.AddressHeight},
                                                command,
                                                .IconOnly)
            {
                .layoutSpec.alignY = .Center
                .setForm(.RoundedRectangle)
            }
        }

        // Repeated folder actions stay beside the path, with the same state as their lens rows.
        with result.actions = StackLayoutCtrl.create(result, .Left)
        {
            .dockStyle       = .Right
            .backgroundStyle = .Transparent
            .spacing         = result.themeMetrics().infoSheet_LineGap
            .margin.x        = result.themeMetrics().infoSheet_BlockGap
        }

        for command, index in [ViewerCommands.Refresh, ViewerCommands.Find, ViewerCommands.Information]
        {
            let glyphs      = [ThemeIcons.Update, .Search, .Information]
            with let button = IconButton.create(result.actions,
                                                result.theme().icon(glyphs[index], result.themeMetrics().menuPopup_IconSize),
                                                {0, 0, Explorer.ToolHeight, Explorer.ToolHeight},
                                                command,
                                                .IconOnly)
            {
                .layoutSpec.alignY = .Center
                .setForm(.RoundedRectangle)
            }
        }

        with result.pathScroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle = .Center
            .updateFlags(.TransparentBars)
            .setFrameFlags(remove: .Borders)
        }

        with result.breadcrumb = BreadcrumbCtrl.create(result.pathScroll)
        {
            .backgroundStyle = .Transparent
            .quiet = true
            .setLayoutMetrics(0, 4, 6)
            .style.setFont(result.theme().createDefaultFont(13), .Regular)
            .sigItemPressed  += func|explorer|(path, index) { explorer.navigateBreadcrumb(path.items[index].tag) }
            .sigFillMenu     += func|explorer|(_, index, menu) { explorer.fillBreadcrumbMenu(index, menu) }
            .sigMenuSelected += func|explorer|(_, _, path) { explorer.navigateBreadcrumb(path) }
            .sigEmptyPressed += func|result|(_) { result.beginEdit() }
        }

        result.pathScroll.setView(result.breadcrumb)

        with result.edit = EditBox.create(result, "", flags: .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Center
            .setForm(.Transparent)
            .hide()
            .sigSubmitted += func|result|(edit)
            {
                result.returnFocus = true
                result.explorer.navigateTyped(edit.text())
            }

            .sigCancelled += func|result|(_)
            {
                result.returnFocus = true
            }

            .sigFocusLost += func|result|(_)
            {
                result.endEdit()
            }
        }

        return result
    }

    // Lays the segments out again and keeps the end of the path in view.
    mtd refreshPath()
    {
        .breadcrumb.layout()
        let width = .breadcrumb.items.isEmpty() ? 0.0 : .breadcrumb.items.back().arrowRect.right() + TypingRoom
        .pathScroll.setScrollSize(width, 0)
        .pathScroll.setScrollPos(width, 0)
    }

    // Shows the whole location as text, selected, with the keyboard in it.
    mtd beginEdit()
    {
        if .edit.isLocallyVisible() do
            return
        .returnFocus = false
        .edit.setText(.explorer.locationText(), notify: false)
        .pathScroll.hide()
        .edit.show()
        .applyLayout()
        .edit.setFocus()
        .edit.selectAll()
        .invalidate()
    }

    // Goes back to the segments, whichever way the edit ended.
    mtd endEdit()
    {
        if not .edit.isLocallyVisible() do
            return
        .edit.hide()
        .pathScroll.show()
        .applyLayout()
        .invalidate()
        if .returnFocus
        {
            .returnFocus = false
            .explorer.focusContent()
        }
    }
}

impl IWnd for ExplorerAddress
{
    // Draws the ground and the focus edge of a field only while the path is typed in; the
    // segments themselves stand on the page.
    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .edit.isLocallyVisible() do
            return
        let painter = evt.paintContext.painter
        let rects   = .themeRects()
        let colors  = .themeColors()
        .theme().drawSubRect(painter, .edit.position, &rects.edit_SquareBk, colors.edit_Bk)
        .theme().drawSubRect(painter, .edit.position, &rects.edit_SquareBorder, colors.edit_FocusBorder)
    }

    // The air around the segments belongs to the field too: pressing it starts typing.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        .beginEdit()
    }
}
