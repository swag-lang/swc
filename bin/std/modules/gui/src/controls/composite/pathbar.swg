#global public

using Core, Pixel

// Shows a location as clickable breadcrumb levels or as an editable full path.
//
// The host owns navigation and fills child menus through [[Gui.BreadcrumbCtrl.sigFillMenu]].
// Clicking the current level or the empty area edits the path; Enter submits it and Escape
// restores the breadcrumbs. Losing focus cancels editing without submitting.
struct PathBar
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            late breadcrumb: *BreadcrumbCtrl     // Levels and child menus; tags carry host-defined locations.
            late pathScroll: *ScrollWnd          // Viewport keeping the current level visible.
            late edit:       *EditBox            // Full path while editing.
        }

        sigNavigate:     SigArray'func||(*Wnd, string)     // Requests navigation to a breadcrumb tag.
        sigSubmitted:    SigArray'func||(*Wnd, string)     // Requests navigation to the submitted full path.
        sigEditFinished: SigArray'func||(*Wnd)             // Enter or Escape finished editing; the host may restore focus.
    }

    location:    String
    returnFocus: bool
}

impl PathBar
{
    // Creates a path bar without a location; call [[Gui.PathBar.setPath]] to populate it.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*PathBar
    {
        with let result = Wnd.create'PathBar(parent, id)
        {
            .backgroundStyle = .Transparent
        }

        with result.pathScroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle = .Center
            .updateFlags(.TransparentBars | .DisableHorizontal)
            .setFrameFlags(remove: .Borders)
        }

        with result.breadcrumb = BreadcrumbCtrl.create(result.pathScroll)
        {
            .backgroundStyle = .Transparent
            .fitToWidth      = true
            .style.setFont(result.theme().createDefaultFontFs(result.themeMetrics().defaultFontSize), .Regular)
            .sigItemPressed += func|result|(path, index)
            {
                if index + 1 == path.items.count do
                    result.beginEdit()
                else do
                    result.sigNavigate.call(result, path.items[index].tag.toString())
            }

            .sigMenuSelected += func|result|(_, _, path)
            {
                result.sigNavigate.call(result, path.toString())
            }

            .sigEmptyPressed += func|result|(_)
            {
                result.beginEdit()
            }
        }

        result.pathScroll.setView(result.breadcrumb)

        with result.edit = EditBox.create(result, "", flags: .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Center
            .hide()
            .sigSubmitted += func|result|(edit)
            {
                result.returnFocus = true
                result.sigSubmitted.call(result, edit.text())
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

    // Sets the full editable location without changing host-defined breadcrumb levels.
    mtd setText(path: string)
    {
        .location = path
        .breadcrumb.toolTip = path
    }

    // Builds all levels of a slash-separated path, including its root and current folder.
    //
    // This operation does no filesystem I/O. Each level's tag is its absolute or relative path.
    mtd setPath(path: string)
    {
        .setText(path)
        .breadcrumb.clear()
        var normalized = String.from(path)
        Path.normalize(&normalized)
        var ancestors: Array'String
        var current = normalized.toString()
        while current.count
        {
            ancestors.add(current)
            let parent = Path.directoryName(current) orelse ""
            if not parent.count or parent == current do
                break
            current = parent
        }

        for ancestor in ancestors.reversed()
        {
            let full = ancestor.toString()
            let name = Path.fileName(full) orelse full
            .breadcrumb.addItem(name.count ? name : full, tag: full)
        }

        .refreshPath()
    }

    // Recomputes level bounds after the host changes them, keeping the current folder in view.
    mtd refreshPath()
    {
        if .breadcrumb == null do
            return
        .breadcrumb.layout()
        .pathScroll.setScrollSize(0, 0)
        .pathScroll.setScrollPos(0, 0)
        .breadcrumb.invalidate()
    }

    // Selects the full location and gives the keyboard to the editor, without submitting it.
    mtd beginEdit()
    {
        if .edit.isLocallyVisible() do
            return
        .returnFocus = false
        .edit.setText(.location, notify: false)
        .pathScroll.hide()
        .edit.show()
        .applyLayout()
        .edit.setFocus()
        .edit.selectAll()
    }

    // Cancels editing and restores the breadcrumb view.
    mtd endEdit()
    {
        if not .edit.isLocallyVisible() do
            return
        .edit.hide()
        .pathScroll.show()
        .applyLayout()
        .refreshPath()
        .invalidate()
        if .returnFocus
        {
            .returnFocus = false
            .sigEditFinished.call(me)
        }
    }
}

impl IWnd for PathBar
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .applyLayout()
        .refreshPath()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Pressed and evt.button == .Left do
            .beginEdit()
        else do
            evt.accepted = false
    }
}
