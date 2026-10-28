#global internal

using Core, Gui, Pixel, Video

enum ExplorerMode { Names, Details, Small, Medium, Large }

// Width over height of a tile's picture: a page for a folder of documents, a screen for a folder
// that is mostly films.
const ExplorerTilePreviewAspect: f32 = 0.8
const ExplorerFilmPreviewAspect: f32 = 16.0 / 9.0

// The duration label of a film tile: small, bold, light ink on a translucent ink ground.
const ExplorerDurationFontSize = 11'u32
const ExplorerDurationGround   = 0xB30B0B0D'u32
const ExplorerDurationInk      = 0xFFE6E6EA'u32

// Writes a duration the way players do: hours only when there are some, minutes and seconds always.
func formatDuration(seconds: u64)->String
{
    let hours   = seconds / 3600
    let minutes = (seconds / 60) % 60
    if hours do
        return Format.toString("%:%{02}:%{02}", hours, minutes, seconds % 60)
    return Format.toString("%:%{02}", minutes, seconds % 60)
}

// Returns the duration a thumbnail is labelled with, in seconds, or zero when it carries none.
func thumbnailDuration(image: const *Image)->u64
{
    for &record in image.metadata where record.isTag(cast(const [..] u8, Viewer.ThumbnailDurationTag)) do
        return catch StrConv.toU64(cast(string, record.toSlice()))
    return 0
}

// Returns how many isolated renderers the Explorer keeps busy.
//
// Each renderer is a child process decoding on one thread, so one per logical processor saturates
// the machine; two are left to the interface and to the decoders of the open viewer.
func explorerWorkerCount()->u64 => Math.max(cast(u64, Hardware.processorCount()), 3'u64) - 2

// How many previews of a folder on a network share run at once.
//
// A share answers a bounded number of scattered reads a second, and every renderer past what it
// keeps busy only lengthens the queue in front of it: on a NAS, twenty renderers filled the folder
// half as fast as a handful.
const ExplorerRemoteWorkerCount = 6'u64

struct ExplorerTemporary
{
    file:  String
    title: String
}

// Owns exploration independently of the file currently being viewed.
//
// The folder is a page: its path as a faint breadcrumb, its name as the title, how much it holds
// in mono, and quiet menus choosing the order and the way of showing it, above a contact sheet of
// what it holds. Moving through the history, refreshing, the online media choices — everything
// else is an entry of the window's lens, and the item chosen is described in the window's sheet.
struct Explorer
{
    using wnd: Wnd

    late
    {
        window:    *ViewerWindow
        header:    *Wnd
        summary:   *Label
        tools:     *StackLayoutCtrl
        address:   *ExplorerAddress
        title:     *Label
        status:    *Label
        extractAll: *IconButton
        sortMenu:  *IconButton
        modeMenu:  *IconButton
        filter:    *EditBox
        list:      *ListCtrl
        scroll:    *ScrollWnd
        grid:      *ExplorerGrid
    }

    mode:            ExplorerMode = .Medium
    history:         NavigationHistory
    listing:         ExplorerListing
    entries:         Array'ExplorerEntry
    shown:           Array'u64
    folder:          String
    requested:       String
    requestedFolder: String
    load:            ExplorerListingLoad
    previews:        Array'ExplorerPreview     // Sized once: a running task borrows its preview.
    generation:      u64
    selected:        u64 = Swag.U64.Max
    pendingOpen:     u64 = Swag.U64.Max
    temporaryFiles:  Array'ExplorerTemporary
    cached:          Array'u64
    sortColumn:      u32
    descending:      bool
    menuPaths:       Array'String
    previewSettings: String
    bypassCache:     bool     // Whether the previews of the shown listing ignore the persistent cache, after a forced refresh.
    previewAspect:   f32 = ExplorerTilePreviewAspect     // Shape of the tiles, chosen from what the listing holds.
    previewBudget:   u64      // How many previews of the shown listing run at once.
    extraction:      ArchiveExtraction
    toast:           *Toast?
}

impl Explorer
{
    // The air between the page and the edges of the document, the height of its header, and the
    // size its title is set in.
    const PageMargin    = 72.0
    const HeaderHeight  = 94.0
    const TitleFontSize    = 44'u32
    const MinTitleFontSize = 28'u32
    const ToolHeight    = 32.0
    const AddressHeight = 24.0
    const SummaryHeight = 24.0

    func create(parent: *Wnd, window: *ViewerWindow)->*Explorer
    {
        with let result = Wnd.create'Explorer(parent, "scope.explorer")
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .window          = window
        }

        result.createHeader()

        // The tiles draw from the cell edge, so the sheet steps in by the air a cell keeps, and
        // its pictures line up with the title above them.
        let sheetMargin = PageMargin - ExplorerGrid.CellInset
        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .margin          = Math.Vector4{sheetMargin, 0, sheetMargin, 0}
            .updateFlags(.Ellipsis | .HotTrack)
            .addColumn(appStrings().explore_Name, 320)
            .addColumn(appStrings().explore_Type, 140)
            .addColumn(appStrings().explore_Size, 100)
            .addColumn(appStrings().explore_Modified, 160)
            .sigSelectionChanged += func|result|(list)
            {
                if list.focusIndex < result.shown.count
                {
                    result.selected = result.shown[list.focusIndex]
                    result.showMediaInfo()
                    result.requestPreview()
                }
            }

            .onFillVirtualLine = func(list, line, row)
            {
                if not line do
                    return
                let explorer = unwrap list.ancestorByType'Explorer()
                let index    = explorer.shown[row]
                let entry    = &explorer.entries[index]
                line.setItem(0, entry.name, explorer.entryIcon(index))
                if explorer.mode == .Details
                {
                    line.setItem(1, entry.directory ? appStrings().ui_Folder : (Path.extension(entry.name) orelse ""))
                    line.setItem(2, entry.directory ? {} : StrConv.toDisplaySize(entry.size))
                    line.setItem(3, entry.modified)
                }
            }

            .sigLeftDoubleClicked += func|result|(_, _)
            {
                result.activate(result.selected)
            }

            .sigKeyPressed += func|result|(_, evt)
            {
                if evt.key == .Return
                {
                    result.activate(result.selected)
                    evt.accepted = true
                }
            }
        }

        result.list.header.sigColumnClicked += func|result|(_, column)
        {
            result.sortBy(column, result.sortColumn == column and not result.descending)
        }

        with result.scroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle = .Center
            .margin    = Math.Vector4{sheetMargin, 0, sheetMargin, 0}
            .updateFlags(.DisableHorizontal)
            .sigScrollPositionChanged += func|result|(_, _, _) { result.prioritizeVisible() }
        }

        with result.grid = result.scroll.createView'ExplorerGrid()
        {
            .explorer        = result
            .backgroundStyle = .View
            .focusPolicy     = .Tab
        }

        result.retranslate()
        result.previews.resize(explorerWorkerCount())
        result.previewBudget = result.previews.count
        result.grid.busy.resize(result.previews.count)
        for result.previews.count
        {
            with let spinner = Spinner.create(result.grid)
            {
                .backgroundStyle = .Transparent
                .hide()
                .hookOnEvent = func|result|(_, evt)
                {
                    if evt is MouseEvent as mouse
                    {
                        result.grid.itf.onMouseEvent(mouse)
                        return true
                    }

                    return false
                }
            }

            result.grid.spinners.add(spinner)
        }

        result.setMode(.Medium)
        return result
    }

    // Builds the head of the page: the path as a faint breadcrumb, the folder name as its title,
    // and on the title's line how much it holds, the filter, and the quiet menus of its order and
    // of the way it is shown.
    private mtd createHeader()
    {
        with .header = Wnd.create'Wnd(me, Math.Rectangle{0, 0, 0, HeaderHeight}, "scope.explorer.header")
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .padding         = Math.Vector4{PageMargin, 0, PageMargin, 8}
        }

        with .address = ExplorerAddress.create(.header, me)
        {
            .dockStyle       = .Top
            .position.height = AddressHeight
        }

        // An archive writes what it holds and weighs on a mono line under its title.
        with .summary = Label.create(.header, "", {0, 0, 0, SummaryHeight}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Bottom
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .style.addStyleSheetColors("label_TextLight $label_TextFaint")
            .setTextAlignment(.Left, .OpticalCenter)
            .hide()
        }

        with let line = Wnd.create'Wnd(.header)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        // The tools stand on the baseline of the title, at the end of its line.
        with .tools = StackLayoutCtrl.create(line, .Left, {0, 0, 0, 0})
        {
            .dockStyle       = .Right
            .backgroundStyle = .Transparent
            .spacing         = 8
        }

        with .status = Label.create(.tools, "", {0, 0, 0, ToolHeight}, null, .SecondaryText)
        {
            .layoutSpec.alignY = .End
            .margin.z          = 8
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .style.addStyleSheetColors("label_TextLight $label_TextFaint")
            .setTextAlignment(.Right, .OpticalCenter)
        }

        // The filter is asked for, by the find key or the lens, on its own line under the title so
        // the title keeps its room, and leaves once it is empty and the keyboard has gone elsewhere.
        with .filter = EditBox.create(.header, "", {0, 0, ViewerWindow.SearchFieldWidth, ToolHeight}, flags: .ClearButton)
        {
            .dockStyle = .Bottom
            .margin    = {0, 4, 0, 0}
            .setForm(.Transparent)
            .setIcon(me.theme().icon(.Search, themeRowIconSize(me.themeMetrics())))
            .setPlaceholder(appStrings().ui_FilterFiles)
            .hide()
            .sigTextChanged += func|view = me|(_) { view.fill() }
            .sigFocusLost   += func|view = me|(edit)
            {
                if not edit.text().count
                {
                    edit.hide()
                    view.fitHeader()
                }
            }
        }

        // An archive offers to extract all it holds, a quiet word acting at once.
        with .extractAll = IconButton.createQuiet(.tools, menu: false)
        {
            .layoutSpec.alignY = .End
            .hide()
            .sigPressed += func|view = me|(_) { view.chooseExtraction(all: true) }
        }

        with .sortMenu = IconButton.createQuiet(.tools)
        {
            .layoutSpec.alignY = .End
            .sigPressed += func|view = me|(_) { view.showSortMenu() }
        }

        with .modeMenu = IconButton.createQuiet(.tools)
        {
            .layoutSpec.alignY = .End
            .sigPressed += func|view = me|(_) { view.showModeMenu() }
        }

        with .title = Label.create(line, "", {}, null, .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFont(TitleFontSize, .Bold), .Regular)
            .setTextAlignment(.Left, .Bottom)
        }
    }

    // Shows the filter of the listing and gives it the keyboard.
    mtd revealFilter()
    {
        .filter.show()
        .fitHeader()
        .filter.setFocus()
    }

    // Gives the head of the page the height of the lines it shows: the path, the title, and the
    // summary of an archive and the filter when they show.
    mtd fitHeader()
    {
        var height = HeaderHeight
        if .summary.isLocallyVisible() do
            height += SummaryHeight
        if .filter.isLocallyVisible() do
            height += ToolHeight + 4
        if .header.position.height != height
        {
            .header.position.height = height
            .applyLayout()
        }

        .layoutTools()
    }

    // Fits the tools of the header to what they hold, after a word in them changed.
    //
    // The title comes first: on a narrow page the count leaves the line before the title would be
    // cut, and comes back when there is room for both.
    mtd layoutTools()
    {
        let line     = unwrap .tools.parent
        let text     = .title.text()
        let full     = Painter.measureString(text, .theme().createDefaultFont(TitleFontSize, .Bold)).width
        let smallest = Painter.measureString(text, .theme().createDefaultFont(MinTitleFontSize, .Bold)).width
        let space    = line.clientRect().width - 24
        .extractAll.show(.listing.isArchive)
        .status.show(not .listing.isArchive and not .status.name.raw.isEmpty())
        var width = Math.ceil(.tools.itf.measureContent({}).x)
        if .status.isLocallyVisible() and width + full > space
        {
            .status.hide()
            width = Math.ceil(.tools.itf.measureContent({}).x)
        }

        // Extracting the whole archive is a lens entry too: it leaves the line before the title
        // would be cut at its smallest.
        if .extractAll.isLocallyVisible() and width + smallest > space
        {
            .extractAll.hide()
            width = Math.ceil(.tools.itf.measureContent({}).x)
        }

        .tools.position.width = width

        // Then the title steps down the scale of page titles before it would be cut. A folder of
        // an archive is a page within a document, titled at the foot of the scale.
        let room = space - width
        for size in [TitleFontSize, 36'u32, MinTitleFontSize]
        {
            if .listing.isArchive and size != MinTitleFontSize do
                continue
            let font = .theme().createDefaultFont(size, .Bold)
            if Painter.measureString(text, font).width <= room or size == MinTitleFontSize
            {
                .title.style.setFont(font, .Regular)
                break
            }
        }

        .header.applyLayout()
        .tools.computeLayout()
    }

    // Shows the ways of showing the listing under its menu, the one in use checked.
    mtd showModeMenu()
    {
        let text = appStrings()
        let menu = MenuCtrl.createPopup(me, owner: me)
        for name, mode in [text.explore_Names, text.explore_Details, text.explore_Small, text.explore_Medium, text.explore_Large] do
            menu.addRadioItem(name, Format.toString("scope.explore.mode.%", mode), checked: cast(u64, .mode) == mode)

        let chosen = menu.doModal(.modeMenu, autoDestroy: true) orelse ""
        for mode in 5 where chosen == Format.toString("scope.explore.mode.%", mode).toString() do
            .setMode(cast(ExplorerMode, cast(u32, mode)))
    }

    // Shows the orders of the listing under its menu: the column, and whether it runs backward.
    mtd showSortMenu()
    {
        let text = appStrings()
        let menu = MenuCtrl.createPopup(me, owner: me)
        for id in [ViewerCommands.SortName, ViewerCommands.SortType, ViewerCommands.SortSize, ViewerCommands.SortModified] do
            menu.addRadioItem(sortCommandName(sortColumnOf(id)), id, checked: .sortColumn == sortColumnOf(id))
        menu.addSeparator()
        menu.addItem(text.cmd_SortDescending, ViewerCommands.SortDescending, checked: .descending)

        let chosen = menu.doModal(.sortMenu, autoDestroy: true) orelse ""
        if chosen == ViewerCommands.SortDescending do
            .sortBy(.sortColumn, not .descending)
        elif chosen.count do
            .sortBy(sortColumnOf(chosen), .descending)
    }

    // Orders the listing by `column`, backward when `descending`, and lists the folder again.
    mtd sortBy(column: u32, descending: bool)
    {
        .sortColumn = column
        .descending = descending
        .refreshQuietMenus()
        .navigate(.listing.path, .folder, false)
    }

    // Writes the order and the way of showing in use on their menus.
    mtd refreshQuietMenus()
    {
        let text = appStrings()
        var sort: string
        switch .sortColumn
        {
        case 1:  sort = text.sort_Type
        case 2:  sort = text.sort_Size
        case 3:  sort = text.sort_Modified
        default: sort = text.sort_Name
        }

        .sortMenu.setQuietText(sort)
        .extractAll.setQuietText(text.cmd_ExtractAll)
        switch .mode
        {
        case .Names:   .modeMenu.setQuietText(text.mode_Names)
        case .Details: .modeMenu.setQuietText(text.mode_Details)
        default:       .modeMenu.setQuietText(text.mode_Thumbnails)
        }
        .layoutTools()
    }

    // Returns the name of the explored location, as the page title and the window title show it.
    mtd locationName()->String
    {
        let location = .locationText()
        var trimmed  = location.toString()
        while trimmed.count > 1 and trimmed[trimmed.count - 1] == '/'u8 do
            trimmed = trimmed[0 until trimmed.count - 1]
        return Path.fileName(trimmed) orelse trimmed
    }

    // Turns the online movie and music details on or off, and shows the tiles again under them.
    mtd setOnlineMedia(movies, music: bool)
    {
        .window.onlineMovies = movies
        .window.onlineMusic  = music
        .refreshMediaOptions()
        catch .window.saveState()
    }

    // Reports whether the chosen item is a piece of music the reader may match by hand.
    mtd canChooseMusic()->bool => .selected < .entries.count and
                                  .window.onlineMusic and
                                  not .listing.isArchive and
                                  not .entries[.selected].directory and
                                  (Path.hasExtension(.entries[.selected].path, ".mp3") or Path.hasExtension(.entries[.selected].path, ".flac"))

    // Shows or hides the listing.
    mtd setShown(visible: bool)
    {
        .show(visible)
        .window.teachHints(visible)
        .showMediaInfo()
    }

    // Reports what the location holds, or why it holds nothing, on the title's line.
    mtd setStatus(text: string)
    {
        // An archive says it under its title, where its counts and weights have the room.
        let archive = .listing.isArchive
        .summary.setText(archive ? text : "")
        .summary.show(archive)
        .fitHeader()
        .status.show(not archive)
        .status.setText(text)
        .status.position.width = Math.ceil(.status.itf.measureContent({}).x)
        .layoutTools()
    }

    mtd refreshMediaOptions()
    {
        .previewAspect = .listingPreviewAspect()
        .grid.refreshLayout()
        .refreshPreviewSettings()
        .requestPreview()
        .grid.invalidate()
    }

    mtd chooseMusic()
    {
        if .selected >= .entries.count do
            return
        let selected   = .selected
        let generation = .generation
        let previous   = musicChoiceId(.window.musicChoices.toSlice(), &.entries[selected])
        let dialog     = .createMusicChoiceDialog(previous)
        if dialog.doModal() != Dialog.BtnOk do
            return
        if generation != .generation or selected != .selected or selected >= .entries.count do
            return
        let answer = dialog.text()
        let text   = Latin1.trim(answer.toString())
        if text.count and not validMusicId(text)
        {
            .setStatus(appStrings().explore_InvalidMusicId)
            return
        }

        setMusicChoice(&.window.musicChoices, &.entries[selected], String.toLower(text))
        .retirePreviews()
        .requestPreview()
    }

    mtd createMusicChoiceDialog(previous: string)->*EditDlg
    {
        return EditDlg.createSingleLine(unwrap .window.surface, {title: appStrings().explore_ChooseMusic,
                                                                 message: appStrings().explore_ChooseMusicHelp,
                                                                 text: previous})
    }

    // Describes the chosen item again in the window's sheet, when the sheet is showing.
    mtd showMediaInfo()
    {
        if not .window.infoSheet.isLocallyVisible() do
            return
        .window.infoSheet.clear()
        .describeSelection(.window.infoSheet)
    }

    // Opens the window's sheet on the chosen item.
    mtd showInformation()
    {
        .window.infoSheet.clear()
        .describeSelection(.window.infoSheet)
        .window.infoSheet.open()
        .fitToSheet(true)
    }

    // Leaves the sheet its room at the trailing edge while it is open, so the page never runs
    // under it, and takes the room back once it is closed.
    mtd fitToSheet(open: bool)
    {
        let metrics = .themeMetrics()
        let room    = open ? metrics.infoSheet_Width + 2 * metrics.floating_Inset - PageMargin : 0
        if .padding.z == room do
            return
        .padding.z = room
        .applyLayout()
        .grid.refreshLayout()
        .layoutTools()
    }

    // Describes the chosen item in `sheet`: its picture, its title and what is known of it, then
    // the file itself; with nothing chosen, the location and how much it holds.
    mtd describeSelection(sheet: *InfoSheet)
    {
        let strings = appStrings()
        if .selected >= .entries.count
        {
            sheet.setTitle(.locationName())
            sheet.setIdentity(.locationText())
            sheet.addText(.status.text())
            return
        }

        let entry = &.entries[.selected]
        if entry.texture.isValid() do
            sheet.setPicture(entry.texture)

        let title = not entry.movie.title.isEmpty() ? entry.movie.title.toString() :
                    (not entry.music.title.isEmpty() ? entry.music.title.toString() : entry.name.toString())
        sheet.setTitle(safeMediaText(title))
        if title != entry.name.toString() do
            sheet.setIdentity(entry.name)
        elif .listing.isArchive
        {
            // A member is placed by the folder of the archive it stands in, and its kind.
            let kind  = String.toUpper(Path.extension(entry.name) orelse "", .Unicode)
            var place = .folder.isEmpty() ? .locationName() : String.from(.folder)
            if place.length and place.back() == '/' do
                place.removeBack()
            place += " /"
            if kind.length > 1 do
                place = Format.toString("% · %", place, kind.toString()[1 to])
            sheet.setIdentity(place)
        }

        // A film is headed by its poster, its title, its year and length, and its rating, the fact
        // a reader of a film comes for, set large with its source as its unit; then the action,
        // what it tells, who made it and played in it, and the file.
        if not entry.movie.title.isEmpty()
        {
            sheet.setPictureBeside(true)
            var identity = String.from(entry.movie.date.toString()[0 until Math.min(entry.movie.date.length, 4'u64)])
            if entry.duration
            {
                if identity.length do
                    identity += " · "
                identity += Format.toString("% min", (entry.duration + 30) / 60)
            }

            sheet.setIdentity(identity)
            if not entry.movie.imdbRating.isEmpty()
            {
                var rating = safeMediaText(entry.movie.imdbRating)
                let slash  = Utf8.indexOf(rating, "/")
                if slash != Swag.U64.Max do
                    rating = String.from(rating.toString()[0 until slash])
                sheet.addFact(rating, "IMDb")
            }

            sheet.setAction(appStrings().cmd_OpenChosen, ViewerCommands.OpenChosen)
            if entry.movie.overview.length do
                sheet.addText(safeMediaText(entry.movie.overview))
            addSheetReading(sheet, strings.explore_Director, entry.movie.director)
            addSheetReading(sheet, strings.explore_Cast, entry.movie.actors)
            let kind = String.toUpper(Path.extension(entry.name) orelse "", .Unicode)
            var file = kind.length > 1 ? String.from(kind.toString()[1 to]) : String.from("")
            if entry.size
            {
                if file.length do
                    file += " · "
                file += StrConv.toDisplaySize(entry.size)
            }

            if file.length do
                sheet.addReading(strings.explore_File, file)
            addSheetReading(sheet, strings.explore_Sources, entry.movie.sources)
            return
        }

        // A rating is the fact a reader of a film comes for, set large with its source as its unit.
        if not entry.movie.imdbRating.isEmpty() do
            sheet.addFact(safeMediaText(entry.movie.imdbRating), "IMDb")

        if not entry.music.title.isEmpty()
        {
            sheet.addSection(strings.explore_MediaDetails)
            addSheetReading(sheet, strings.explore_Artist, entry.music.artist)
            addSheetReading(sheet, strings.explore_FirstRelease, entry.music.date)
            addSheetReading(sheet, strings.explore_Source, "MusicBrainz")
        }

        if .listing.isArchive and entry.archiveIndex < .listing.archive.entries.count
        {
            // A member of an archive, its kind already on the identity line: what it weighs
            // packed and extracted, how well it packed, when, and the checksum it is verified
            // against, all measures in mono.
            let member = &.listing.archive.entries[entry.archiveIndex]
            sheet.addReading(strings.explore_Size, Format.toString("% → %", StrConv.toDisplaySize(member.compressedSize), StrConv.toDisplaySize(member.uncompressedSize)))
            if member.uncompressedSize
            {
                let ratio = cast(u64, Math.round(100 * cast(f64, member.compressedSize) / cast(f64, member.uncompressedSize)))
                sheet.addReading(strings.explore_Compression, Format.toString("% %", ratio, "%"))
            }

            if entry.modified.length do
                sheet.addReading(strings.explore_Modified, entry.modified)
            let crc = Format.toString("%{X08}", member.crc32)
            sheet.addReading("CRC-32", Format.toString("% %", crc.toString()[0 until 4], crc.toString()[4 to]))
        }
        else
        {
            sheet.addSection(strings.explore_FileProperties)
            addSheetReading(sheet, strings.explore_Type, entry.directory ? strings.ui_Folder : (Path.extension(entry.name) orelse ""))
            if not entry.directory do
                addSheetReading(sheet, strings.explore_Size, StrConv.toDisplaySize(entry.size))
            addSheetReading(sheet, strings.explore_Modified, entry.modified)
        }

        if entry.duration do
            addSheetReading(sheet, strings.explore_Duration, formatDuration(entry.duration))
        sheet.setAction(appStrings().cmd_OpenChosen, ViewerCommands.OpenChosen)
        if .listing.isArchive do
            sheet.setSecondaryAction(appStrings().cmd_Extract, ViewerCommands.ExtractChosen)
    }

    // Asks where to extract, then extracts the whole archive into a folder named after it there,
    // or, without `all`, the chosen member or folder of the archive right there.
    mtd chooseExtraction(all: bool)
    {
        if not .listing.isArchive or .extraction.started do
            return
        if not all and .selected >= .entries.count do
            return

        with var options: FileDlgOptions
        {
            .mode  = .SelectFolder
            .title = all ? appStrings().cmd_ExtractAll : appStrings().cmd_Extract
            .state = &me.window.fileDlgState
        }

        let dialog = FileDlg.create(unwrap .window.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let chosen = dialog.selectedPath()
        if all
        {
            let name = Path.fileNameWithoutExtension(.displayPath(.listing.path)) orelse "archive"
            .extractTo(Path.combine(chosen, name), all: true)
        }
        else do
            .extractTo(chosen, all: false)
    }

    // Extracts into `target`: the whole archive with `all`, else the chosen member or folder.
    mtd extractTo(target: string, all: bool)
    {
        if not .listing.isArchive or .extraction.started do
            return
        var members: Array'Viewers.Archive.ZipEntry
        var strip:   String
        if all
        {
            members = .listing.archive.entries
        }
        else
        {
            if .selected >= .entries.count do
                return
            let entry = &.entries[.selected]
            strip = .folder
            if entry.directory
            {
                for &member in .listing.archive.entries where Utf8.startsWith(member.path, entry.path) do
                    members.add(member[])
            }
            elif entry.archiveIndex < .listing.archive.entries.count
            {
                members.add(.listing.archive.entries[entry.archiveIndex])
            }
        }

        .extraction.start(.listing.path, #move members, strip, target, me)
    }

    // Says how the extraction went, in a toast over the page.
    private mtd finishExtraction()
    {
        .extraction.wait()
        let text = appStrings()
        if not .toast do
            .toast = Toast.create(me, "scope.explorer.toast")
        if not .extraction.error.isEmpty()
        {
            .toast.show(text.explore_ExtractFailed, .extraction.error, .Failure)
            return
        }

        var message: String
        if .extraction.written == 1 do
            message = String.from(text.explore_ExtractedOne)
        else do
            message = Format.toString(text.explore_Extracted, .extraction.written)
        if .extraction.kept do
            message = Format.toString(text.explore_ExtractedKept, message, .extraction.kept)
        .toast.show(message, .extraction.target)
    }

    // Gives the keyboard to the listing, in whichever form it is shown.
    mtd focusContent()
    {
        if .mode == .Names or .mode == .Details do
            .list.setFocus()
        else do
            .grid.setFocus()
    }

    mtd retranslate()
    {
        let text = appStrings()
        .showMediaInfo()
        .filter.setPlaceholder(text.ui_FilterFiles)
        .list.header.itemAt(0).name = text.explore_Name
        .list.header.itemAt(1).name = text.explore_Type
        .list.header.itemAt(2).name = text.explore_Size
        .list.header.itemAt(3).name = text.explore_Modified
        .refreshQuietMenus()
    }

    mtd navigate(path: string, folder: string = "", remember = true)
    {
        .generation  += 1
        .bypassCache = false
        .suspend()
        .pendingOpen     = Swag.U64.Max
        .requested       = path
        .requestedFolder = folder
        if remember do
            .history.push(Format.toString("%\n%", path, folder))
        .setStatus(appStrings().explore_Loading)
        if not .load.started do
            .startListing()
    }

    // Lists the folder again and renders its previews anew instead of reading them from the cache.
    //
    // The cache already follows a file that changed, so a forced refresh is what the user reaches
    // for when a preview is wrong anyway; the previews it renders replace the cached ones.
    mtd forceRefresh()
    {
        .navigate(.listing.path, .folder, false)
        .bypassCache = true
    }

    private mtd startListing()
    {
        .load.start(.requested, .requestedFolder, .sortColumn, .descending, me)
    }

    private mtd visit(location: string)
    {
        let split = Utf8.indexOf(location, "\n")
        .navigate(location[0 until split], location[split + 1 to], false)
    }

    mtd navigateBreadcrumb(location: string)
    {
        let split = Utf8.indexOf(location, "\n")
        .navigate(location[0 until split], location[split + 1 to])
    }

    // Returns the explored location as one path: the folder, or the archive and the folder inside it.
    mtd locationText()->String
    {
        let path = .displayPath(.listing.path)
        if .folder.isEmpty() do
            return path
        return Format.toString("%/%", path, .folder)
    }

    // Goes to a location typed into the address: the folder or archive it names, a folder inside
    // the archive on show, or the file it names, which opens as any other file does.
    //
    // A path copied from the system file browser comes between quotes, which are not part of it.
    mtd navigateTyped(text: string)
    {
        var typed = Latin1.trim(text)
        if typed.count >= 2 and typed[0] == '"'u8 and typed[typed.count - 1] == '"'u8 do
            typed = typed[1 until typed.count - 1]
        if typed.count == 0 or .locationText() == typed do
            return

        if .listing.isArchive
        {
            let archive = .displayPath(.listing.path)
            if Utf8.startsWith(typed, archive) and (typed.count == archive.count or typed[archive.count] == '/'u8)
            {
                var folder = typed[archive.count to]
                while folder.count and folder[0] == '/'u8 do
                    folder = folder[1 to]
                if folder.count and folder[folder.count - 1] != '/'u8 do
                    .navigate(.listing.path, Format.toString("%/", folder))
                else do
                    .navigate(.listing.path, folder)
                return
            }
        }

        if Directory.exists(typed) do
            .navigate(typed)
        elif File.exists(typed) do
            .window.queueFile(typed)
        else do
            .setStatus(appStrings().explore_NotFound)
    }

    mtd updateBreadcrumb()
    {
        let breadcrumb = .address.breadcrumb
        breadcrumb.clear()
        var ancestors: Array'String
        var path = .listing.path.toString()
        while path.count
        {
            ancestors.add(path)
            let parent = Path.directoryName(path) orelse ""
            if not parent.count or parent == path do
                break
            path = parent
        }

        // The breadcrumb names the levels above the page; the page's own name is its title.
        let skipLast = not .listing.isArchive or .folder.isEmpty()
        for ancestor, rank in ancestors.reversed()
        {
            if skipLast and rank + 1 == ancestors.count do
                break
            let full = ancestor.toString()
            let name = Path.fileName(full) orelse full
            breadcrumb.addItem(name.count ? name : full, tag: Format.toString("%\n", full))
        }

        if .listing.isArchive
        {
            var begin: u64
            let last = .folder.length ? .folder.length - 1 : 0
            for offset in .folder.length where .folder[offset] == '/'u8 and offset != last
            {
                breadcrumb.addItem(.folder.toString()[begin until offset],
                                   tag: Format.toString("%\n%", .listing.path, .folder.toString()[0 until offset + 1]))
                begin = offset + 1
            }
        }

        breadcrumb.toolTip = .locationText()
        .address.refreshPath()
        .title.setText(.locationName())
        .window.refreshTitle()
    }

    mtd fillBreadcrumbMenu(index: u64, menu: *MenuCtrl)
    {
        let breadcrumb = .address.breadcrumb
        if index >= breadcrumb.items.count do
            return
        let location = breadcrumb.items[index].tag.toString()
        let split    = Utf8.indexOf(location, "\n")
        let path     = location[0 until split]
        let folder   = location[split + 1 to]
        var children: Array'ExplorerEntry
        if .listing.isArchive and path == .listing.path.toString()
        {
            children = .listing.children(folder)
        }
        else
        {
            let directories = catch Directory.enumerateDirectories(path)
            {
                return
            }

            for directory in directories do
                children.add({name: Path.fileName(directory.fullName) orelse directory.fullName.toString(),
                              path: directory.fullName, directory: true})
        }

        children.sort(func(a, b)->s32 { return Latin1.compareNatural(a.name, b.name) })
        .menuPaths.clear()
        .menuPaths.reserve(children.count)
        for &child in children where child.directory
        {
            let target = .listing.isArchive and path == .listing.path.toString() ?
                         Format.toString("%\n%", path, child.path) : Format.toString("%\n", child.path)
            .menuPaths.add(target)
        }

        var item: u64
        for &child in children where child.directory
        {
            let target   = .menuPaths[item].toString()
            let selected = index + 1 < breadcrumb.items.count and breadcrumb.items[index + 1].tag == target
            menu.addItem(child.name, target, checked: selected)
            item += 1
        }
    }

    mtd goBack()
    {
        if .history.canGoBack() do
            .visit(.history.goBack())
    }

    mtd goForward()
    {
        if .history.canGoForward() do
            .visit(.history.goForward())
    }

    mtd goUp()
    {
        if .listing.isArchive and not .folder.isEmpty()
        {
            let trimmed = .folder.toString()[0 until .folder.length - 1]
            let parent  = Path.directoryName(trimmed) orelse ""
            .navigate(.listing.path, parent.count ? Format.toString("%/", parent) : {})
        }
        else
        {
            if .listing.isArchive and .history.canGoBack()
            {
                .goBack()
            }
            else
            {
                let parent = Path.directoryName(.listing.path) orelse ""
                if parent.count do
                    .navigate(parent)
            }
        }
    }

    private mtd clearTextures()
    {
        for &entry in .entries where entry.texture.isValid() do
            .app().renderer.removeTexture(&entry.texture)
        .cached.clear()
    }

    private mtd publish()
    {
        .clearTextures()
        let entering = .listing.isArchive and not .grid.rows
        .entries  = #move .listing.entries
        .selected = Swag.U64.Max
        .showMediaInfo()
        .previewAspect = .listingPreviewAspect()
        .previewBudget = Directory.isRemote(.listing.path) ? Math.min(ExplorerRemoteWorkerCount, .previews.count) : .previews.count
        .updateBreadcrumb()

        .filter.setText("", notify: false)
        .list.header.setSortIndicator(.sortColumn, .descending ? .Descending : .Ascending)
        if entering do
            .setMode(.Details)
        elif not .listing.isArchive and .grid.rows do
            .setMode(.mode)
        .window.teachHints(.isLocallyVisible())
        .fill()
        .scroll.setScrollPos(0, 0)
        .window.refreshFileLists()
    }

    // Chooses the shape of the tiles from the files listed, before any preview exists.
    //
    // A page-shaped tile leaves most of itself empty around a film, and a folder of films is a row of
    // screens; deciding from the names keeps the grid from changing shape while previews arrive.
    mtd listingPreviewAspect()->f32
    {
        var files, films: u64
        for &entry in .entries where not entry.directory
        {
            files += 1
            var pluginIndex: u64
            if .window.index.namePlugin(entry.path, &pluginIndex) and .window.index.plugins[pluginIndex].key == "video" do
                films += 1
        }

        if films * 2 > files do
            return .window.onlineMovies ? ExplorerTilePreviewAspect : ExplorerFilmPreviewAspect
        return ExplorerTilePreviewAspect
    }

    // Reports whether the folder is mostly films whose posters are looked up, which the grid
    // shows upright.
    mtd listingIsFilms()->bool
    {
        if not .window.onlineMovies or .listing.isArchive do
            return false
        var files, films: u64
        for &entry in .entries where not entry.directory
        {
            files += 1
            var pluginIndex: u64
            if .window.index.namePlugin(entry.path, &pluginIndex) and .window.index.plugins[pluginIndex].key == "video" do
                films += 1
        }

        return films * 2 > files
    }

    mtd entryIcon(index: u64, size: f32 = 16)->Icon
    {
        let entry = &.entries[index]
        if entry.directory do
            return .theme().icon(.Folder, size)
        var pluginIndex: u64
        if .window.index.namePlugin(entry.path, &pluginIndex) do
            return .window.pluginIcon(&.window.index.plugins[pluginIndex], size)
        return .theme().icon(.OpenFile, size)
    }

    mtd fill()
    {
        .grid.hovered = Swag.U64.Max
        .shown.clear()
        .list.clear()
        let query = .filter.text()
        for &entry, index in .entries
        {
            if query.count and Utf8.indexOf(entry.name, query, comparisonType: .Latin1NoCase) == Swag.U64.Max do
                continue
            .shown.add(index)
        }

        var count: String
        switch .shown.count
        {
        case 0:  count = appStrings().explore_Empty
        case 1:  count = appStrings().explore_OneItem
        default: count = Format.toString(appStrings().explore_Count, .shown.count)
        }

        // A folder says what its files weigh; an archive what it weighs packed and what it will
        // weigh once extracted.
        if not .listing.isArchive and .shown.count
        {
            var weight = 0'u64
            for index in .shown where not .entries[index].directory do
                weight += .entries[index].size
            if weight do
                count = Format.toString("% · %", count, StrConv.toDisplaySize(weight))
        }

        if .listing.isArchive and .shown.count
        {
            let zip = &.listing.archive
            count = Format.toString(appStrings().explore_ArchiveSummary, count, StrConv.toDisplaySize(zip.compressedSize), StrConv.toDisplaySize(zip.uncompressedSize))
        }

        .setStatus(count)

        .list.setVirtualCount(cast(u32, .shown.count))
        for index, row in .shown where index == .selected
        {
            .list.setFocusedIndex(cast(u32, row), ensureVisible: false)
            .list.selectLine(cast(u32, row))
            break
        }

        .grid.refreshLayout()
        .requestPreview()
        .window.teachHints(.isLocallyVisible())
    }

    mtd setMode(mode: ExplorerMode)
    {
        .mode = mode
        .refreshQuietMenus()

        // An archive reads as quiet rows — its glyph, its name, how well it packed, its size and
        // its date — where a folder shows its columns.
        .grid.rows = mode == .Details and .listing.isArchive
        let rows = (mode == .Names or mode == .Details) and not .grid.rows
        .list.show(rows)
        .list.header.show(mode == .Details)
        .scroll.show(not rows)
        .applyLayout()
        .fill()
    }

    mtd suspend()
    {
        for &preview in .previews
        {
            if preview.started and preview.generation == .generation and preview.index < .entries.count do
                .entries[preview.index].attempted = false
            preview.task.cancel()
        }
    }

    mtd leave()
    {
        .suspend()
        .generation  += 1
        .pendingOpen = Swag.U64.Max
    }

    mtd displayPath(path: string)->string
    {
        for file in .temporaryFiles where file.file == path do
            return file.title
        return path
    }

    // Called only after the foreground viewer has retired. Archive sources retained by navigation stay alive.
    mtd releasePreviews()
    {
        for index in reversed(.temporaryFiles.count)
        {
            let file     = &.temporaryFiles[index]
            var retained = .listing.path == file.file
            for location in .history.entries where Utf8.startsWith(location[], file.file) do
                retained = true
            if retained do
                continue
            catch File.delete(file.file)
            .temporaryFiles.removeAtOrdered(index)
        }
    }

    private mtd prioritizeVisible()
    {
        .grid.hovered = Swag.U64.Max
        for &preview in .previews where preview.started and not preview.opening
        {
            let range   = .grid.visibleRange()
            var visible = false
            for row in range.first until range.end where .shown[row] == preview.index do
                visible = true
            if not visible
            {
                if preview.generation == .generation and preview.index < .entries.count do
                    .entries[preview.index].attempted = false
                preview.task.cancel()
            }
        }

        .requestPreview()
    }

    mtd activate(index: u64)
    {
        if .load.started or index >= .entries.count do
            return
        let entry = &.entries[index]
        if entry.directory
        {
            if not .isLocallyVisible() do
                .window.closeFile()
            if .listing.isArchive do
                .navigate(.listing.path, entry.path)
            else do
                .navigate(entry.path)
        }
        elif .listing.isArchive
        {
            .leave()
            .pendingOpen = index
            .requestPreview()
        }
        else
        {
            .window.queueFile(entry.path)
        }
    }

    // Keep every independent renderer busy on visible tiles, with at most 128 uploaded previews.
    mtd requestPreview()
    {
        .refreshPreviewSettings()
        var running = 0'u64
        for &preview in .previews where preview.started do
            running += 1
        for &preview in .previews where not preview.started
        {
            // Opening a file is what the user waits for; only background previews keep the budget.
            if running >= .previewBudget and .pendingOpen == Swag.U64.Max do
                break
            .startPreview(preview)
            if preview.started do
                running += 1
        }
    }

    mtd refreshPreviewSettings()
    {
        let settings = ThumbnailSettings.capture(.window)
        if .previewSettings == settings do
            return

        // The first snapshot precedes all jobs; later changes retire every old publication.
        if not .previewSettings.isEmpty() do
            .retirePreviews()

        .previewSettings = settings
    }

    private mtd retirePreviews()
    {
        // Extracting an opened archive member does not depend on its thumbnail appearance.
        for &preview in .previews
        {
            if preview.opening and preview.generation == .generation do
                preview.generation += 1
            else do
                preview.task.cancel()
        }

        .generation += 1
        .clearTextures()
        for &entry in .entries
        {
            entry.attempted = false
            entry.movie     = {}
            entry.music     = {}
        }

        .showMediaInfo()
        .grid.invalidate()
    }

    // Returns the active slot for a tile, including work waiting for GUI publication.
    mtd previewSlot(index: u64)->u64
    {
        for &preview, slot in .previews where preview.started and
                                              not preview.opening and
                                              preview.generation == .generation and
                                              preview.index == index do
            return slot
        return Swag.U64.Max
    }

    private mtd startPreview(preview: *ExplorerPreview)
    {
        if .load.started or (not .isVisible() and .pendingOpen == Swag.U64.Max) do
            return
        var wanted  = .pendingOpen
        let opening = wanted != Swag.U64.Max
        if not opening
        {
            if .mode == .Names or .mode == .Details
            {
                if .selected >= .entries.count do
                    return
                let selected = &.entries[.selected]
                let movie    = .window.onlineMovies and Reader.canOpen(selected.path)
                let music    = .window.onlineMusic and (Path.hasExtension(selected.path, ".mp3") or Path.hasExtension(selected.path, ".flac"))
                if selected.directory or
                   selected.attempted or
                   not (movie or music or .grid.rows) or
                   .previewSlot(.selected) != Swag.U64.Max do
                    return
                wanted = .selected
            }
            else
            {
                let range = .grid.visibleRange()
                for row in Math.min(range.first, .shown.count) until Math.min(range.end, .shown.count)
                {
                    let index = .shown[row]
                    if index < .entries.count and not .entries[index].directory and
                       not .entries[index].attempted and
                       .previewSlot(index) == Swag.U64.Max
                    {
                        wanted = index
                        break
                    }
                }
            }
        }

        if wanted >= .entries.count do
            return
        if not opening and .cached.count >= 128
        {
            let range = .grid.visibleRange()
            var evict = Swag.U64.Max
            for cached, position in .cached
            {
                var visible = false
                for row in Math.min(range.first, .shown.count) until Math.min(range.end, .shown.count) where .shown[row] == cached do
                    visible = true
                if not visible
                {
                    evict = position
                    break
                }
            }

            if evict == Swag.U64.Max do
                return
            let old = .cached[evict]
            .app().renderer.removeTexture(&.entries[old].texture)
            .entries[old].attempted = false
            .cached.removeAtOrdered(evict)
            if old == .selected do
                .showMediaInfo()
        }

        let entry = &.entries[wanted]
        if .listing.isArchive and entry.archiveIndex >= .listing.archive.entries.count do
            return
        .pendingOpen        = Swag.U64.Max
        preview.path        = entry.path
        preview.index       = wanted
        preview.generation  = .generation
        preview.opening     = opening
        preview.bypassCache = .bypassCache
        preview.settings    = ThumbnailSettings.capture(.window, entry)
        preview.archivePath = .listing.isArchive ? .listing.path : {}
        if .listing.isArchive do
            preview.entry = .listing.archive.entries[entry.archiveIndex]
        entry.attempted = true
        preview.start(me)
        .grid.invalidate()
    }
}

impl IWnd for Explorer
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if .extraction.claim(evt)
        {
            .finishExtraction()
            return
        }

        if .load.claim(evt)
        {
            var listing: ExplorerListing
            let error = .load.finish(&listing)
            if .load.path != .requested or
               .load.folder != .requestedFolder or
               .load.sortColumn != .sortColumn or
               .load.descending != .descending
            {
                .startListing()
                return
            }

            if not error.isEmpty()
            {
                .setStatus(error)
                return
            }

            .listing = #move listing
            .folder  = .requestedFolder
            .publish()
        }
        else
        {
            for &preview, slot in .previews where preview.claim(evt)
            {
                preview.wait()
                .refreshPreviewSettings()
                .grid.spinners[slot].hide()
                .grid.invalidate()
                if preview.generation != .generation and not preview.temporary.isEmpty()
                {
                    catch File.delete(preview.temporary)
                    preview.temporary.clear()
                }

                if not preview.temporary.isEmpty()
                {
                    let title = Format.toString("% / %", .displayPath(preview.archivePath), preview.path)
                    .temporaryFiles.add(ExplorerTemporary{#move preview.temporary, title})
                }

                if preview.generation == .generation
                {
                    if preview.opening
                    {
                        if preview.error.isEmpty() and not .temporaryFiles.isEmpty() do
                            .window.queueFile(.temporaryFiles.back().file, remember: false)
                        else do
                            .setStatus(preview.error)
                    }
                    elif preview.image.isValid()
                    {
                        if preview.index == .selected and not preview.error.isEmpty() do
                            .setStatus(preview.error)
                        if .cached.count >= 128
                        {
                            let old = .cached[0]
                            .app().renderer.removeTexture(&.entries[old].texture)
                            .entries[old].attempted = false
                            .cached.removeAtOrdered(0)
                            if old == .selected do
                                .showMediaInfo()
                        }

                        .entries[preview.index].texture  = .app().renderer.addImage(preview.image)
                        .entries[preview.index].duration = thumbnailDuration(&preview.image)
                        .entries[preview.index].movie    = MovieSummary.fromImage(&preview.image)
                        .entries[preview.index].music    = MusicSummary.fromImage(&preview.image)
                        if .selected == preview.index do
                            .showMediaInfo()
                        .cached.add(preview.index)
                        .grid.invalidate()
                    }
                }

                .requestPreview()
                return
            }

            evt.accepted = false
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        for &preview in .previews do
            preview.task.cancel()
        for &preview in .previews do
            preview.wait()
        .clearTextures()
        for file in .temporaryFiles do
            catch File.delete(file.file)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .retranslate()
            .fill()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .F5:                                  .forceRefresh()
        case .L where evt.modifiers.has(.Control): .address.beginEdit()
        case .D where evt.modifiers.has(.Alt):     .address.beginEdit()
        case .Left where evt.modifiers.has(.Alt):  .goBack()
        case .Right where evt.modifiers.has(.Alt): .goForward()
        case .Up where evt.modifiers.has(.Alt):    .goUp()
        case .Back:                                .goUp()
        case .Oem2 where evt.modifiers == .None:   .revealFilter()
        default:                                   evt.accepted = false
        }
    }
}

// Adds a reading of `value` under `label` to the sheet, unless nothing is known of it.
private func addSheetReading(sheet: *InfoSheet, label, value: string)
{
    if value.count do
        sheet.addReading(label, safeMediaText(value), mono: false)
}

// A virtual tile viewport: one painted cell per visible file, independent of directory size.
struct ExplorerGrid
{
    using wnd:     Wnd
    late explorer: *Explorer
    columns:       u64        = 1
    cell:          Math.Point = {160, 152}
    hovered:       u64        = Swag.U64.Max
    spinners:      Array'(*Spinner)
    busy:          Array'bool     // Which spinners a visible tile claimed during the current paint.
    nameTimer:     *Timer?
    nameTick:      u64
    rows:          bool     // Whether the entries stand one per line, as an archive lists them.
    posters:       bool     // Whether the tiles stand upright, as the posters of a folder of films.
    tile:          Math.Point = {160, 142}
}

impl ExplorerGrid
{
    // The air a cell keeps around its tile, the height of the name and of the mono line of what
    // is known of the item under its picture, and the weight of the ring around the chosen one.
    const CellInset     = 12.0
    const NameHeight    = 22.0
    const ReadingHeight = 16.0
    const RingWeight    = 2.0

    // The tiles: the air between two of them, the narrowest a tile gets and its height over its
    // width, upright for posters; and the band under a tile for its name and its facts.
    const Gap          = 24.0
    const TileWidth    = 160.0
    const TileAspect   = 0.885
    const PosterWidth  = 170.0
    const PosterAspect = 1.38
    const TextBand     = 72.0

    // The rows of an archive: their pitch, the length of the bar of the compression ratio, and the
    // columns of the size and the date from the end of the row.
    const RowPitch   = 34.0
    const RatioWidth = 64.0
    const DateColumn = 136.0
    const SizeColumn = 96.0

    mtd rowAt(point: Math.Point)->u64
    {
        let local = point + .scrollPos - Math.Point{CellInset, CellInset}
        if local.x < 0 or local.y < 0 do
            return Swag.U64.Max
        let column = cast(u64, local.x / .cell.x)
        let line   = cast(u64, local.y / .cell.y)
        let row    = line * .columns + column
        if column >= .columns or
           row >= .explorer.shown.count or
           local.x - cast(f32, column) * .cell.x >= .cell.x - (.rows ? 0 : Gap) or
           local.y - cast(f32, line) * .cell.y >= .cell.y - (.rows ? 0 : Gap) do
            return Swag.U64.Max
        return row
    }

    mtd refreshLayout()
    {
        if .rows
        {
            .columns = 1
            .cell    = Math.Point{Math.max(.clientRect().width - 2 * CellInset, 200), RowPitch}
            .explorer.scroll.setScrollSize(0, cast(f32, .explorer.shown.count) * RowPitch + 2 * CellInset)
            .invalidate()
            return
        }

        // Every tile has the same size and the grid fills the width of the page: as many columns
        // as the narrowest tile allows, the tiles sharing what is left. A folder of films stands
        // its posters upright; anything else on a tile a little wider than tall.
        .posters = .explorer.listingIsFilms()
        var narrowest = .posters ? PosterWidth : TileWidth
        switch .explorer.mode
        {
        case .Small: narrowest *= 0.75
        case .Large: narrowest *= 1.4
        }

        let room = Math.max(.clientRect().width - 2 * CellInset, narrowest)
        .columns = Math.max(1'u64, cast(u64, (room + Gap) / (narrowest + Gap)))
        let width = Math.floor((room - Gap * cast(f32, .columns - 1)) / cast(f32, .columns))
        .tile = Math.Point{width, Math.round(width * cast(f32, .posters ? PosterAspect : TileAspect))}
        .cell = Math.Point{width + Gap, .tile.y + TextBand}
        let rows = (.explorer.shown.count + .columns - 1) / .columns
        .explorer.scroll.setScrollSize(0, cast(f32, rows) * .cell.y + 2 * CellInset)
        .invalidate()
    }

    // Returns where the tile of `row` stands in the grid.
    mtd tileRect(row: u64)->Math.Rectangle
    {
        return Math.Rectangle{CellInset + cast(f32, row % .columns) * .cell.x,
                              CellInset + cast(f32, row / .columns) * .cell.y, .tile.x, .tile.y}
    }

    // Paints the tile of `row`: its ground, what the item shows, the Arc ring of the chosen one,
    // then its name and one mono line of its facts under it.
    //
    // A picture, a film or a poster fills its tile, cropped to its shape; any other preview stands
    // whole on the ground of the tile. An item without a preview shows the faint page glyph of its
    // kind, a file its extension in faint mono at the foot of the tile.
    mtd paintTile(painter: *Painter, row: u64)
    {
        let index   = .explorer.shown[row]
        let entry   = &.explorer.entries[index]
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let tile    = .tileRect(row)
        let radius  = metrics.corner_Control
        let slot    = .explorer.previewSlot(index)
        painter.setAntialiased(true)

        // The chosen item is ringed in Arc, the ring standing just off its tile.
        if .explorer.selected == index
        {
            var ring = tile
            ring.inflate(RingWeight + 1)
            painter.drawRoundRect(ring, radius + RingWeight + 1, radius + RingWeight + 1, colors.arc, RingWeight)
        }

        painter.fillRoundRect(tile, radius, radius, colors.raised)
        let glyph = .theme().fileGlyph(entry.name, entry.directory, 32)
        if entry.texture.isValid()
        {
            let texture = entry.texture
            let fills   = .posters or glyph.index == cast(s32, ThemeIcons.FileImage) or glyph.index == cast(s32, ThemeIcons.FileVideo)
            if fills
            {
                // Crop the picture to the shape of the tile, around its centre.
                let tw     = cast(f32, texture.width)
                let th     = cast(f32, texture.height)
                let scale  = Math.max(tile.width / tw, tile.height / th)
                let sw     = tile.width / scale
                let sh     = tile.height / scale
                var brush  = Brush.createTexture(texture)
                brush.uvMode = .FillSubRect
                brush.uvRect = Math.Rectangle{(tw - sw) * 0.5, (th - sh) * 0.5, sw, sh}
                painter.fillRoundRect(tile, radius, radius, brush)
            }
            else
            {
                var room = tile
                room.inflate(-12)
                let scale  = Math.min(room.width / cast(f32, texture.width), room.height / cast(f32, texture.height))
                let width  = Math.round(cast(f32, texture.width) * scale)
                let height = Math.round(cast(f32, texture.height) * scale)
                let card   = Math.Rectangle{Math.round(room.horzCenter() - width * 0.5), Math.round(room.vertCenter() - height * 0.5), width, height}
                painter.fillRoundRect(card, 2, 2, Brush.createTexture(texture))
            }

            .paintDuration(painter, tile, entry)
        }
        elif slot != Swag.U64.Max
        {
            let size = metrics.spinner_Size
            .spinners[slot].setPosition(Math.Rectangle{tile.horzCenter() - size / 2, tile.vertCenter() - size / 2, size, size}, computeLayout: false)
            .busy[slot] = true
        }
        else
        {
            glyph.paint(painter, Math.round(tile.horzCenter() - 16), Math.round(tile.vertCenter() - 16), glyph.color.a ? glyph.color : colors.faintText)
            let ext = entry.directory ? "" : (Path.extension(entry.name) orelse "")
            if ext.count
            {
                let mono = .theme().createDefaultFontFs(11)
                painter.drawString(tile.x + 12, mono.opticalLineTop(tile.bottom() - 16), ext, mono, colors.faintText)
            }
        }

        // The name, left on the edge of the tile, and the facts under it: what the item measures
        // at the left, what it weighs at the right.
        let font = unwrap .font().regular
        let mono = .theme().createDefaultFontFs(11)
        let nameRect = Math.Rectangle{tile.x, tile.bottom() + 8, tile.width, 20}
        .paintName(painter, nameRect, row, index, font, .posters and entry.movie.title.length ? entry.movie.title.toString() : entry.name.toString())

        let factsY = mono.opticalLineTop(tile.bottom() + 37)
        let size   = .sizeText(entry)
        var right  = tile.right()
        if size.length
        {
            right -= Painter.measureString(size, mono).width
            painter.drawString(right, factsY, size, mono, colors.faintText)
            right -= 12
        }

        let facts = .reading(entry)
        if facts.length
        {
            painter.pushClippingRect(Math.Rectangle{tile.x, tile.bottom() + 28, Math.max(right - tile.x, 0), 18})
            painter.drawString(tile.x, factsY, facts, mono, colors.faintText)
            painter.popClippingRect()
        }
    }

    // Writes the duration of a film in a mono chip at the corner of its tile.
    mtd paintDuration(painter: *Painter, tile: Math.Rectangle, entry: const *ExplorerEntry)
    {
        if not entry.duration or .posters do
            return
        let label = formatDuration(entry.duration)
        let font  = .theme().createDefaultFontFs(ExplorerDurationFontSize, .Bold)
        let text  = Painter.measureString(label, font)
        var chip  = Math.Rectangle{0, 0, Math.round(text.width) + 12, Math.round(font.height) + 4}
        if chip.width + 16 > tile.width or chip.height + 16 > tile.height do
            return
        chip.x = tile.right() - chip.width - 8
        chip.y = tile.bottom() - chip.height - 8
        painter.fillRoundRect(chip, 4, 4, Color.fromArgb(ExplorerDurationGround))
        painter.drawString(chip.x + 6, font.opticalLineTop(chip.vertCenter()), label, font, Color.fromArgb(ExplorerDurationInk))
    }

    // Writes the name of a tile, left on its edge, travelling when it is longer than the tile and
    // the item is hovered or chosen.
    mtd paintName(painter: *Painter, nameRect: Math.Rectangle, row, index: u64, font: *Font, text: string)
    {
        let width   = Painter.measureString(text, font).width
        let scrolls = width > nameRect.width and (.hovered == row or .explorer.selected == index)
        var name: RichString = text
        var format: RichStringFormat
        format.font = .font()
        me.theme().setTextColors(&format, me.themeColors().text)
        format.horzAlignment = .Left
        if scrolls
        {
            // Pause at each end before traveling back, so the beginning remains easy to read.
            let distance = cast(u64, Math.ceil(width - nameRect.width))
            let phase    = .nameTick % (distance * 2 + 40)
            var offset: u64
            if phase > 20 and phase <= distance + 20 do
                offset = phase - 20
            elif phase > distance + 20 and phase <= distance + 40 do
                offset = distance
            elif phase > distance + 40 do
                offset = distance * 2 + 40 - phase
            var moving = nameRect
            moving.x -= cast(f32, offset)
            moving.width = Math.ceil(width) + 1
            painter.pushClippingRect(nameRect)
            painter.drawRichString(moving, &name, format)
            painter.popClippingRect()
        }
        else
        {
            format.flags = .Ellipsis
            painter.drawRichString(nameRect, &name, format)
        }
    }

    // Returns what a file weighs, written at the right of its facts; nothing for a folder.
    mtd sizeText(entry: const *ExplorerEntry)->String
    {
        if entry.directory or not entry.size or .posters do
            return {}
        return StrConv.toDisplaySize(entry.size)
    }

    // Paints the entries `first` until `end` as rows: the glyph, the name, a thin Arc bar of how
    // much the member packed, the size and the date in mono, a folder its count instead.
    mtd paintRows(painter: *Painter, first, end: u64)
    {
        let explorer = .explorer
        let colors   = .themeColors()
        let metrics  = .themeMetrics()
        let body     = .theme().createDefaultFont(14)
        let mono     = .theme().createDefaultFontFs(11)
        painter.setAntialiased(true)
        for row in first until end
        {
            let index   = explorer.shown[row]
            let entry   = &explorer.entries[index]
            let rect    = Math.Rectangle{CellInset, CellInset + cast(f32, row) * .cell.y, .cell.x, .cell.y}
            let centerY = rect.vertCenter()
            if explorer.selected == index do
                painter.fillRoundRect(rect, metrics.corner_Control, metrics.corner_Control, colors.selection)
            elif .hovered == row do
                painter.fillRoundRect(rect, metrics.corner_Control, metrics.corner_Control, colors.raised)

            let glyph = explorer.entryIcon(index, metrics.menuPopup_IconSize)
            glyph.paint(painter, rect.x + 12, Math.round(centerY - glyph.sizeY * 0.5), colors.softText)

            let dateRight = rect.right() - 12
            let sizeRight = dateRight - DateColumn
            let barRight  = sizeRight - SizeColumn
            painter.pushClippingRect(Math.Rectangle{rect.x + 36, rect.y, Math.max(barRight - RatioWidth - 16 - rect.x - 36, 0), rect.height})
            painter.drawString(rect.x + 36, body.opticalLineTop(centerY), entry.name, body, colors.text)
            painter.popClippingRect()

            let date = entry.modified.toString()[0 until Math.min(entry.modified.length, 10)]
            painter.drawString(dateRight - Painter.measureString(date, mono).width, mono.opticalLineTop(centerY), date, mono, colors.faintText)

            var size: String
            if entry.directory
            {
                let children = explorer.listing.isArchive ? explorer.listing.children(entry.path).count : 0
                size = children == 1 ? String.from(appStrings().explore_OneItem) : Format.toString(appStrings().explore_Count, children)
            }
            else
            {
                size = StrConv.toDisplaySize(entry.size)
                if explorer.listing.isArchive and entry.archiveIndex < explorer.listing.archive.entries.count
                {
                    let member = &explorer.listing.archive.entries[entry.archiveIndex]
                    if member.uncompressedSize
                    {
                        let ratio = Math.clamp(cast(f32, member.compressedSize) / cast(f32, member.uncompressedSize), 0, 1)
                        let track = Math.Rectangle{barRight - RatioWidth, Math.round(centerY - 1.5), RatioWidth, 3}
                        painter.fillRoundRect(track, 1.5, 1.5, colors.raised)
                        painter.fillRoundRect(Math.Rectangle{track.x, track.y, Math.max(Math.round(RatioWidth * ratio), 3), 3}, 1.5, 1.5, colors.arc)
                    }
                }
            }

            painter.drawString(sizeRight - Painter.measureString(size, mono).width, mono.opticalLineTop(centerY), size, mono, colors.faintText)
        }
    }

    // Returns the facts written under the name of a tile, at the left: the year and length of a
    // film, the length of anything else that plays, how many items a folder holds.
    mtd reading(entry: const *ExplorerEntry)->String
    {
        var result: #returntype
        if entry.directory
        {
            if entry.children == 1 do
                result = String.from(appStrings().explore_OneItem)
            elif entry.children != Swag.U64.Max do
                result = Format.toString(appStrings().explore_Count, entry.children)
            return result
        }

        if not entry.movie.date.isEmpty() do
            result = entry.movie.date.toString()[0 until Math.min(entry.movie.date.length, 4'u64)]
        if entry.duration
        {
            if not result.isEmpty() do
                result += " · "

            // A film is as long as its hours and minutes, the way a programme lists it.
            if .posters and entry.duration >= 3600 do
                result += Format.toString(appStrings().explore_Length, entry.duration / 3600, Format.toString("%{02}", (entry.duration / 60) % 60))
            else do
                result += formatDuration(entry.duration)
        }

        return result
    }

    mtd visibleRange()->{first: u64, end: u64}
    {
        let first = cast(u64, Math.max(0.0, .scrollPos.y - CellInset) / .cell.y) * .columns
        let rows  = cast(u64, Math.max(0.0, .clientRect().height) / .cell.y) + 2
        return {first: Math.min(first, .explorer.shown.count), end: Math.min(first + rows * .columns, .explorer.shown.count)}
    }

    mtd startNameScroll()
    {
        .nameTick = 0
        let font = unwrap .font().regular
        var needsTimer = false
        for index, row in .explorer.shown where row == .hovered or index == .explorer.selected
        {
            if Painter.measureString(.explorer.entries[index].name, font).width > .cell.x - 16 do
                needsTimer = true
        }

        if needsTimer and not .nameTimer do
            .nameTimer = .addTimer(50'ms)
        elif not needsTimer and .nameTimer do
            .stopTimer(&.nameTimer)
    }

    mtd select(row: u64)
    {
        if row >= .explorer.shown.count do
            return
        .explorer.selected = .explorer.shown[row]
        .startNameScroll()
        .explorer.showMediaInfo()
        if .rows do
            .explorer.requestPreview()
        let top = CellInset + cast(f32, row / .columns) * .cell.y
        if top < .scrollPos.y do
            .explorer.scroll.setScrollPos(0, top)
        elif top + .cell.y > .scrollPos.y + .clientRect().height do
            .explorer.scroll.setScrollPos(0, top + .cell.y - .clientRect().height)
        .invalidate()
    }
}

impl IWnd for ExplorerGrid
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .nameTimer
        {
            .nameTick += 1
            .invalidate()
        }
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .explorer != null do
            .refreshLayout()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let range   = .visibleRange()
        if .rows
        {
            .paintRows(painter, range.first, range.end)
            for spinner in .spinners do
                spinner.hide()
            return
        }

        .busy.fill(false)
        for row in range.first until range.end do
            .paintTile(painter, row)

        for spinner, slot in .spinners do
            spinner.show(.busy[slot])
        .explorer.requestPreview()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Move or evt.kind == .Enter or evt.kind == .Leave
        {
            let row = evt.kind == .Leave ? Swag.U64.Max : .rowAt(.surfaceToLocal(evt.surfacePos))
            if .hovered != row
            {
                .hovered = row
                .startNameScroll()
                .invalidate()
            }

            return
        }

        if (evt.kind != .Pressed and evt.kind != .DoubleClick) or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        let row = .rowAt(.surfaceToLocal(evt.surfacePos))
        .select(row)
        .setFocus()
        if evt.kind == .DoubleClick and row < .explorer.shown.count do
            .explorer.activate(.explorer.selected)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers.has(.Alt)
        {
            evt.accepted = false
            return
        }

        var row = 0'u64
        if .explorer.selected == Swag.U64.Max and
           (evt.key == .Left or evt.key == .Right or evt.key == .Up or evt.key == .Down)
        {
            .select(0)
            return
        }

        for index, at in .explorer.shown where index == .explorer.selected do
            row = at
        switch evt.key
        {
        case .Return: .explorer.activate(.explorer.selected)
        case .Left:   .select(row > 0 ? row - 1 : 0)
        case .Right:  .select(row + 1)
        case .Up:     .select(row >= .columns ? row - .columns : 0)
        case .Down:   .select(row + .columns)
        case .Home:   .select(0)
        case .End where not .explorer.shown.isEmpty(): .select(.explorer.shown.count - 1)
        case .Back:   .explorer.goUp()
        default:      evt.accepted = false
        }
    }
}
