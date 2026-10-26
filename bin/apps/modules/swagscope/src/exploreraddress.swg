#global internal

using Core, Gui, Pixel

// The field that names the explored location, the way a file browser's address bar does.
//
// It reads as the path, one level per segment, until the reader asks to type: a click past the
// last segment, or Ctrl+L, turns it into a box holding the whole location, selected, so a path can
// be copied out or pasted in. Enter goes there; Escape, or the focus leaving, puts the path back.
struct ExplorerAddress
{
    using wnd: Wnd

    late
    {
        explorer:   *Explorer
        pathScroll: *ScrollWnd
        breadcrumb: *BreadcrumbCtrl
        edit:       *EditBox
        refresh:    *IconButton
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
        let metrics     = parent.themeMetrics()
        let compactSize = themeCompactButtonSize(metrics)
        with let result = Wnd.create'ExplorerAddress(parent, "scope.explorer.address")
        {
            .explorer        = explorer
            .backgroundStyle = .Transparent
            .padding.x       = 4
        }

        with result.refresh = IconButton.create(result, result.theme().icon(.Update, themeRowIconSize(metrics)), {0, 0, compactSize, compactSize})
        {
            .dockStyle  = .Right
            .sigPressed += func|explorer|(_) { explorer.forceRefresh() }
        }

        with result.pathScroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle = .Center
            .updateFlags(.CompactBars | .TransparentBars)
            .setFrameFlags(remove: .Borders)
        }

        with result.breadcrumb = BreadcrumbCtrl.create(result.pathScroll)
        {
            .backgroundStyle = .Transparent
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
    // Draws the ground of a field under the path, and the focus edge of one while it is typed in.
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let rects   = .themeRects()
        let colors  = .themeColors()
        .theme().drawSubRect(painter, .clientRect(), &rects.edit_SquareBk, colors.edit_Bk)
        if .edit.isLocallyVisible() do
            .theme().drawSubRect(painter, .clientRect(), &rects.edit_SquareBorder, colors.edit_FocusBorder)
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
