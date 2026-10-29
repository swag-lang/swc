#global public

using Core, File, Directory

// Stores linear string locations for back and forward navigation.
//
// Pushing a location after moving backward discards the abandoned forward branch.
struct NavigationHistory
{
    public readonly
    {
        entries: Array'String     // Locations in visit order.
        index = Swag.U64.Max      // Current entry index, or `Swag.U64.Max` when empty.
    }
}

impl NavigationHistory
{
    // Removes every location and resets the current position.
    mtd clear()
    {
        .entries.clear()
        .index = Swag.U64.Max
    }

    // Appends `path`, discarding any forward branch after the current position.
    mtd push(path: string)
    {
        if .index != Swag.U64.Max and .entries[.index] == path do
            return
        while .index != Swag.U64.Max and .entries.count > .index + 1 do
            .entries.removeBack()
        .entries.add(String.from(path))
        .index = .entries.count - 1
    }

    // Returns whether a location exists before the current one.
    mtd canGoBack()->bool => .index != Swag.U64.Max and .index > 0

    // Returns whether a location exists after the current one.
    mtd canGoForward()->bool => .index != Swag.U64.Max and .index + 1 < .entries.count

    // Moves backward and returns the new current location.
    //
    // The caller must first check [[Gui.NavigationHistory.canGoBack]].
    mtd goBack()->String
    {
        Swag.assert(.canGoBack(), "file-browser history has no previous folder")
        .index -= 1
        return .entries[.index]
    }

    // Moves forward and returns the new current location.
    //
    // The caller must first check [[Gui.NavigationHistory.canGoForward]].
    mtd goForward()->String
    {
        Swag.assert(.canGoForward(), "file-browser history has no next folder")
        .index += 1
        return .entries[.index]
    }
}

// One stop of a row of text the browser lays out itself: a place, or a step of the path.
struct FileBrowserStop
{
    public
    {
        name: String             // Words shown for the stop.
        path: String             // Folder the stop leads to.
        rect: Math.Rectangle     // Where the words stand, in local coordinates.
    }
}

// The places of a file browser, set as text tabs: preferred locations, built-in folders, then drives.
//
// The place the current folder lies in carries the Arc underline; a click browses to a place.
struct FilePlacesBar
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.
    }

    late browser:    *FileBrowserCtrl          // Browser the places lead.
    stops:           Array'FileBrowserStop     // Places in display order.
    private primaryCount: u64                  // Preferred locations kept on the row before built-in folders.
    hotIdx = Swag.U64.Max                      // Place under the pointer.
    visibleCount:    u64                       // Places that fit before the overflow button.
    moreButton: *IconButton?                   // Opens built-in folders, drives and preferred places that do not fit.
}

// The path of the current folder, written before the filter in the path field of a file browser.
//
// The steps start at the place the folder lies in, or at its root; a click on a step browses
// there. Steps that would take more than half the field are folded into an ellipsis.
struct FileCrumbs
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.
    }

    late browser: *FileBrowserCtrl          // Browser the steps lead.
    stops:        Array'FileBrowserStop     // Steps in display order, the first possibly an ellipsis.
    hotIdx = Swag.U64.Max     // Step under the pointer.
}

// Browses folders with places as text tabs, a path field that filters, a quiet file list, and name and type editors.
struct FileBrowserCtrl
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            options:       FileDlgOptions      // Effective browsing and selection options.
            currentFolder: String              // Normalized folder currently displayed.
            placesBar:     *FilePlacesBar?     // Places, unless [[Gui.FileDlgOptions.showLocationsPane]] is off.

            late
            {
                listCtrl:        *ListCtrl       // Sortable file and folder list.
                pathField:       *EditBox        // The current folder as a path, then a filter or a path typed after it.
                editFile:        *EditBox        // Name of the file a save creates; in the other modes, the chosen names.
                comboType:       *ComboBox       // Active file-type filter selector.
                choiceLabel:     *Label          // What the box will answer with, in faint mono beside the type filter.
                upButton:        *IconButton     // Navigates to the parent folder.
                historyButton:   *IconButton     // Opens the recent-folders drop-down menu.
                newFolderButton: *IconButton     // Creates a folder in the current location.
            }
        }

        sigAccepted:           SigArray'func||(*Wnd)     // Emitted when the current selection is activated.
        sigFolderChanged:      SigArray'func||(*Wnd)     // Emitted after [[Gui.FileBrowserCtrl.currentFolder]] changes.
        sigNewFolderRequested: SigArray'func||(*Wnd)     // Emitted when the user requests a new folder.
        sigChoiceChanged:      SigArray'func||(*Wnd)     // Emitted after what the browser would answer with changes.
    }

    late crumbs:    *FileCrumbs           // Path written at the start of the path field.
    late typeRow:   *Wnd                  // Row holding the type filter when the browser keeps it.
    currentEntries: Array'FileInfo        // Filesystem entries backing visible rows.
    history:        NavigationHistory     // Folder-navigation history.
}

impl IWnd for FilePlacesBar
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrange()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let font    = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        let current = .currentIndex()

        // The chosen place reads in the body ink over the Arc underline; the others stay soft, and
        // the one under the pointer comes up to the body ink without the underline.
        for idx in 0 until .visibleCount
        {
            let stop   = .stops[idx]
            let chosen = idx == current
            let color  = chosen or idx == .hotIdx ? colors.text : colors.softText
            painter.drawString(stop.rect.x, font.opticalLineTop(stop.rect.vertCenter()), stop.name.toString(), font, color)
            if chosen do
                painter.fillRect(Math.Rectangle{stop.rect.x, .clientRect().bottom() - 2, stop.rect.width, 2}, colors.arc)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let hit = hitStop(.stops.toSlice()[until .visibleCount], .surfaceToLocal(evt.surfacePos))
        switch evt.kind
        {
        case .Move:
            if hit != .hotIdx
            {
                .hotIdx = hit
                .invalidate()
            }

        case .Leave:
            .hotIdx = Swag.U64.Max
            .invalidate()

        case .Pressed:
            if evt.button == .Left and hit != Swag.U64.Max do
                .browser.setCurrentFolder(.stops[hit].path)
        }
    }
}

impl FilePlacesBar
{
    // Opens the built-in folders, drives and any preferred places that do not fit in the row.
    internal mtd openOverflowMenu()
    {
        let menu = MenuCtrl.createPopup(.browser)
        for idx in .visibleCount until .stops.count
        {
            let stop = .stops[idx]
            var icon = .theme().fileGlyph("", isDirectory: true)
            icon.color = .themeColors().arc
            discard menu.addItem(stop.name.toString(), stop.path.toString(), icon)
        }

        if menu.items.isEmpty()
        {
            menu.destroy()
            return
        }

        let chosen = menu.doModal(unwrap .moreButton, autoDestroy: true) orelse ""
        if chosen.count do
            .browser.setCurrentFolder(chosen)
    }

    // Returns the place the current folder lies in: the deepest one whose path starts it, or `Swag.U64.Max`.
    mtd currentIndex()->u64
    {
        var result = Swag.U64.Max
        var length = 0'u64
        for &stop, idx in .stops
        {
            if stop.path.length > length and isInside(.browser.currentFolder.toString(), stop.path.toString())
            {
                result = idx
                length = stop.path.length
            }
        }

        return result
    }

    // Places the words of every place from the leading edge, a gap apart.
    mtd arrange()
    {
        if not .moreButton do
            return

        let font        = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        let height      = .clientRect().height
        let buttonWidth = .moreButton.position.width
        var totalWidth  = 0'f32
        for idx in 0 until .primaryCount
        {
            let stop = .stops[idx]
            totalWidth += Painter.measureString(stop.name.toString(), font).width + .themeMetrics().fileBrowser_PlaceGap
        }

        if totalWidth and .primaryCount do
            totalWidth -= .themeMetrics().fileBrowser_PlaceGap

        if .primaryCount == .stops.count and totalWidth <= .clientRect().width
        {
            .moreButton.hide()
            .visibleCount = .stops.count
        }
        else
        {
            .moreButton.show()
            let available = Math.max(0'f32, .clientRect().width - buttonWidth - .themeMetrics().fileBrowser_PlaceGap)
            .visibleCount = 0
            var used = 0'f32
            for idx in 0 until .primaryCount
            {
                let stop  = .stops[idx]
                let width = Painter.measureString(stop.name.toString(), font).width
                if used + width > available do
                    break
                used += width + .themeMetrics().fileBrowser_PlaceGap
                .visibleCount += 1
            }
        }

        var x = 0'f32
        for idx in 0 until .visibleCount
        {
            let stop  = .stops[idx]
            let width = Painter.measureString(stop.name.toString(), font).width
            .stops[idx].rect = Math.Rectangle{x, 0, width, height - 2}
            x += width + .themeMetrics().fileBrowser_PlaceGap
        }

        .updateSelection()
        .invalidate()
    }

    // Marks the overflow control when the current folder belongs to a hidden place.
    internal mtd updateSelection()
    {
        let current = .currentIndex()
        .moreButton?.setIconColor(current != Swag.U64.Max and current >= .visibleCount ? .themeColors().arc : Color{})
    }

    // Adds a place leading to `path`, named `name`.
    mtd addPlace(name, path: string)
    {
        var normalized = String.from(path)
        Path.normalize(&normalized)
        .stops.add({name: String.from(name), path: normalized})
    }
}

impl IWnd for FileCrumbs
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let font    = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        for &stop, idx in .stops
        {
            let y = font.opticalLineTop(stop.rect.vertCenter())
            painter.drawString(stop.rect.x, y, stop.name.toString(), font, idx == .hotIdx ? colors.softText : colors.faintText)
            painter.drawString(stop.rect.right(), y, " / ", font, colors.faintText)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let hit = hitStop(.stops.toSlice(), .surfaceToLocal(evt.surfacePos))
        switch evt.kind
        {
        case .Move:
            if hit != .hotIdx
            {
                .hotIdx = hit
                if hit == Swag.U64.Max do
                    .cursor.clear()
                else do
                    .cursor = Cursor.from(CursorShape.Hand)
                .invalidate()
            }

        case .Leave:
            .hotIdx = Swag.U64.Max
            .invalidate()

        case .Pressed:
            if evt.button == .Left and hit != Swag.U64.Max do
                .browser.setCurrentFolder(.stops[hit].path)
        }
    }
}

impl FileCrumbs
{
    // Rebuilds the steps of the current folder and returns the width they take, separators included.
    //
    // At most `maximum` wide: the steps after the first are folded into an ellipsis, oldest first,
    // until the rest fits.
    mtd rebuild(maximum: f32)->f32
    {
        .stops.clear()
        .hotIdx = Swag.U64.Max

        let folder = .browser.currentFolder.toString()
        var start  = 0'u64
        let places = .browser.placesBar
        if places
        {
            let place = places.currentIndex()
            if place != Swag.U64.Max
            {
                let stop = &places.stops[place]
                .stops.add({name: stop.name, path: stop.path})
                start = stop.path.length
            }
        }

        // The remaining folders, each step leading to the path up to it.
        var path = String.from(folder[until start])
        for part in Tokenize.split(folder[start until folder.count], '/'rune) where part.count
        {
            if not path.isEmpty() and path.back() != '/' do
                path += '/'u8
            path += part
            .stops.add({name: String.from(part), path: path})
        }

        // Fold the oldest steps behind the first into one ellipsis until the path fits.
        let font  = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        let slash = Painter.measureString(" / ", font).width
        var total = 0'f32
        for &stop in .stops do
            total += Painter.measureString(stop.name.toString(), font).width + slash
        if total > maximum and .stops.count > 2
        {
            total -= Painter.measureString(.stops[1].name.toString(), font).width
            total += Painter.measureString("…", font).width
            .stops[1].name = String.from("…")

            // The ellipsis leads to the deepest folder it hides.
            while total > maximum and .stops.count > 3
            {
                total -= Painter.measureString(.stops[2].name.toString(), font).width + slash
                .stops[1].path = .stops[2].path
                .stops.removeAtOrdered(2)
            }
        }

        let height = .clientRect().height
        var x      = 0'f32
        for &stop in .stops
        {
            let width = Painter.measureString(stop.name.toString(), font).width
            stop.rect = Math.Rectangle{x, 0, width, height}
            x         += width + slash
        }

        .invalidate()
        return x
    }
}

// Reports whether `folder` is `place` or lies under it; both are normalized.
private func isInside(folder, place: string)->bool
{
    if not place.count or not Utf8.startsWith(folder, place, .Latin1NoCase) do
        return false
    if folder.count == place.count or place[place.count - 1] == '/'u8 do
        return true
    return folder[place.count] == '/'u8
}

// Returns the stop whose words are under `pos`, or `Swag.U64.Max`.
private func hitStop(stops: const [..] FileBrowserStop, pos: Math.Point)->u64
{
    for &stop, idx in stops where pos.x >= stop.rect.x and pos.x < stop.rect.right() do
        return idx
    return Swag.U64.Max
}

private impl FileBrowserCtrl
{
    mtd updateNavigationState()
    {
        .historyButton.enable(.options.state != null and not .options.state.recentFolders.isEmpty())
        let parent = Path.directoryName(.currentFolder.toString()) orelse ""
        .upButton.enable(parent.count != 0 and parent != .currentFolder.toString())
    }

    // Opens the recent-folders menu below the history button and navigates to the choice.
    mtd openRecentMenu()
    {
        let state = .options.state
        if not state do
            return

        let menu = MenuCtrl.createPopup(me)
        for &recent in state.recentFolders
        {
            if not Directory.exists(recent.toString()) do
                continue
            var name = Path.fileName(recent.toString()) orelse ""
            if not name.count do
                name = recent.toString()
            var icon = .theme().fileGlyph(name, isDirectory: true)
            icon.color = .themeColors().softText
            discard menu.addItem(name, recent.toString(), icon)
        }

        // Nothing to show: drop the empty popup rather than flashing an empty box.
        if menu.items.isEmpty()
        {
            menu.destroy()
            return
        }

        let sel    = menu.doModal(.historyButton, autoDestroy: true)
        let chosen = sel orelse ""
        if chosen.count do
            .setCurrentFolder(chosen)
    }

    mtd showFolder(folder: string)->bool
    {
        if not folder.count or not Directory.exists(folder) do
            return false

        var normalized = String.from(folder)
        Path.normalize(&normalized)
        if normalized.back() == '/' and normalized.length > Path.rootLength(normalized.toString()) do
            normalized.removeBack()
        if .currentFolder == normalized do
            return true

        .currentFolder = #move normalized
        .pathField.setText(null, notify: false)
        .placesBar?.invalidate()
        .placesBar?.updateSelection()
        .placeCrumbs()
        .fillFileList()
        .sigFolderChanged.call(me)
        return true
    }

    // Writes the path of the current folder at the start of the path field, and starts the typing after it.
    mtd placeCrumbs()
    {
        let field = .pathField
        let inset = field.padding.x
        let room  = Math.max(field.position.width * 0.5, 0)
        .crumbs.setPosition(Math.Rectangle{inset, 0, room, field.position.height})
        let width = .crumbs.rebuild(room)
        .crumbs.resize(width, field.position.height)
        field.setLeadingMargin(width)
    }

    // Reports whether what is typed in the path field names a path rather than filters the list.
    mtd typedIsPath()->bool
    {
        let typed = .pathField.text()
        return Utf8.indexOfAny(typed, "/\\:") != Swag.U64.Max
    }

    // Answers Enter in the path field: a typed path browses or chooses, a filter takes its first row.
    mtd submitPath()
    {
        var typed = String.from(.pathField.text())
        typed.trim()
        if typed.isEmpty() do
            return

        if .typedIsPath()
        {
            var candidate: String
            if Path.rootLength(typed.toString()) > 0 do
                candidate = typed
            else do
                candidate = Path.combine(.currentFolder, typed.toString())

            if Directory.exists(candidate)
            {
                .setCurrentFolder(candidate.toString())
                return
            }

            if .options.mode != .SelectFolder and File.exists(candidate)
            {
                .setCurrentFolder(Path.directoryName(candidate.toString()) orelse "")
                .editFile.setText(Path.fileName(candidate.toString()) orelse "")
                .sigAccepted.call(me)
            }

            return
        }

        if .listCtrl.lines.isEmpty() do
            return
        .listCtrl.selectLine(0)
        let fi = cast(const *FileInfo, unwrap .listCtrl.lines[0]!.userData0)
        if fi.isDirectory() do
            .setCurrentFolder(fi.fullName)
        elif .options.mode != .SelectFolder do
            .sigAccepted.call(me)
    }

    // Answers the browsing keys wherever the keyboard is in the browser, and reports whether `key` was one.
    mtd browseKey(key: Input.Key, modifiers: Input.KeyModifiers)->bool
    {
        switch key
        {
        case .BrowserBack:
            discard .goBack()
            return true

        case .BrowserForward:
            discard .goForward()
            return true

        case .BrowserRefresh, .F5:
            .refresh()
            return true

        case .Left where modifiers.equals(.Alt):
            discard .goBack()
            return true

        case .Right where modifiers.equals(.Alt):
            discard .goForward()
            return true

        case .Up where modifiers.equals(.Alt):
            discard .goUp()
            return true
        }

        return false
    }

    // Checks exactly the checkable rows that are selected.
    mtd syncChecks()
    {
        if .options.mode != .SelectFiles do
            return
        let selected = .listCtrl.selectedLines()
        for line, idx in .listCtrl.lines where line and line.canCheck
        {
            var chosen = false
            for s in selected where s == line do
                chosen = true
            .listCtrl.setLineChecked(cast(u32, idx), chosen, notify: false)
        }
    }

    // Writes what the box will answer with beside the type filter, and tells the host.
    //
    // Picking a folder, it is the path chosen: the selected folder, or the folder shown. Picking
    // several files, it is their count and weight.
    mtd updateChoice()
    {
        var text: String
        switch .options.mode
        {
        case .SelectFolder:
            text = .displayPath()
            let name = .editFile.text()
            if name.count
            {
                text += " / "
                text += name
            }

        case .SelectFiles:
            var count = 0
            var bytes = 0'u64
            for line in .listCtrl.selectedLines()
            {
                let fi = cast(const *FileInfo, unwrap line!.userData0)
                if fi.isDirectory() do
                    continue
                count += 1
                bytes += fi.size
            }

            if count do
                text = Format.toString(strings().browser_Chosen, count, Format.byteSize(bytes))
        }

        .choiceLabel.setText(text.toString())
        .sigChoiceChanged.call(me)
    }

    // Answers the keys the path field leaves to the browser, and keeps the written path fitted to the field.
    mtd handlePathEvent(evt: IEvent)->bool
    {
        switch evt
        {
        case ResizeEvent:
            .placeCrumbs()

        case KeyEvent as key:
            if key.kind != .Pressed do
                break

            // Down leaves the field for the rows it filtered; Backspace at its start climbs.
            if key.key == .Down and key.modifiers.equals(.None)
            {
                .listCtrl.setFocus()
                if not .listCtrl.lines.isEmpty() and not .listCtrl.selectedLine() do
                    .listCtrl.selectLine(0)
                return true
            }

            if key.key == .Back and key.modifiers.equals(.None) and .pathField.text().count == 0
            {
                discard .goUp()
                return true
            }

            return .browseKey(key.key, key.modifiers)
        }

        return false
    }

    mtd createPathRow(parent: *Wnd)
    {
        let metrics = .themeMetrics()
        let side    = metrics.control_DialogHeight

        with let row = Wnd.create'Wnd(parent, {0, 0, 0, side})
        {
            .dockStyle = .Top
            if me.placesBar do
                .margin.y = metrics.fileBrowser_RowGap
        }

        // Quiet glyphs at the end of the field, each named by its tooltip.
        let iconSize = metrics.fileBrowser_GlyphSize
        with .newFolderButton = IconButton.create(row, .theme().icon(.Plus, iconSize), {0, 0, side, side})
        {
            .dockStyle  = .Right
            .toolTip    = strings().browser_NewFolder
            .sigPressed += func|fileBrowser = me|(_) { fileBrowser.sigNewFolderRequested.call(fileBrowser) }
        }

        with .historyButton = IconButton.create(row, .theme().icon(.History, iconSize), {0, 0, side, side})
        {
            .dockStyle  = .Right
            .toolTip    = strings().browser_TipRecent
            .sigPressed += func|fileBrowser = me|(_) { fileBrowser.openRecentMenu() }

            // Without reusable state there is never a history to show.
            if not me.options.state do
                .hide()
        }

        with .upButton = IconButton.create(row, .theme().icon(.ParentFolder, iconSize), {0, 0, side, side})
        {
            .dockStyle  = .Right
            .margin.z   = metrics.fileBrowser_GlyphGap
            .toolTip    = strings().browser_TipUp
            .sigPressed += func|fileBrowser = me|(_) { discard fileBrowser.goUp() }
        }

        with .pathField = EditBox.create(row, "")
        {
            .dockStyle = .Center
            .setPlaceholder(strings().browser_FilterHint)
            .sigTextChanged += func|fileBrowser = me|(_) { fileBrowser.fillFileList() }

            .sigSubmitted += func|fileBrowser = me|(_) { fileBrowser.submitPath() }
            .hookOnEvent  = func|fileBrowser = me|(_, evt) => fileBrowser.handlePathEvent(evt)
        }

        .crumbs             = Wnd.create'FileCrumbs(.pathField, "", {})
        .crumbs.browser     = me
        .crumbs.focusPolicy = .Click
    }

    mtd createFileList(view: *Wnd)
    {
        let metrics = .themeMetrics()
        with me.listCtrl = ListCtrl.createMultiColumns(view)
        {
            .setSelectionMode(me.options.mode == FileDlgMode.SelectFiles ? ListSelectionMode.Multi : ListSelectionMode.Single)
            .dockStyle = .Center
            .margin.y  = metrics.fileBrowser_RowGap
            .updateFlags(.HotTrack | .StretchFirstColumn | .Ellipsis)
            .setLineHeight(metrics.fileBrowser_LineHeight)
            .backgroundStyle = .Transparent

            // NOTE: both branches are kept explicitly f32. A runtime conditional
            // whose unified result is integer, fed to an f32 parameter, is currently
            // mis-lowered to a bit-reinterpret (see reference_conditional_int_to_float_miscompile).
            .addColumn(strings().browser_ColName, me.options.state ? cast(f32, me.options.state.nameColumnWidth) : 220.0)
            .addColumn(strings().browser_ColModified, me.options.state ? cast(f32, me.options.state.modifiedColumnWidth) : 130.0)
            .addColumn(strings().browser_ColSize, me.options.state ? cast(f32, me.options.state.sizeColumnWidth) : 90.0, align: .Right)
            .header.form = .Transparent

            // The rows say what they are without a header: a name, a faint mono date and size.
            .header.hide()

            // A key the browsing gesture claims is marked handled, so the list does not read it a
            // second time as a movement of its own: Enter opens what is selected instead of also
            // folding the row, and Alt and an arrow browse instead of also folding it.
            .sigKeyPressed += func|fileBrowser = me|(list, evt)
            {
                if fileBrowser.browseKey(evt.key, evt.modifiers)
                {
                    evt.accepted = true
                    return
                }

                switch evt.key
                {
                case .Back:
                    if evt.modifiers.equals(.None)
                    {
                        if not fileBrowser.goBack() do
                            discard fileBrowser.goUp()
                        evt.accepted = true
                    }

                case .Enter:
                    let l = list.focusedLine()
                    if not l do
                        break
                    let fi = cast(const *FileInfo, unwrap l.userData0)
                    if fi.isDirectory()
                    {
                        fileBrowser.setCurrentFolder(fi.fullName)
                        evt.accepted = true
                    }
                    elif fileBrowser.options.mode != .SelectFolder
                    {
                        fileBrowser.sigAccepted.call(fileBrowser)
                        list.setFocus()
                        evt.accepted = true
                    }
                }
            }

            .sigLeftDoubleClicked += func|fileBrowser = me|(list, _)
            {
                var l = list.selectedLine()
                if not l do
                    return
                var fi = cast(const *FileInfo, unwrap l.userData0)
                if fi.isDirectory()
                {
                    fileBrowser.setCurrentFolder(fi.fullName)
                }
                elif fileBrowser.options.mode != .SelectFolder
                {
                    fileBrowser.sigAccepted.call(fileBrowser)
                    list.setFocus()
                }
            }

            .sigSelectionChanged += func|fileBrowser = me|(list)
            {
                var sel = list.selectedLines()
                var txt: String
                for l in sel
                {
                    let fi = cast(const *FileInfo, unwrap l!.userData0)
                    if fi.isDirectory()
                    {
                        if fileBrowser.options.mode != .SelectFolder do
                            continue
                    }
                    else
                    {
                        if fileBrowser.options.mode == .SelectFolder do
                            continue
                    }

                    if not txt.isEmpty() do
                        txt += ";"
                    txt += Path.fileName(fi.fullName)
                }

                if not txt.isEmpty() or fileBrowser.options.mode == .SelectFolder do
                    fileBrowser.editFile.setText(txt)
                fileBrowser.syncChecks()
                fileBrowser.updateChoice()
            }

            // A checkbox is another way to hold the same choice.
            .sigCheckedChanged += func|fileBrowser = me|(list)
            {
                for line, idx in list.lines where line and line.canCheck do
                    list.selectLine(cast(u32, idx), list.isLineChecked(cast(u32, idx)))
                discard fileBrowser
            }

            .compareLines = func(l1, l2, col, down)
            {
                if not l1 or not l2 do
                    return 0

                var fi1 = cast(*FileInfo, unwrap l1.userData0)
                var fi2 = cast(*FileInfo, unwrap l2.userData0)
                if fi1.isDirectory() and not fi2.isDirectory() do
                    return -1
                if not fi1.isDirectory() and fi2.isDirectory() do
                    return 1

                let byName = Utf8.compare(fi1.fullName.toSlice(), fi2.fullName.toSlice(), .Latin1NoCase)
                switch col
                {
                case 0:
                    return byName * (down ? -1 : 1)

                case 1:
                    return (fi1.lastWriteTime <=> fi2.lastWriteTime) * (down ? -1 : 1)

                case 2:

                    // Folders have no size: keep them in stable name order.
                    if fi1.isDirectory() do
                        return byName
                    let bySize = fi1.size <=> fi2.size
                    return (bySize ? bySize : byName) * (down ? -1 : 1)
                }

                return 0
            }
        }
    }
}

impl FileBrowserCtrl
{
    // Copies the current browsing state into the optional borrowed state object.
    internal mtd saveState()
    {
        if not .options.state do
            return

        let state = .options.state
        state.currentFolder       = .currentFolder
        state.nameColumnWidth     = cast(.listCtrl.header.itemWidthForColumn(0))
        state.modifiedColumnWidth = cast(.listCtrl.header.itemWidthForColumn(1))
        state.sizeColumnWidth     = cast(.listCtrl.header.itemWidthForColumn(2))
    }

    // Hands the foot — the type filter and the line of what is chosen — to a host that shows it elsewhere, such as the bottom-left slot of a dialog.
    //
    // It takes its own width, since the browser may not have been laid out yet when it is handed over.
    internal mtd detachFoot()->*Wnd
    {
        .typeRow.resize(.themeMetrics().fileBrowser_FootWidth, .themeMetrics().control_DialogHeight)
        return .typeRow
    }

    // Returns the path of the current folder as the path field writes it, its steps parted by slashes.
    mtd displayPath()->String
    {
        var result: String
        for &stop, idx in .crumbs.stops
        {
            if idx do
                result += " / "
            result += stop.name
        }

        return result
    }

    // Puts the keyboard where a name is chosen: the name field of a save, the path field otherwise.
    internal mtd focusNameEntry()
    {
        let entry = .options.mode == .CreateFile ? .editFile : .pathField
        entry.selectAll()
        entry.setFocus()
    }

    // Creates an embedded file browser inside `parent`.
    //
    // From the top: the places as text tabs, the path field with the parent, recent and new
    // folder glyphs at its end, the list, the name field of a save, and the type filter.
    #[Swag.Discardable]
    func create(parent: *Wnd, opt: FileDlgOptions = {}, position: Math.Rectangle = {})->*FileBrowserCtrl
    {
        Swag.assert(parent != null)
        let fileBrowser = Wnd.create'FileBrowserCtrl(parent, "", position)
        fileBrowser.options         = opt
        fileBrowser.backgroundStyle = .Transparent
        let metrics = fileBrowser.themeMetrics()

        let primaryShortcutCount = fileBrowser.options.shortcuts.count
        func addDefaultShortcut(browser: *FileBrowserCtrl, directory: Env.SpecialDirectory, name: string)
        {
            for &shortcut in browser.options.shortcuts where shortcut.type == directory do
                return
            browser.options.shortcuts.add({type: directory, name})
        }

        addDefaultShortcut(fileBrowser, .Desktop, strings().browser_Desktop)
        addDefaultShortcut(fileBrowser, .UserDocuments, strings().browser_Documents)
        addDefaultShortcut(fileBrowser, .Downloads, strings().browser_Downloads)
        addDefaultShortcut(fileBrowser, .UserPictures, strings().browser_Pictures)
        addDefaultShortcut(fileBrowser, .UserMusic, strings().browser_Music)
        addDefaultShortcut(fileBrowser, .UserVideos, strings().browser_Videos)

        if fileBrowser.options.mode != .SelectFolder and fileBrowser.options.filters.isEmpty() do
            fileBrowser.options.filters.add({name: strings().browser_AllFiles, extensions: ""})

        // Places
        if fileBrowser.options.showLocationsPane
        {
            with let places = Wnd.create'FilePlacesBar(fileBrowser, "", {0, 0, 0, metrics.fileBrowser_PlacesHeight})
            {
                .dockStyle   = .Top
                .focusPolicy = .Click
                .browser     = fileBrowser
                with .moreButton = IconButton.create(places, .theme().icon(.More, metrics.fileBrowser_GlyphSize), {0, 0, metrics.fileBrowser_PlacesHeight, metrics.fileBrowser_PlacesHeight})
                {
                    .dockStyle  = .Right
                    .toolTip    = strings().browser_MorePlaces
                    .sigPressed += func|places|(_) { places.openOverflowMenu() }
                }

                for idx in 0 until primaryShortcutCount
                {
                    let v = fileBrowser.options.shortcuts[idx]
                    .addPlace(v.name, Env.getSpecialDirectory(v.type).toString())
                }

                if fileBrowser.options.showDrives
                {
                    let volumes = catch Directory.drives()
                    for &v in volumes
                    {
                        let path = String.from(v.toString())
                        v.removeBack()
                        .addPlace(v.toString(), path.toString())
                    }
                }

                .primaryCount = .stops.count
                for idx in primaryShortcutCount until fileBrowser.options.shortcuts.count
                {
                    let v = fileBrowser.options.shortcuts[idx]
                    .addPlace(v.name, Env.getSpecialDirectory(v.type).toString())
                }
            }

            fileBrowser.placesBar = places
        }

        fileBrowser.createPathRow(fileBrowser)

        // The type filter, at the bottom left, until a host takes it for a slot of its own.
        with fileBrowser.typeRow = Wnd.create'Wnd(fileBrowser, {0, 0, metrics.fileBrowser_FootWidth, metrics.control_DialogHeight})
        {
            .dockStyle = .Bottom
            .margin.y  = metrics.fileBrowser_RowGap
        }

        with fileBrowser.comboType = ComboBox.create(fileBrowser.typeRow, flags: .Flat)
        {
            .dockStyle = .Left
            if fileBrowser.options.mode == .SelectFolder do
                .hide()
            if fileBrowser.options.mode == .SelectFolder do
                .addItem(strings().browser_Folders)
            else do
                for f, idx in fileBrowser.options.filters do
                    .addItem(f.name, userData0: cast(*void?, idx))
            .setSelectedIndex(0)

            // As wide as its longest name, since it holds a slot of its own rather than a column.
            let font   = fileBrowser.theme().createDefaultFont(metrics.defaultFontSize)
            var widest = 0'f32
            for item in .items where item do
                widest = Math.max(widest, Painter.measureString(item.name.raw.toString(), font).width)
            .resize(widest + metrics.fileBrowser_TypeChrome, metrics.control_DialogHeight)
            .sigChanged += func|fileBrowser|(_, _)
            {
                fileBrowser.fillFileList()
                fileBrowser.updateSaveExtension()
            }
        }

        with fileBrowser.choiceLabel = Label.create(fileBrowser.typeRow, "")
        {
            .dockStyle = .Center
            if fileBrowser.options.mode != .SelectFolder do
                .margin.x = metrics.fileBrowser_PlaceGap
            .style.setFont(fileBrowser.theme().createDefaultFontFs(metrics.defaultFontSize - 1), .Regular)
            .setTextColor(fileBrowser.themeColors().faintText)
            .setTextAlignment(.Left, .OpticalCenter)
            .updateFlags(add: .Ellipsis)
        }

        // The name a save creates, labelled above its field; in the other modes the names chosen
        // in the list are kept here, out of sight.
        if fileBrowser.options.mode == .CreateFile
        {
            with var formOptions: FormLayoutOptions
            {
                .fieldHeight = metrics.control_DialogHeight
            }

            with let form = FormLayoutCtrl.create(fileBrowser, formOptions)
            {
                .dockStyle = .Bottom
                .margin.y  = metrics.fileBrowser_RowGap
            }

            fileBrowser.editFile = EditBox.create(form, "")
            fileBrowser.editFile.sigTextChanged += func|fileBrowser|(_) { fileBrowser.updateSaveExtension() }
            discard form.addField(strings().browser_FileName, fileBrowser.editFile)
        }
        else
        {
            fileBrowser.editFile = EditBox.create(fileBrowser, "")
            fileBrowser.editFile.hide()
        }

        fileBrowser.createFileList(fileBrowser)
        fileBrowser.applyLayout()

        with fileBrowser
        {
            if fileBrowser.options.initialFolder.count do
                .setCurrentFolder(fileBrowser.options.initialFolder)
            elif fileBrowser.options.state and not fileBrowser.options.state.currentFolder.isEmpty() do
                .setCurrentFolder(fileBrowser.options.state.currentFolder)
            .listCtrl.sort(0)
            .editFile.setText(fileBrowser.options.initialName)
            if fileBrowser.options.mode == .CreateFile
            {
                // A save names its file without the extension its type adds: the extension
                // trails the name, faint, and follows the type chosen under it.
                let name = fileBrowser.options.initialName
                var stem = name.count
                for i in name.count where name[i] == '.'u8 and i > 0 do
                    stem = i
                if stem < name.count and fileBrowser.typeAddsExtensionOf(name) do
                    .editFile.setText(name[0 until stem])
                .updateSaveExtension()
                .editFile.setSelection(0, stem)
                .editFile.setFocus()
            }
            else
            {
                .pathField.setFocus()
            }
        }

        // Default to the first place when nothing else chose a folder.
        if fileBrowser.currentFolder.isEmpty() and
           fileBrowser.placesBar and
           not fileBrowser.placesBar.stops.isEmpty() do
            fileBrowser.setCurrentFolder(fileBrowser.placesBar.stops[0].path)

        fileBrowser.updateNavigationState()
        fileBrowser.updateChoice()
        return fileBrowser
    }

    // Navigates to `folder`; returns false when it does not name an existing directory.
    #[Swag.Discardable]
    mtd setCurrentFolder(folder: string)->bool
    {
        if not .showFolder(folder) do
            return false
        .history.push(.currentFolder.toString())
        .updateNavigationState()
        return true
    }

    // Returns whether a previous folder is available in this browser session.
    mtd canGoBack()->bool => .history.canGoBack()

    // Returns whether a later folder is available in this browser session.
    mtd canGoForward()->bool => .history.canGoForward()

    // Navigates to the previous folder; returns false when history has no valid entry.
    #[Swag.Discardable]
    mtd goBack()->bool
    {
        if not .history.canGoBack() do
            return false
        let oldIndex = .history.index
        let folder   = .history.goBack()
        if not .showFolder(folder.toString())
        {
            .history.index = oldIndex
            .updateNavigationState()
            return false
        }

        .updateNavigationState()
        return true
    }

    // Navigates to the next folder; returns false when history has no valid entry.
    #[Swag.Discardable]
    mtd goForward()->bool
    {
        if not .history.canGoForward() do
            return false
        let oldIndex = .history.index
        let folder   = .history.goForward()
        if not .showFolder(folder.toString())
        {
            .history.index = oldIndex
            .updateNavigationState()
            return false
        }

        .updateNavigationState()
        return true
    }

    // Navigates to the parent folder; returns false at a root or when it is unavailable.
    #[Swag.Discardable]
    mtd goUp()->bool
    {
        let parent = Path.directoryName(.currentFolder.toString()) orelse ""
        if not parent.count or parent == .currentFolder.toString() do
            return false
        return .setCurrentFolder(parent)
    }

    // Reloads the file list of the current folder.
    mtd refresh()
    {
        .fillFileList()
        .updateNavigationState()
    }

    // Fills the file list from the current folder, applying the type filter and the words typed in the path field.
    private mtd fillFileList()
    {
        .listCtrl.clear()

        with var options: EnumerationOptions
        {
            .skipAttributes  = .Hidden
            .wantFiles       = me.options.mode != .SelectFolder
            .wantDirectories = true
            .recurse         = false
        }

        .currentEntries = catch Directory.enumerate(.currentFolder, options)

        let filterExtensions = .activeFilterExtensions()
        let tokens = Tokenize.split(filterExtensions orelse "", ';'rune)

        var typed = String.from(.typedIsPath() ? "" : .pathField.text())
        typed.trim()
        let now = Time.DateTime.now()

        for &fi in .currentEntries
        {
            let fname = unwrap Path.fileName(fi.fullName)

            // Filter
            var show = true
            if not fi.isDirectory() and filterExtensions.count
            {
                show = false
                for t in tokens
                {
                    if Path.hasExtension(fname, t)
                    {
                        show = true
                        break
                    }
                }
            }

            if not show do
                continue
            if typed.count and Utf8.indexOf(fname, typed.toString(), comparisonType: .Latin1NoCase) == Swag.U64.Max do
                continue

            // Content. The date and the size are read at a glance and never acted on, so they
            // stand in the faint ink beside the names.
            let faint = .themeColors().faintText
            var icon  = .theme().fileGlyph(fname, fi.isDirectory())
            if not icon.color.a do
                icon.color = .themeColors().softText
            let line = .listCtrl.createLine(fname, icon)
            line.userData0 = fi
            line.canCheck  = .options.mode == .SelectFiles and not fi.isDirectory()

            // The words typed in the path field are marked where they were found in the name.
            if typed.count
            {
                let nameItem = unwrap line.items[0]
                nameItem.matchStart = cast(u32, Utf8.indexOf(fname, typed.toString(), comparisonType: .Latin1NoCase))
                nameItem.matchCount = cast(u32, typed.count)
            }

            // In a save the rows are context, not choices.
            if .options.mode == .CreateFile do
                line.colorFg = faint
            let dateItem = line.setItem(1, briefFileTime(fi.lastWriteTime.toLocal(), now))
            dateItem.sortKey = fi.lastWriteTime.toString(.DateTimeIso)
            dateItem.colorFg = faint
            dateItem.mono    = true
            if not fi.isDirectory()
            {
                let sizeItem = line.setItem(2, Format.byteSize(fi.size).toString())
                sizeItem.horzAlign = .Right
                sizeItem.colorFg   = faint
                sizeItem.mono      = true
            }
        }

        .listCtrl.setEmptyText(typed.count ? strings().browser_NoMatch : strings().browser_EmptyFolder)
        .listCtrl.computeLayout()
        .listCtrl.sort()
        .updateChoice()
    }

    // Creates a folder inside [[Gui.FileBrowserCtrl.currentFolder]] and refreshes the list on success.
    mtd createFolder(name: string)->bool
    {
        if .currentFolder.isEmpty() or not Path.isValidFileName(name) do
            return false
        let path = Path.combine(.currentFolder, name)
        catch Directory.create(path) do
            return false
        .fillFileList()
        return true
    }

    // Changes the contents of the file or folder name editor.
    mtd setFileName(name: string?)
    {
        .editFile.setText(name)
    }

    // Returns the current contents of the file or folder name editor.
    mtd fileName()->string => .editFile.text()

    // Returns the folder the name editor points to, or an empty string.
    //
    // The editor targets a folder when it holds one single entry naming an existing
    // directory, either absolute or relative to [[Gui.FileBrowserCtrl.currentFolder]].
    // A file dialog uses this to navigate on confirmation instead of accepting.
    mtd typedFolderTarget()->String
    {
        var typed = String.from(.editFile.text())
        typed.trim()
        if typed.isEmpty() or typed.contains(";") do
            return String.from("")

        var candidate: String
        if Path.rootLength(typed.toString()) > 0 do
            candidate = typed
        else do
            candidate = Path.combine(.currentFolder, typed.toString())
        if not Directory.exists(candidate) do
            return String.from("")
        return candidate
    }

    // Records the accepted selection into the reusable dialog state.
    //
    // The browsed folder (and the selected folder in folder mode) lands at the front of
    // [[Gui.FileDlgState.recentFolders]], served by the recent-folders drop-down.
    mtd noteAccepted()
    {
        if not .options.state do
            return
        if .options.mode == .SelectFolder
        {
            let sel = .selectedPath()
            if not sel.isEmpty() do
                .recordRecentFolder(sel.toString())
        }

        .recordRecentFolder(.currentFolder.toString())
        .updateNavigationState()
    }

    // Puts `folder` at the front of the recent list, keeping at most eight unique entries.
    mtd recordRecentFolder(folder: string)
    {
        let state = .options.state
        if not state or not folder.count or not Directory.exists(folder) do
            return

        var normalized = String.from(folder)
        Path.normalize(&normalized)
        for &existing, idx in state.recentFolders
        {
            if Utf8.compare(existing.toSlice(), normalized.toSlice(), .Latin1NoCase) == 0
            {
                state.recentFolders.removeAtOrdered(idx)
                break
            }
        }

        state.recentFolders.insertAt(0, normalized)
        while state.recentFolders.count > 8 do
            state.recentFolders.removeBack()
    }

    // Returns the first selected full path, or an empty string when selection is invalid.
    mtd selectedPath()->String
    {
        let sel = .selectedPaths()
        if sel.isEmpty() do
            return String.from("")
        return sel.front()
    }

    // Returns the extensions of the file-type filter chosen in the type selector, or null for none.
    //
    // Folder selection has no filters, so it lists and returns folders only.
    private mtd activeFilterExtensions()->string?
    {
        if .options.mode == .SelectFolder or .options.filters.isEmpty() do
            return null

        let filterIndex = cast(u64, .comboType.selectedItem()!.userData0)
        if filterIndex >= .options.filters.count do
            return null
        return .options.filters[filterIndex].extensions
    }

    // Returns all selected full paths in display order.
    //
    // Picking a folder with nothing chosen in the list picks the folder the browser shows.
    mtd selectedPaths()->Array'String
    {
        var result: #returntype
        if .options.mode == .SelectFolder and
           .editFile.text().count == 0 and
           not .currentFolder.isEmpty()
        {
            result.add(.currentFolder)
            return result
        }

        let filterExtensions = .activeFilterExtensions()
        let tokens = Tokenize.split(.editFile.text(), ';'rune)
        for t in tokens
        {
            // Be sure this is a valid file/folder name
            var t1 = String.from(t)
            t1.trim()
            if t1.isEmpty() do
                continue
            if .options.mode == .SelectFolder and not Path.isValidPathName(t1.toString()) do
                continue
            if .options.mode != .SelectFolder and not Path.isValidFileName(t1.toString()) do
                continue

            // Get the full name
            var val = Path.combine(.currentFolder, t1.toString())

            // A filter can offer several extensions. Keep any one of them when it is already
            // present; otherwise append the first, preferred extension.
            var hasFilterExtension = false
            let extensions         = Tokenize.split(filterExtensions orelse "", ';'rune)
            for extension in extensions where extension.count
            {
                if Path.hasExtension(val, extension)
                {
                    hasFilterExtension = true
                    break
                }
            }

            if .options.mode != .SelectFolder and
               filterExtensions.count and
               not hasFilterExtension and
               extensions.count do
                val += extensions[0]

            result.add(val)
        }

        return result
    }

    // Reports whether the type chosen in a save adds one of its extensions to `name`, which then
    // already ends with it.
    private mtd typeAddsExtensionOf(name: string)->bool
    {
        let extensions = Tokenize.split(.activeFilterExtensions() orelse "", ';'rune)
        for extension in extensions where extension.count
        {
            if Path.hasExtension(name, extension) do
                return true
        }

        return false
    }

    // Writes, faint after the name of a save, the extension the chosen type will add to it; a
    // name that already ends with one of the type's extensions gets nothing more.
    private mtd updateSaveExtension()
    {
        if .options.mode != .CreateFile do
            return
        let extensions = Tokenize.split(.activeFilterExtensions() orelse "", ';'rune)
        if extensions.count == 0 or extensions[0].count == 0 or .typeAddsExtensionOf(.editFile.text())
        {
            .editFile.setUnit("")
            return
        }

        .editFile.setUnit(extensions[0])
    }

    // Returns whether the current selection satisfies the configured dialog mode.
    mtd hasValidSelection()->bool
    {
        let paths = .selectedPaths()
        if paths.isEmpty() do
            return false

        switch #complete .options.mode
        {
        case .CreateFile:
            return paths.count == 1 and Directory.exists(.currentFolder)

        case .SelectFile:
            return paths.count == 1 and File.exists(paths[0])

        case .SelectFiles:
            for path in paths where not File.exists(path.toString()) do
                return false
            return true

        case .SelectFolder:
            return paths.count == 1 and Directory.exists(paths[0])
        }
    }
}

// Writes `time` as briefly as a file list can still read it against `now`: "21:30" today,
// "10-26 21:30" within the year, "2025-03-01" before.
//
// Both are wall-clock times of the same zone: a file system's UTC times go through
// [[Core.Time.DateTime.toLocal]] first, with `now` from [[Core.Time.DateTime.now]].
//
// ```swag
// let when = briefFileTime(file.lastWriteTime.toLocal(), Time.DateTime.now())
// ```
func briefFileTime(time, now: Time.DateTime)->String
{
    if time.year == now.year and time.month == now.month and time.day == now.day do
        return time.toString(.TimeIsoHm)
    if time.year == now.year do
        return Format.toString("%{02}-%{02} %", time.month, time.day, time.toString(.TimeIsoHm))
    return time.toString(.DateIso)
}
