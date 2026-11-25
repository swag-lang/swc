using Core, Gui

// The commands of the main window.
//
// Direct controls, menus and the lens share command identities and state. Shortcuts are
// registered once so every route teaches the same gesture.
namespace ViewerCommands
{
    const Lens              = "scope.lens"
    const Information       = "scope.information"
    const Open              = "scope.open"
    const Explore           = "scope.explore"
    const ReturnToExplorer  = "scope.explore.return"
    const Close             = "scope.close"
    const Dismiss           = "scope.dismiss"
    const Reload            = "scope.reload"
    const Print             = "scope.print"
    const PreviousFile      = "scope.previousFile"
    const NextFile          = "scope.nextFile"
    const OpenDefault       = "scope.file.openDefault"
    const OpenWith          = "scope.file.openWith"
    const Locate            = "scope.file.locate"
    const CopyPath          = "scope.file.copyPath"
    const CopyName          = "scope.file.copyName"
    const Forget            = "scope.file.forget"
    const SameKind          = "scope.sameKind"
    const ClearHistory      = "scope.clearHistory"
    const Find              = "scope.find"
    const GoToLine          = "scope.goToLine"
    const FindNext          = "scope.findNext"
    const FindPrevious      = "scope.findPrevious"
    const SearchMode        = "scope.search.mode.search"
    const FilterMode        = "scope.search.mode.filter"
    const MatchCase         = "scope.search.matchCase"
    const WholeWord         = "scope.search.wholeWord"
    const RegularExpression = "scope.search.regularExpression"
    const FullScreen        = "scope.fullScreen"
    const Outline           = "scope.outline"
    const SidePanel         = "scope.sidePanel"
    const PlayOnce          = "scope.play.once"
    const PlayRepeat        = "scope.play.repeat"
    const PlayFolder        = "scope.play.folder"
    const PlayShuffle       = "scope.play.shuffle"
    const Back              = "scope.explore.back"
    const Forward           = "scope.explore.forward"
    const Up                = "scope.explore.up"
    const Refresh           = "scope.explore.refresh"
    const ClearCaches       = "scope.explore.clearCaches"
    const EditLocation      = "scope.explore.location"
    const ChooseFolder      = "scope.explore.choose-folder"
    const CopyLocation      = "scope.explore.location.copy"
    const OpenSystemFolder  = "scope.explore.location.openSystem"
    const RevealArchive     = "scope.explore.location.revealArchive"
    const SortName          = "scope.explore.sort.name"
    const SortType          = "scope.explore.sort.type"
    const SortSize          = "scope.explore.sort.size"
    const SortModified      = "scope.explore.sort.modified"
    const SortAscending     = "scope.explore.sort.ascending"
    const SortDescending    = "scope.explore.sort.descending"
    const FilterAll         = "scope.explore.filter.all"
    const FilterVideos      = "scope.explore.filter.videos"
    const FilterImages      = "scope.explore.filter.images"
    const FilterAudio       = "scope.explore.filter.audio"
    const FilterDocuments   = "scope.explore.filter.documents"
    const FilterSubtitles   = "scope.explore.filter.subtitles"
    const FilterArchives    = "scope.explore.filter.archives"
    const FilterFolders     = "scope.explore.filter.folders"
    const OnlineMovies      = "scope.explore.onlineMovies"
    const OnlineMusic       = "scope.explore.onlineMusic"
    const GeneralOptions    = "scope.generalOptions"
    const ChooseMusic       = "scope.explore.chooseMusic"
    const OpenChosen        = "scope.explore.openChosen"
    const ExtractAll        = "scope.explore.extractAll"
    const ExtractChosen     = "scope.explore.extractChosen"
    const AlbumPlay         = "scope.explore.album.play"
    const AlbumShuffle      = "scope.explore.album.shuffle"
    const ArtworkOnline     = "scope.explore.artwork.online"
    const ArtworkLocal      = "scope.explore.artwork.local"
    const ThumbnailCaptions = "scope.explore.thumbnailCaptions"
    const TextLongestLine    = "scope.text.longestLine"

    // Each family is ordered like its matching Explorer enum.
    const Modes = ["scope.explore.mode.0", "scope.explore.mode.1", "scope.explore.mode.2",
                   "scope.explore.mode.3", "scope.explore.mode.4"]
    const Boards = ["scope.explore.board.0", "scope.explore.board.1", "scope.explore.board.2",
                    "scope.explore.board.3"]
    const ThumbnailCrops = ["scope.explore.crop.attention", "scope.explore.crop.entropy",
                            "scope.explore.crop.center", "scope.explore.crop.none"]
    const Artwork     = [ArtworkOnline, ArtworkLocal]
    const KindFilters = [FilterAll, FilterVideos, FilterImages, FilterAudio,
                         FilterDocuments, FilterSubtitles, FilterArchives, FilterFolders]
}

// Files the lens lists in one section for a query typed without the `/` prefix, which stands
// beside every other kind of answer, and with it, which asks for files alone.
const LensFilesBeside = 5'u64
const LensFilesAlone  = 64'u64

// The most lines of the open file the lens shows for a query, and the most of the file it reads
// to find them.
const LensLinesShown = 8'u64
const LensFileLimit  = 8 * 1024 * 1024'u64

// The viewers whose own lens source answers `:`, each with the positions it reads: rows, cells,
// pages, instants, offsets or chapters. Text, code and Markdown are answered here, by their lines.
const ViewersAnsweringPositions: [11] string = ["table", "xlsx", "ods", "pdf", "comic", "video", "sound", "hex", "binary", "epub", "subtitle"]

impl ViewerWindow
{
    // Creates the lens, registers every command of the window under its family, and the sources
    // that answer with the viewer choices, the basic file and view actions, and viewer controls.
    private mtd createLens()
    {
        with .lens = Lens.View.create(me)
        {
            if me.workspace
            {
                .wndFlags.add(.TopMost)
                .addRestSource(func|window = me|(results) { window.describeScenes(results, atRest: true) })
            }

            // In Explorer, make the folder the subject of the empty-query lens. A document keeps
            // the file and view actions at the door, ahead of viewer-specific choices and controls.
            .addRestSource(func|window = me|(results)
            {
                if not window.isExploring() do
                    return
                let section = results.addSection(appStrings().lens_Folder)
                window.lens.addCommandRows(section,
                                           [ViewerCommands.OpenChosen, SceneCommands.CompareSelection, ViewerCommands.Up, ViewerCommands.Refresh,
                                            ViewerCommands.EditLocation, ViewerCommands.Back, ViewerCommands.Forward],
                                           enabledOnly: true)
            })
            .addRestSource(func|window = me|(results)
            {
                let section = results.addSection(appStrings().lens_File)
                if window.isExploring()
                {
                    window.lens.addCommandRows(section, [ViewerCommands.Open, ViewerCommands.Close], enabledOnly: true)
                    return
                }

                window.lens.addCommandRows(section,
                                           [ViewerCommands.Open, ViewerCommands.Explore, ViewerCommands.ReturnToExplorer, ViewerCommands.Print, ViewerCommands.Close],
                                           enabledOnly: true)
            })
            .addRestSource(func|window = me|(results)
            {
                let section = results.addSection(appStrings().lens_View)
                window.lens.addCommandRows(section,
                                           [ViewerCommands.Outline, ViewerCommands.SidePanel, ViewerCommands.FullScreen, ViewerCommands.GeneralOptions],
                                           enabledOnly: true)
            })
            .addRestSource(func|window = me|(results) { window.describeViewerChoices(results) })
            .addRestSource(func|window = me|(results) { window.describeViewerCommands(results) })
            .addSource(.None, func|window = me|(results) { window.describeViewerChoices(results) })
            .addSource(.Action, func|window = me|(results) { window.describeViewerCommands(results) })
            .addSource(.File, func|window = me|(results) { window.describeFiles(results) })
            .addSource(.Line, func|window = me|(results) { window.describeFileLines(results) })
            .addCommand(func()->string => appStrings().lens_File, ViewerCommands.Open, func()->string => appStrings().search_Open)
            .addCommand(func()->string => appStrings().lens_File, ViewerCommands.Explore, func()->string => appStrings().search_Browse)
            .addCommands(func()->string => appStrings().lens_File, [ViewerCommands.Close, ViewerCommands.ReturnToExplorer, ViewerCommands.Reload, ViewerCommands.Print,
                                                                    ViewerCommands.PreviousFile, ViewerCommands.NextFile, ViewerCommands.OpenDefault, ViewerCommands.OpenWith,
                                                                    ViewerCommands.Locate, ViewerCommands.CopyPath, ViewerCommands.CopyName, ViewerCommands.Forget,
                                                                    ViewerCommands.SameKind, ViewerCommands.ClearHistory])
            .addCommands(func()->string => appStrings().lens_Folder, [ViewerCommands.Back, ViewerCommands.Forward, ViewerCommands.Up, ViewerCommands.Refresh,
                                                                      ViewerCommands.ClearCaches,
                                                                      ViewerCommands.EditLocation, ViewerCommands.ChooseFolder, ViewerCommands.CopyLocation,
                                                                      ViewerCommands.OpenSystemFolder, ViewerCommands.RevealArchive,
                                                                      ViewerCommands.SortName, ViewerCommands.SortType, ViewerCommands.SortSize,
                                                                      ViewerCommands.SortModified, ViewerCommands.SortAscending, ViewerCommands.SortDescending,
                                                                      ViewerCommands.FilterAll, ViewerCommands.FilterVideos, ViewerCommands.FilterImages,
                                                                      ViewerCommands.FilterAudio, ViewerCommands.FilterDocuments, ViewerCommands.FilterSubtitles,
                                                                      ViewerCommands.FilterArchives, ViewerCommands.FilterFolders, ViewerCommands.OnlineMovies,
                                                                      ViewerCommands.OnlineMusic, ViewerCommands.ChooseMusic, ViewerCommands.OpenChosen,
                                                                      ViewerCommands.ExtractAll, ViewerCommands.ExtractChosen,
                                                                      ViewerCommands.AlbumPlay, ViewerCommands.AlbumShuffle])
            .addCommands(func()->string => appStrings().lens_View, ViewerCommands.Modes)
            .addCommand(func()->string => appStrings().lens_View, ViewerCommands.ThumbnailCaptions)
            .addCommands(func()->string => appStrings().lens_View, ViewerCommands.Boards)
            .addCommands(func()->string => appStrings().explore_ThumbnailFraming, ViewerCommands.ThumbnailCrops)
            .addCommands(func()->string => appStrings().lens_Artwork, ViewerCommands.Artwork)
            .addCommands(func()->string => appStrings().lens_Find, [ViewerCommands.GoToLine, ViewerCommands.Find, ViewerCommands.FindNext, ViewerCommands.FindPrevious, ViewerCommands.SearchMode,
                                                                    ViewerCommands.FilterMode, ViewerCommands.MatchCase, ViewerCommands.WholeWord, ViewerCommands.RegularExpression])
            .addCommand(func()->string => appStrings().lens_View, ViewerCommands.FullScreen, func()->string => appStrings().search_FullScreen)
            .addCommands(func()->string => appStrings().lens_View,
                         [ViewerCommands.Information, ViewerCommands.Outline, ViewerCommands.SidePanel, ViewerCommands.GeneralOptions])
            .addCommands(func()->string => appStrings().lens_Playback,
                         [ViewerCommands.PlayOnce, ViewerCommands.PlayRepeat, ViewerCommands.PlayFolder, ViewerCommands.PlayShuffle])
        }

        .appearanceButton.addToLens(.lens)
        if .workspace do
            .addSceneCommands()

        // The lens uses one chord everywhere.
        .registerKeyShortcut(.Control, .Space, ViewerCommands.Lens)
        .registerKeyShortcut(.None, .Escape, ViewerCommands.Dismiss)
        .registerKeyShortcut(.None, .I, ViewerCommands.Information)
        .registerKeyShortcut(Input.KeyModifiers.Control | .Shift, .O, ViewerCommands.Outline)
        .registerKeyShortcut(.Control, .O, ViewerCommands.Open)
        .registerKeyShortcut(.Control, .E, ViewerCommands.Explore)
        .registerKeyShortcut(.None, .F5, ViewerCommands.Reload)
        .registerKeyShortcut(.Control, .P, ViewerCommands.Print)
        .registerKeyShortcut(.Control, .F, ViewerCommands.Find)
        .registerKeyShortcut(.Control, .G, ViewerCommands.GoToLine)
        .registerKeyShortcut(.None, .F3, ViewerCommands.FindNext)
        .registerKeyShortcut(.Shift, .F3, ViewerCommands.FindPrevious)
        .registerKeyShortcut(.None, .F11, ViewerCommands.FullScreen)
        .registerKeyShortcut(.Alt, .Left, ViewerCommands.Back)
        .registerKeyShortcut(.Alt, .Right, ViewerCommands.Forward)
        .registerKeyShortcut(.Alt, .Up, ViewerCommands.Up)
        .registerKeyShortcut(.Control, .L, ViewerCommands.EditLocation)
    }

    // Answers the lens with the viewers that can show the open file, the one in use underlined, or
    // with the ways of showing the explored folder: one exclusive choice, shown as one row.
    private mtd describeViewerChoices(results: *Lens.Results)
    {
        if not .acceptsViewCommands() do
            return
        let texts = appStrings()
        let typed:   String = results.query
        let query = typed.toString()
        var section: *Lens.Section?

        // A query naming the choice brings every viewer. The label is the same for each of them,
        // so it is matched once.
        let viewAsAnswers = Lens.match(results.folded, texts.lens_ViewAs).matched
        if .isExploring()
        {
            let explorer = unwrap .explorer
            if not query.count
            {
                        section        = results.addSection(texts.lens_ViewAs)
                        section.inline = true
                .lens.addCommandRows(section, ViewerCommands.Modes)
            }

            if explorer.listing.isArchive
            {
                let choices = .index.choices(explorer.listing.path)
                var viewers: *Lens.Section?
                for choice, index in choices
                {
                    let plugin = &.index.plugins[choice.pluginIndex]
                    let name   = plugin.displayName()
                    var found  = Lens.match(results.folded, name)
                    if not found.matched and not viewAsAnswers do
                        continue
                    if not viewers
                    {
                        viewers        = results.addSection(texts.lens_ViewAs)
                        viewers.inline = true
                    }

                    let chosen     = cast(u32, index)
                    with let entry = viewers.addEntry(name, #move found)
                    {
                        .checked = choice.key == "archive"
                        .run     = func|window = me, chosen|() { window.chooseViewerFromMenu(chosen) }
                    }
                }
            }

            return
        }

        if .choices.count < 2 do
            return
        for choice, index in .choices
        {
            let plugin = &.index.plugins[choice.pluginIndex]
            let name   = plugin.displayName()
            var found  = Lens.match(results.folded, name)
            if not found.matched and not viewAsAnswers do
                continue
            if not section
            {
                section        = results.addSection(texts.lens_ViewAs)
                section.inline = true
            }

            let chosen     = cast(u32, index)
            with let entry = section.addEntry(name, #move found)
            {
                .checked = chosen == me.activeChoiceIndex
                .run     = func|window = me, chosen|() { window.selectViewer(chosen) }
            }
        }
    }

    // Offers every compatible reader at the file itself. The first entry restores the
    // registry's original choice, even after the Archive alternative opened an explorer page.
    internal mtd createViewerChoicesMenu()->*MenuCtrl
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        if .isExploring() and .explorer and .explorer.listing.isArchive
        {
            let choices = .index.choices(.explorer.listing.path)
            .fillViewerChoicesMenu(menu, choices.toSlice(), "archive")
        }
        else
        {
            let active = .activeChoiceIndex < .choices.count ? .choices[.activeChoiceIndex].key.toString() : ""
            .fillViewerChoicesMenu(menu, .choices.toSlice(), active)
        }

        return menu
    }

    private mtd fillViewerChoicesMenu(menu: *MenuCtrl, choices: const [..] ViewerPluginChoice, active: string)
    {
        for &choice, index in choices
        {
            if index == 1 do
                menu.addSeparator()
            let plugin = &.index.plugins[choice.pluginIndex]
            let name   = plugin.displayName()
            var label  = String.from(name)
            if index == 0 do
                label = Format.toString(appStrings().ui_DefaultViewerChoice, name)
            let item = menu.addRadioItem(label, Format.toString("scope.viewer.choice.%", index), checked: choice.key == active)
            item.icon = .pluginIcon(plugin)
        }
    }

    private mtd showViewerChoicesMenu()
    {
        let selected = .createViewerChoicesMenu().doModal(.viewerCaptionButton, autoDestroy: true) orelse ""
        if not selected.count do
            return
        for index in .index.plugins.count where selected == Format.toString("scope.viewer.choice.%", index)
        {
            .chooseViewerFromMenu(cast(u32, index))
            return
        }
    }

    internal mtd chooseViewerFromMenu(index: u32)
    {
        if .isExploring() and .explorer and .explorer.listing.isArchive
        {
            let fileName = String.from(.explorer.listing.path)
            let choices  = .index.choices(fileName)
            if index >= choices.count or choices[index].key == "archive" do
                return
            .setFileViewer(fileName, choices[0].key, choices[index].key)
            .queueFile(fileName)
            return
        }

        .selectViewer(index)
    }

    // Answers the lens with the rows of the viewer on screen, under its name.
    private mtd describeViewerCommands(results: *Lens.Results)
    {
        if not .acceptsViewCommands() do
            return
        if .activeChoiceIndex >= .instances.count or .activeChoiceIndex >= .choices.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if not instance.view or not instance.lensSource do
            return
        let plugin  = &.index.plugins[.choices[.activeChoiceIndex].pluginIndex]
        var entries = Viewer.LensEntries.create(results, plugin.displayName(), .theme())
        instance.lensSource(&entries)
    }

    // Answers the lens with the lines of the open document that hold the query, under "In This
    // File", in the order of the file, each led by its number in mono; `:` and a number go to that
    // line, and a second number after another colon to that column of it. Code, text and Markdown
    // answer, as documents read line by line; a table, a workbook, a PDF, a comic, a film, a
    // recording and a subtitle track answer `:` themselves, with their rows, cells, pages, instants
    // and cues.
    private mtd describeFileLines(results: *Lens.Results)
    {
        if not .acceptsViewCommands() do
            return
        if let comparison = .lineComparison()
        {
            comparison.describeLine(results)
            return
        }
        if .isExploring() or .currentFile.isEmpty() do
            return
        if .activeChoiceIndex >= .instances.count or .activeChoiceIndex >= .choices.count do
            return
        let key = .choices[.activeChoiceIndex].key
        if results.prefix == .Line and Slice.contains(ViewersAnsweringPositions, key.toString())
        {
            .describeViewerCommands(results)
            return
        }

        if key != "text" and key != "code" and key != "markdown" do
            return
        if not .instances[.activeChoiceIndex].revealMatch do
            return

        // Plain text resolves typed positions with its active decoder and line counter. Other
        // text-like viewers keep the shared UTF-8 search path below.
        if key == "text"
        {
            let view = assume cast(*Viewers.PlainText.Panel, .instances[.activeChoiceIndex].view)
            if view.describeTypedPosition(results) do
                return
        }

        let typed: String = results.query
        let query         = Latin1.trim(typed.toString())
        if not query.count do
            return
        let bytes = .lensFileBytes()
        if bytes.isEmpty() do
            return

        let texts   = appStrings()
        let content = cast(string, bytes.toSlice())
        let starts  = .lensLineStarts.toSlice()

        // A number after `:` is a line to go to, and a second one after another colon the column
        // there, counted in characters from 1.
        var number    = true
        var separator = Swag.U64.Max
        for c, at in query
        {
            if c == ':' and separator == Swag.U64.Max and at > 0 and at + 1 < query.count do
                separator = at
            elif not Latin1.isDigit(c) do
                number = false
        }

        if results.prefix == .Line and number
        {
            let lineText = separator == Swag.U64.Max ? query : query[0 until separator]
            let wanted   = catch StrConv.toU64(lineText) { return; }
            if not wanted or wanted > starts.count do
                return

            let start   = starts[wanted - 1]
            let section = results.addSection(texts.lens_InFile)
            if separator == Swag.U64.Max
            {
                with let entry = section.addEntry(Format.toString(texts.lens_GoToLine, wanted))
                {
                    .lead = Format.toString("%", wanted)
                    .run  = func|window = me, start|() { window.revealLensOffset(start, 0) }
                }

                return
            }

            // A column past the end of the line stops at its end, and the row says where.
            let column  = catch StrConv.toU64(query[separator + 1 to]) orelse 1
            var offset  = start
            var reached = 1'u64
            while reached < column and
                  offset < content.count and
                  content[offset] != '\n' and
                  content[offset] != '\r'
            {
                offset += 1
                while offset < content.count and (content[offset] & 0xC0) == 0x80 do
                    offset += 1
                reached += 1
            }

            with let entry = section.addEntry(Format.toString(texts.lens_GoToLineColumn, wanted, reached))
            {
                .lead = Format.toString("%:%", wanted, reached)
                .run  = func|window = me, offset|() { window.revealLensOffset(offset, 0) }
            }

            return
        }

        // Every line holding the query, without regard to case; the first few stand as rows. The
        // whole file is searched at once and each hit named by the line it falls in, the search
        // resuming at the next line, so a line counts once however often it holds the query.
        var section: *Lens.Section?
        var found = 0'u32
        var line  = 0'u64
        var from  = 0'u64
        while from < content.count
        {
            let hit = Utf8.indexOf(content, query, from, .Latin1NoCase)
            if hit == Swag.U64.Max do
                break
            while line + 1 < starts.count and starts[line + 1] <= hit do
                line += 1

            let start = starts[line]
            var end   = line + 1 < starts.count ? starts[line + 1] - 1 : content.count
            if end > start and content[end - 1] == '\r' do
                end -= 1
            found += 1
            if cast(u64, found) <= LensLinesShown
            {
                if not section do
                    section = results.addSection(texts.lens_InFile)
                let length     = query.count
                with let entry = section.addEntry(Latin1.trim(content[start until end]))
                {
                    .lead      = Format.toString("%", line + 1)
                    .monoTitle = key == "code"
                    .run       = func|window = me, hit, length|() { window.revealLensOffset(hit, length) }
                }
            }

            if line + 1 >= starts.count do
                break
            from = starts[line + 1]
        }

        if section do
            section.count = found
    }

    // Shows the open document at `offset` of its file, the `length` bytes there marked.
    mtd revealLensOffset(offset, length: u64)
    {
        if .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if not instance.revealMatch do
            return
        let bytes = .lensFileBytes()
        if offset > bytes.count do
            return
        let text = cast(string, bytes.toSlice()[offset until Math.min(offset + length, bytes.count)])
        let sourceOffset = .lensContentStart + Viewer.sourceByteCount(cast(string, bytes.toSlice()[until offset]), .lensEncoding)
        if .activeChoiceIndex < .choices.count and
           .choices[.activeChoiceIndex].key == Viewers.PlainText.ViewerKey and
           instance.view
        {
            let view = assume cast(*Viewers.PlainText.Panel, instance.view)
            discard view.revealLensDestination(sourceOffset, text, caret: true)
            return
        }
        discard instance.revealMatch(Viewer.SearchMatch{0, 0, sourceOffset, Viewer.sourceByteCount(text, .lensEncoding)}, text)
    }

    // Returns the bytes of the open file the lens searches, read once per opening of the file and
    // at most `LensFileLimit` of them, and notes where each of their lines starts, so that a line
    // is reached by its number without counting the lines before it at every keystroke.
    mtd lensFileBytes()->const *Array'u8
    {
        var encoding = Text.Encoding.Utf8
        switch .currentView
        {
        case Viewers.PlainText.Panel as view: encoding = view.encoding
        case Viewers.Code.Panel as view:      encoding = view.encoding
        }
        if .lensBytesFile != .currentFile or .lensEncoding != encoding
        {
            .forgetLensFile()
            .lensBytesFile = .currentFile
            .lensEncoding = encoding
            catch
            {
                var stream = try File.openRead(.currentFile)
                let size   = Math.min(try stream.size(), LensFileLimit)
                .lensBytes.resize(size)
                .lensBytes.resize(try stream.read(.lensBytes.toSlice()))
                .lensContentStart = Text.hasBom(.lensBytes.toSlice(), encoding) ? Text.bomLength(encoding) : 0
                if encoding != .Utf8 or .lensContentStart
                {
                    let decoded = Text.decode(.lensBytes.toSlice()[.lensContentStart to], encoding)
                    .lensBytes.clear()
                    .lensBytes.add(decoded.toSlice())
                }
            }
            {
                .lensBytes.clear()
            }

            // A line starts the file and each line feed starts another, even the last one.
            .lensLineStarts.add(0)
            var at = Utf8.indexOf(.lensBytes.toSlice(), '\n'rune)
            while at != Swag.U64.Max
            {
                .lensLineStarts.add(at + 1)
                at = Utf8.indexOf(.lensBytes.toSlice(), '\n'rune, at + 1)
            }
        }

        return &.lensBytes
    }

    // Lets the lens read the open file again on its next question, as a file opened again or
    // reloaded may have changed since.
    mtd forgetLensFile()
    {
        .lensBytes.clear()
        .lensLineStarts.clear()
        .lensBytesFile.clear()
        .lensContentStart = 0
    }

    // Answers the lens with files to open: the recent ones, the ones beside the open file, and the
    // folders read lately. Without the `/` prefix, only a typed query brings them, a few each.
    private mtd describeFiles(results: *Lens.Results)
    {
        let alone = results.prefix == .File
        if not alone and results.query.isEmpty() do
            return

        let texts = appStrings()
        let limit = alone ? LensFilesAlone : LensFilesBeside
        .addFileSection(results, texts.ui_Recent, .recent.toSlice(), limit, remember: true)
        if not .acceptsViewCommands() do
            return
        if .siblingsDirty do
            .rebuildSiblings()
        .addFileSection(results, texts.lens_InFolder, .siblings.toSlice(), limit, remember: false)

        var section: *Lens.Section?
        for one in .folderHistory
        {
            if section and section.entries.count >= limit do
                break
            let folder = one.folder.toString()
            let name   = Path.fileName(folder) orelse folder
            var found  = Lens.match(results.folded, name)
            if not found.matched do
                continue
            if not section do
                section = results.addSection(texts.ui_FolderHistory)
            let file       = one.file.toString()
            with let entry = section.addEntry(name, #move found)
            {
                .glyph      = me.theme().icon(.Folder, me.themeMetrics().menuPopup_IconSize)
                .detail     = folder
                .monoDetail = true
                .run        = func|window = me, folder, file|()
                {
                    if window.isExploring() do
                        window.openExplorer(folder)
                    else do
                        window.openFile(file)
                }
            }
        }
    }

    // Adds the files of `files` whose name answers the query of `results` as one section of the lens.
    private mtd addFileSection(results: *Lens.Results, label: string, files: const [..] String, limit: u64, remember: bool)
    {
        var section: *Lens.Section?
        for one in files
        {
            if section and section.entries.count >= limit do
                break
            let file = one.toString()
            if file == .currentFile.toString() do
                continue
            let name  = Path.fileName(file) orelse file
            var found = Lens.match(results.folded, name)
            if not found.matched do
                continue
            if not section do
                section = results.addSection(label)

            var pluginIndex = Swag.U64.Max
            with let entry  = section.addEntry(name, #move found)
            {
                .detail     = Path.directoryName(file) orelse ""
                .monoDetail = true
                .run        = func|window = me, file, remember|() { window.openFile(file, remember) }
                if me.index.namePlugin(file, &pluginIndex) do
                    .glyph = me.pluginIcon(&me.index.plugins[pluginIndex], me.themeMetrics().menuPopup_IconSize)
            }
        }
    }

    // The last document still hosts the shared lens and title controls when the grid has focus.
    // Only commands with a window or scene target can run in that state.
    mtd needsSelectedCell(id: WndId)->bool
    {
        switch id
        {
        case ViewerCommands.Open, ViewerCommands.Explore, ViewerCommands.Lens, ViewerCommands.FullScreen,
             ViewerCommands.Dismiss, ViewerCommands.GeneralOptions, ViewerCommands.ClearHistory,
             ViewerCommands.OnlineMovies, ViewerCommands.OnlineMusic:
            return false
        case ViewerCommands.Information:
            return not (.workspace?.wantsComparisonSheet() orelse false)
        case SceneCommands.Beside, SceneCommands.CompareWith, SceneCommands.CompareSelection, SceneCommands.Maximize,
             SceneCommands.Layouts[0], MediaCommands.Solo, MediaCommands.AlignHere, MediaCommands.Times[2],
             ComparisonCommands.ZoomIn, ComparisonCommands.ZoomOut:
            return true
        default:
            return Utf8.startsWith(id, "scope.") and not Utf8.startsWith(id, "scope.scene.") and not Utf8.startsWith(id, "scope.compare.")
        }
    }

    // Describes one command of the window for the lens and every other presenter: its name, its
    // glyph, and whether it applies, is available and is in force now.
    mtd computeCommandState(evt: *CommandStateEvent)->bool
    {
        let unavailable = not .acceptsViewCommands() and .needsSelectedCell(evt.id)
        defer
        {
            if unavailable and evt.accepted
            {
                evt.disabled = true
                evt.updatedFields.add(.Disabled)
            }
        }
        if .computeSceneCommand(evt) or .computeComparisonCommand(evt) or .computeMediaCommand(evt) do
            return true

        let texts     = appStrings()
        let hasFile   = not .currentFile.isEmpty()
        let exploring = .isExploring()
        let compare   = .lineComparison() != null
        let search    = compare or (.activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].revealMatch != null)
        let canFilter = not compare and .activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].filterSearch != null

        var name:     string = ""
        var owned:    String     // Keeps a name the command composes alive until it is read.
        var icon:     Icon
        var hidden:   bool
        var disabled: bool
        var toggle:   bool
        var checked:  bool
        switch evt.id
        {
        case ViewerCommands.Lens:
            return false

        case ViewerCommands.Information:
            let comparison = .workspace?.wantsComparisonSheet() orelse false
            name     = comparison ? texts.scene_ComparisonSheet : texts.cmd_Information
            icon     = .commandGlyph(.Information)
            disabled = not hasFile and not exploring
            toggle   = true
            checked = .informationOpen()

        case ViewerCommands.GeneralOptions:
            name = texts.ui_GeneralOptions
            icon = .commandGlyph(.Settings)

        case ViewerCommands.Open:
            name = texts.cmd_Open
            icon = .commandGlyph(.OpenFile)

        case ViewerCommands.Explore:
            name = texts.cmd_Explore
            icon = .commandGlyph(.Folder)

        case ViewerCommands.ReturnToExplorer:
            name   = texts.cmd_ReturnToExplorer
            icon   = .commandGlyph(.ChevronLeft)
            hidden = not .canReturnToExplorer()

        case ViewerCommands.Close:
            let views = .workspace?.documentCount() orelse 0
            name   = views > 1 or (exploring and views > 0) ? texts.scene_CloseView : texts.ui_CloseFile
            icon   = .commandGlyph(.WndClose)
            hidden = not hasFile and not exploring and not (.workspace and .workspace.vacancy == me)

        case ViewerCommands.Dismiss:
            name     = Gui.strings().dlg_Close
            disabled = not .informationOpen() and not (.searchShown and not .isExploring()) and
                       not (.workspace?.scene()?.maximized orelse false) and not .fullScreen

        case ViewerCommands.Reload:
            name   = texts.cmd_Reload
            icon   = .commandGlyph(.Update)
            hidden = not hasFile or exploring

        case ViewerCommands.Print:
            name     = Gui.strings().print_Command
            icon     = .commandGlyph(.File)
            hidden   = not hasFile or exploring
            disabled = .printView() == null

        case ViewerCommands.PreviousFile:
            name   = texts.cmd_PreviousFile
            icon   = .commandGlyph(.ChevronLeft)
            hidden = not hasFile or exploring

        case ViewerCommands.NextFile:
            name   = texts.cmd_NextFile
            icon   = .commandGlyph(.ChevronRight)
            hidden = not hasFile or exploring

        case ViewerCommands.OpenDefault:
            name   = texts.ui_MenuOpenDefault
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = .fileActionPath().count == 0

        case ViewerCommands.OpenWith:
            name   = texts.ui_MenuOpenWith
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = .fileActionPath().count == 0

        case ViewerCommands.Locate:
            name   = texts.ui_MenuLocate
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = .fileActionPath().count == 0

        case ViewerCommands.CopyPath:
            name   = texts.ui_MenuCopyPath
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = .fileActionPath().count == 0

        case ViewerCommands.CopyName:
            name   = texts.ui_MenuCopyName
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = .fileActionPath().count == 0

        case ViewerCommands.Forget:
            name   = texts.ui_MenuForget
            icon   = .commandGlyph(.Remove)
            hidden = not hasFile or not .recent.contains(.currentFile)

        case ViewerCommands.SameKind:
            name    = texts.ui_SameKind
            icon    = .commandGlyph(.Filter)
            toggle  = true
            checked = .folderSameKind
            hidden  = exploring

        case ViewerCommands.ClearHistory:
            name     = texts.cmd_ClearHistory
            icon     = .commandGlyph(.RemoveAll)
            disabled = .recent.isEmpty()

        case ViewerCommands.Find:
            name   = exploring ? texts.cmd_FilterFiles : texts.cmd_Find
            icon   = .commandGlyph(.Search)
            hidden = not search and not exploring

        case ViewerCommands.GoToLine:
            name   = texts.cmd_GoToLine
            icon   = .commandGlyph(.GoTo)
            hidden = not .canGoToLine()

        case ViewerCommands.FindNext:
            name     = texts.cmd_FindNext
            icon     = .commandGlyph(.SearchNext)
            hidden   = not search
            disabled = .searchMatches.isEmpty()

        case ViewerCommands.FindPrevious:
            name     = texts.cmd_FindPrevious
            icon     = .commandGlyph(.SearchPrevious)
            hidden   = not search
            disabled = .searchMatches.isEmpty()

        case ViewerCommands.SearchMode:
            name    = texts.ui_SearchMode
            icon    = .commandGlyph(.Search)
            hidden  = not search or not canFilter
            toggle  = true
            checked = not .searchFilterMode

        case ViewerCommands.FilterMode:
            name    = texts.ui_FilterMode
            icon    = .commandGlyph(.Filter)
            hidden  = not search or not canFilter
            toggle  = true
            checked = .searchFilterMode

        case ViewerCommands.MatchCase:
            name    = texts.ui_SearchMatchCase
            icon    = .commandGlyph(.MatchCase)
            hidden  = not search
            toggle  = true
            checked = .searchMatchCaseOption

        case ViewerCommands.WholeWord:
            name    = texts.ui_SearchWholeWord
            icon    = .commandGlyph(.MatchWholeWord)
            hidden  = not search
            toggle  = true
            checked = .searchWholeWordOption

        case ViewerCommands.RegularExpression:
            name    = texts.ui_SearchRegularExpression
            icon    = .commandGlyph(.RegularExpression)
            hidden  = not search
            toggle  = true
            checked = .searchRegexOption

        case ViewerCommands.FullScreen:
            name    = texts.cmd_FullScreen
            icon    = .commandGlyph(.FullScreen)
            toggle  = true
            checked = .fullScreen

        case ViewerCommands.Outline:
            name   = outlineTitle()
            icon   = .commandGlyph(.Outline)
            hidden = true
            toggle = true
            if .currentSidePanelButton
            {
                hidden  = .currentSidePanelButton.id != OutlineToggleId
                checked = .currentSidePanelButton.isChecked
            }

        case ViewerCommands.SidePanel:
            hidden = .currentSidePanelButton == null
            if .currentSidePanelButton
            {
                name    = .currentSidePanelButton.toolTip
                icon    = .commandGlyph(.Information)
                hidden  = .currentSidePanelButton.id == OutlineToggleId
                toggle  = true
                checked = .currentSidePanelButton.isChecked
            }

        case ViewerCommands.PlayOnce:
            name    = texts.ui_PlayOnce
            icon    = .commandGlyph(.Play)
            toggle  = true
            checked = .playMode == .Once

        case ViewerCommands.PlayRepeat:
            name    = texts.ui_PlayRepeat
            icon    = .commandGlyph(.RepeatOne)
            toggle  = true
            checked = .playMode == .Repeat

        case ViewerCommands.PlayFolder:
            name    = texts.ui_PlayFolder
            icon    = .commandGlyph(.RepeatAll)
            toggle  = true
            checked = .playMode == .Folder

        case ViewerCommands.PlayShuffle:
            name    = texts.ui_PlayShuffle
            icon    = .commandGlyph(.Shuffle)
            toggle  = true
            checked = .playMode == .Shuffle

        case ViewerCommands.Back:
            name     = texts.explore_Back
            icon     = .commandGlyph(.ChevronLeft)
            hidden   = not exploring
            disabled = exploring and not .explorer!.history.canGoBack()

        case ViewerCommands.Forward:
            name     = texts.explore_Forward
            icon     = .commandGlyph(.ChevronRight)
            hidden   = not exploring
            disabled = exploring and not .explorer!.history.canGoForward()

        case ViewerCommands.Up:
            name     = texts.explore_Up
            icon     = .commandGlyph(.ParentFolder)
            hidden   = not exploring
            disabled = exploring and not .explorer!.canGoUp()

        case ViewerCommands.Refresh:
            name   = texts.explore_Refresh
            icon   = .commandGlyph(.Update)
            hidden = not exploring

        case ViewerCommands.ClearCaches:
            name     = texts.cmd_ClearCaches
            icon     = .commandGlyph(.RemoveAll)
            hidden   = not exploring
            disabled = not exploring or .explorer!.clearingCaches

        case ViewerCommands.EditLocation:
            name   = texts.cmd_EditLocation
            icon   = .commandGlyph(.Edit)
            hidden = not exploring

        case ViewerCommands.ChooseFolder:
            owned  = Format.toString("%…", Gui.strings().fileDlg_TitleSelectFolder)
            name   = owned
            icon   = .commandGlyph(.Folder)
            hidden = not exploring

        case ViewerCommands.CopyLocation:
            name   = texts.explore_CopyLocation
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = not exploring or .explorer!.listing.path.isEmpty()

        case ViewerCommands.OpenSystemFolder:
            name   = texts.explore_OpenSystemFolder
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = not exploring or .explorer!.listing.isArchive or .explorer!.listing.path.isEmpty()

        case ViewerCommands.RevealArchive:
            name   = texts.explore_RevealArchive
            icon   = .commandGlyph(pathActionGlyph(evt.id))
            hidden = not exploring or .explorer!.nativeArchivePath().count == 0

        case ViewerCommands.SortName, ViewerCommands.SortType,
             ViewerCommands.SortSize, ViewerCommands.SortModified:
            let column = sortColumnOf(evt.id)
            name    = sortCommandName(column)
            icon    = .commandGlyph(.Sort)
            hidden  = not exploring
            toggle  = true
            checked = exploring and .explorer!.sortColumn == column

        case ViewerCommands.SortAscending, ViewerCommands.SortDescending:
            let descending = evt.id == ViewerCommands.SortDescending
            name    = descending ? texts.cmd_SortDescending : texts.cmd_SortAscending
            icon    = .commandGlyph(descending ? .ChevronDown : .ChevronUp)
            hidden  = not exploring
            toggle  = true
            checked = exploring and .explorer!.descending == descending

        case ViewerCommands.OnlineMovies:
            name    = texts.explore_OnlineMovies
            icon    = .commandGlyph(.FileVideo)
            hidden  = not exploring and .currentFile.isEmpty()
            toggle  = true
            checked = .onlineMovies

        case ViewerCommands.OnlineMusic:
            name    = texts.explore_OnlineMusic
            icon    = .commandGlyph(.FileAudio)
            hidden  = not exploring and .currentFile.isEmpty()
            toggle  = true
            checked = .onlineMusic

        case ViewerCommands.OpenChosen:
            owned    = exploring ? .explorer!.openActionName() : String.from(texts.cmd_OpenChosen)
            name     = owned
            icon     = .commandGlyph(.OpenFile)
            hidden   = not exploring
            disabled = not exploring or .explorer!.selected >= .explorer.entries.count

        case ViewerCommands.ExtractAll:
            name     = texts.cmd_ExtractAll
            icon     = .commandGlyph(.Download)
            hidden   = not exploring or not .explorer!.listing.isArchive
            disabled = hidden or .explorer!.extraction.started

        case ViewerCommands.ExtractChosen:
            name     = texts.cmd_Extract
            icon     = .commandGlyph(.Download)
            hidden   = not exploring or not .explorer!.listing.isArchive
            disabled = hidden or
                       .explorer!.extraction.started or
                       .explorer!.selected >= .explorer.entries.count

        case ViewerCommands.AlbumPlay, ViewerCommands.AlbumShuffle:
            name     = evt.id == ViewerCommands.AlbumPlay ? texts.explore_Play : texts.explore_Shuffle
            icon     = .commandGlyph(evt.id == ViewerCommands.AlbumPlay ? .Play : .Shuffle)
            hidden   = not exploring or .explorer!.grid.board != .Album
            disabled = hidden or .explorer!.shown.isEmpty()

        case ViewerCommands.ChooseMusic:
            name     = texts.explore_ChooseMusic
            icon     = .commandGlyph(.AudioTracks)
            hidden   = not exploring
            disabled = not exploring or not .explorer!.canChooseMusic()

        case ViewerCommands.ThumbnailCaptions:
            name    = texts.explore_ShowTileCaption
            icon    = .scopeIcon(.Captions)
            hidden  = not exploring or not .explorer!.isThumbnailView() or .explorer!.grid.board == .Album
            toggle  = true
            checked = exploring and .explorer!.showTileCaption

        default:
            for id, index in ViewerCommands.Modes where evt.id == id
            {
                let names = [texts.explore_Names, texts.explore_Details, texts.explore_Small, texts.explore_Medium, texts.explore_Large]
                name    = names[index]
                icon    = .explorerModeIcon(ExplorerModeValues[index])
                hidden  = not exploring
                toggle  = true
                checked = exploring and cast(u64, .explorer!.mode) == index
                evt.renderingHint.add(.ExclusiveGroup)
                evt.updatedFields.add(.RenderingHint)
            }

            for id, index in ViewerCommands.KindFilters where evt.id == id
            {
                let names = [texts.explore_FilterAll, texts.explore_FilterVideos, texts.explore_FilterImages,
                             texts.explore_FilterAudio, texts.explore_FilterDocuments, texts.explore_FilterSubtitles,
                             texts.explore_FilterArchives, texts.explore_FilterFolders]
                name    = names[index]
                icon    = .commandGlyph(kindFilterIcon(ExplorerKindFilterValues[index]))
                hidden  = not exploring
                toggle  = true
                checked = exploring and cast(u64, .explorer!.kindFilter) == index
                evt.renderingHint.add(.ExclusiveGroup)
                evt.updatedFields.add(.RenderingHint)
            }

            for id, index in ViewerCommands.Boards where evt.id == id
            {
                let names = [texts.board_Automatic, texts.board_Grid, texts.board_Posters,
                             texts.board_Covers]
                let icons = [ThemeIcons.Folder, ThemeIcons.ExploreFolder, ThemeIcons.FileVideo,
                             ThemeIcons.FileAudio]
                name    = names[index]
                icon    = .commandGlyph(icons[index])
                hidden  = not exploring or not .explorer!.isThumbnailView() or .explorer!.listing.isArchive
                toggle  = true
                checked = exploring and
                          (index == 0 ? not .explorer!.forced :
                           (.explorer!.forced and cast(u64, .explorer.forcedBoard) == index - 1))
                evt.renderingHint.add(.ExclusiveGroup)
                evt.updatedFields.add(.RenderingHint)
            }

            for id, index in ViewerCommands.Artwork where evt.id == id
            {
                let names = [texts.artwork_Online, texts.artwork_Local]
                let icons = [ThemeIcons.Link, ThemeIcons.FileImage]
                name    = names[index]
                icon    = .commandGlyph(icons[index])
                hidden  = not exploring or not .explorer!.showsMedia()
                toggle  = true
                checked = exploring and cast(u64, .explorer!.artworkSource) == index
                evt.renderingHint.add(.ExclusiveGroup)
                evt.updatedFields.add(.RenderingHint)
            }

            for id, index in ViewerCommands.ThumbnailCrops where evt.id == id
            {
                let icons = [ThemeIcons.Eye, ThemeIcons.Histogram, ThemeIcons.CenterCrop, ThemeIcons.FitView]
                name    = thumbnailCropNames()[index]
                icon    = .commandGlyph(icons[index])
                hidden  = not exploring or not .explorer!.isThumbnailView()
                toggle  = true
                checked = exploring and .explorer!.thumbnailCrop == ThumbnailCropModes[index]
                evt.renderingHint.add(.ExclusiveGroup)
                evt.updatedFields.add(.RenderingHint)
            }

            if not name.count do
                return false
        }

        evt.name = name
        evt.updatedFields.add(.Name)
        if evt.id == ViewerCommands.Back or
           evt.id == ViewerCommands.Forward or
           evt.id == ViewerCommands.Up or
           evt.id == ViewerCommands.Refresh or
           evt.id == ViewerCommands.Find or
           evt.id == ViewerCommands.Information
        {
            evt.toolTip = name
            evt.updatedFields.add(.ToolTip)
        }

        if icon.isValid()
        {
            evt.icon = icon
            evt.updatedFields.add(.Icon)
        }

        if hidden
        {
            evt.hidden = true
            evt.updatedFields.add(.Hidden)
        }

        evt.disabled = disabled
        evt.updatedFields.add(.Disabled)

        if toggle
        {
            evt.checked = checked
            evt.updatedFields.add(.Checked)
        }

        if evt.id == ViewerCommands.Forget or evt.id == ViewerCommands.ClearHistory
        {
            evt.renderingHint |= .Critical
            evt.updatedFields.add(.RenderingHint)
        }

        evt.accepted = true
        return true
    }

    mtd explorerModeIcon(mode: ExplorerMode)->Icon
    {
        switch #complete mode
        {
        case .Names:   return .scopeIcon(.Names)
        case .Details: return .scopeIcon(.Details)
        case .Small:   return .commandGlyph(.ZoomOut)
        case .Medium:  return .commandGlyph(.Grid)
        case .Large:   return .commandGlyph(.ZoomIn)
        }
    }

    // Returns `icon` at the size of a glyph leading a row of the lens or a menu.
    private mtd commandGlyph(icon: ThemeIcons)->Icon => .theme().icon(icon, .themeMetrics().menuPopup_IconSize)

    mtd canGoToLine()->bool
    {
        if .lineComparison() do
            return true
        if .isExploring() or not .currentView or .activeChoiceIndex >= .choices.count do
            return false
        return Slice.contains(["text", "code", "markdown", "table", "subtitle", "xlsx", "ods"], .choices[.activeChoiceIndex].key.toString())
    }

    // Runs a window command against the current selection.
    mtd runCommand(id: WndId)->bool
    {
        if not .acceptsViewCommands() and .needsSelectedCell(id) do
            return true
        if .runSceneCommand(id) or .runComparisonCommand(id) or .runMediaCommand(id) do
            return true

        let hasFile = not .currentFile.isEmpty()
        switch id
        {
        case ViewerCommands.Lens:

            // A row of the viewer may open a menu from one of its floating buttons: they stay on
            // screen while the lens is open.
            .revealViewerBar()
            .lens.open()

        case ViewerCommands.Information:
            .toggleInformation()

        case ViewerCommands.TextLongestLine:
            if .activeChoiceIndex >= .instances.count or .activeChoiceIndex >= .choices.count do
                return false
            let instance = &.instances[.activeChoiceIndex]
            if not instance.view or instance.view != .currentView or
               .choices[.activeChoiceIndex].key != Viewers.PlainText.ViewerKey do
                return false
            let view = assume cast(*Viewers.PlainText.Panel, instance.view)
            return view.revealLongestLine()

        case ViewerCommands.GeneralOptions:
            .showGeneralOptions()

        case ViewerCommands.Open:
            .chooseFile()

        case ViewerCommands.Explore:
            if .acceptsViewCommands()
            {
                .exploreFolder()
            }
            else
            {
                let folder = .selectExplorerFolder()
                if not folder.isEmpty() do
                    .workspace!.openDocument(folder)
            }

        case ViewerCommands.ReturnToExplorer:
            .closeFile()

        case ViewerCommands.Close:
            if .workspace and .workspace.scene() do
                .workspace.closeView()
            else do
                .closeFile()

        case ViewerCommands.Dismiss:
            if .workspace?.comparisonSheet?.panel.isLocallyVisible() orelse false do
                .workspace!.closeComparisonSheet()
            elif .infoSheet.isLocallyVisible() do
                .closeInformation()
            elif .searchShown and not .isExploring() do
                .hideSearch()
            elif .workspace?.scene()?.maximized orelse false do
                .workspace!.toggleMaximized()
            elif .fullScreen do
                .setFullScreen(false)

        case ViewerCommands.Reload:
            .reloadCurrentFile()

        case ViewerCommands.Print:
            .printCurrentView()

        case ViewerCommands.PreviousFile:
            .navigate(-1)

        case ViewerCommands.NextFile:
            .navigate(1)

        case ViewerCommands.OpenDefault, ViewerCommands.OpenWith,
             ViewerCommands.Locate, ViewerCommands.CopyPath, ViewerCommands.CopyName:
            .runFileAction(id, .fileActionPath())

        case ViewerCommands.Forget where hasFile:
            .forgetRecent(.currentFile.toString())

        case ViewerCommands.SameKind:
            .setFolderSameKind(not .folderSameKind)

        case ViewerCommands.ClearHistory:
            .confirmClearRecent()

        case ViewerCommands.Find:
            .showSearch()

        case ViewerCommands.GoToLine:
            if not .canGoToLine() do
                return false
            .lens.open(":")

        case ViewerCommands.FindNext:
            .findNext()

        case ViewerCommands.OnlineMovies, ViewerCommands.OnlineMusic:
            .applyOnlineMedia(id == ViewerCommands.OnlineMovies ? not .onlineMovies : .onlineMovies,
                              id == ViewerCommands.OnlineMusic ? not .onlineMusic : .onlineMusic)
            catch .saveState()
            .information.request()
            .refreshInformation()

        case ViewerCommands.FindPrevious:
            .findPrevious()

        case ViewerCommands.SearchMode:
            .setSearchOption(id)

        case ViewerCommands.FilterMode:
            .setSearchOption(id)

        case ViewerCommands.MatchCase:
            .setSearchOption(id)

        case ViewerCommands.WholeWord:
            .setSearchOption(id)

        case ViewerCommands.RegularExpression:
            .setSearchOption(id)

        case ViewerCommands.FullScreen:
            .setFullScreen(not .fullScreen)

        case ViewerCommands.Outline:
            if not .currentSidePanelButton or .currentSidePanelButton.id != OutlineToggleId do
                return false
            .toggleSidePanel()

        case ViewerCommands.SidePanel:
            .toggleSidePanel()

        case ViewerCommands.PlayOnce:
            .setPlayMode(.Once)

        case ViewerCommands.PlayRepeat:
            .setPlayMode(.Repeat)

        case ViewerCommands.PlayFolder:
            .setPlayMode(.Folder)

        case ViewerCommands.PlayShuffle:
            .setPlayMode(.Shuffle)

        default:
            return .runExplorerCommand(id)
        }

        return true
    }

    private mtd toggleSidePanel()
    {
        if not .currentSidePanelButton do
            return
        let toggle = .currentSidePanelButton
        toggle.setChecked(not toggle.isChecked)
        toggle.sigCheckedChanged.call(toggle)
    }

    // Runs one command of the explored folder, and reports whether it was one.
    private mtd runExplorerCommand(id: WndId)->bool
    {
        if not .explorer do
            return false
        let explorer = .explorer
        switch id
        {
        case ViewerCommands.Back:
            explorer.goBack()

        case ViewerCommands.Forward:
            explorer.goForward()

        case ViewerCommands.Up:
            explorer.goUp()

        case ViewerCommands.Refresh:
            explorer.forceRefresh()

        case ViewerCommands.ClearCaches:
            explorer.clearCaches()

        case ViewerCommands.EditLocation:
            explorer.address.beginEdit()

        case ViewerCommands.ChooseFolder:
            explorer.chooseFolder()

        case ViewerCommands.CopyLocation:
            .runFileAction(id, explorer.locationText())

        case ViewerCommands.OpenSystemFolder:
            if not explorer.listing.isArchive do
                .runFileAction(id, explorer.listing.path)

        case ViewerCommands.RevealArchive:
            .runFileAction(id, explorer.nativeArchivePath())

        case ViewerCommands.FilterAll, ViewerCommands.FilterVideos,
             ViewerCommands.FilterImages, ViewerCommands.FilterAudio,
             ViewerCommands.FilterDocuments, ViewerCommands.FilterSubtitles,
             ViewerCommands.FilterArchives, ViewerCommands.FilterFolders:
            for command, index in ViewerCommands.KindFilters where id == command
            {
                explorer.setKindFilter(ExplorerKindFilterValues[index])
                return true
            }

        case ViewerCommands.SortAscending, ViewerCommands.SortDescending:
            explorer.sortBy(explorer.sortColumn, id == ViewerCommands.SortDescending)

        case ViewerCommands.ChooseMusic:
            explorer.chooseMusic()

        case ViewerCommands.OpenChosen:
            explorer.openSelection()

        case ViewerCommands.ExtractAll:
            explorer.chooseExtraction(all: true)

        case ViewerCommands.ExtractChosen:
            explorer.chooseExtraction(all: false)

        case ViewerCommands.ThumbnailCaptions:
            explorer.setTileCaption(not explorer.showTileCaption)

        case ViewerCommands.AlbumPlay:
            explorer.playAlbum(false)

        case ViewerCommands.AlbumShuffle:
            explorer.playAlbum(true)

        case ViewerCommands.SortName, ViewerCommands.SortType,
             ViewerCommands.SortSize, ViewerCommands.SortModified:
            explorer.sortBy(sortColumnOf(id), explorer.descending)

        default:
            for command, index in ViewerCommands.Modes where id == command
            {
                explorer.setMode(ExplorerModeValues[index])
                return true
            }

            for command, index in ViewerCommands.Boards where id == command
            {
                explorer.forceBoard(index != 0, index ? ExplorerBoardValues[index - 1] : .Grid)
                return true
            }

            for command, index in ViewerCommands.Artwork where id == command
            {
                explorer.setArtworkSource(ExplorerArtworkSourceValues[index])
                return true
            }

            for command, index in ViewerCommands.ThumbnailCrops where id == command
            {
                explorer.setThumbnailCrop(ThumbnailCropModes[index])
                return true
            }

            return false
        }

        return true
    }

    mtd informationOpen()->bool => .infoSheet.isLocallyVisible() or
                                  (.workspace?.comparisonSheet?.panel.isLocallyVisible() orelse false)

    // Shows the sheet of readings about the open file or the explored folder, or hides it.
    mtd toggleInformation()
    {
        if .workspace and .workspace.wantsComparisonSheet()
        {
            .workspace.toggleComparisonSheet()
            return
        }
        if .currentFile.isEmpty() and not .isExploring()
        {
            .closeInformation()
            return
        }

        .refreshInformation()
        .infoSheet.toggle()
        .sheetToggled(.infoSheet.isLocallyVisible())
    }

    // Closes the sheet of readings, and gives its room back to the page under it.
    mtd closeInformation()
    {
        .infoSheet.close()
        .sheetToggled(false)
    }

    // Refreshes the sheet and its caption action while leaving the document in place.
    mtd sheetToggled(open: bool)
    {
        .refreshExplorerCaption()
        if open do
            .information.request()
        else do
            .information.stop()
        if .isExploring() do
            .teachHints(true)
        .layoutSearchBar()
    }

    // Describes what the window shows in the information sheet: the open file, or the item chosen
    // in the explored folder.
    mtd refreshInformation()
    {
        if .information.refreshing do
            return
        if .isExploring() or (.currentFile.isEmpty() and .explorerActive and .explorer)
        {
            .information.selectExplorer(unwrap .explorer)
            .information.describe(.infoSheet, includeAction: true)
        }
        elif not .currentFile.isEmpty()
        {
            if .explorer and (.explorer.describesFile(.currentFile) or .isArchivePreview()) do
                .information.selectExplorer(.explorer)
            else do
                .information.selectFile(.currentFile)
            .information.describe(.infoSheet)
        }
        else
        {
            .infoSheet.close()
        }
    }

    // Applies one choice of the search options and runs the search again under it.
    mtd setSearchOption(id: WndId)
    {
        switch id
        {
        case ViewerCommands.SearchMode:
            if not .searchFilterMode do
                return
            .searchFilterMode = false

        case ViewerCommands.FilterMode:
            if .searchFilterMode do
                return
            .searchFilterMode = true

        case ViewerCommands.MatchCase:
            .searchMatchCaseOption = not .searchMatchCaseOption

        case ViewerCommands.WholeWord:
            .searchWholeWordOption = not .searchWholeWordOption

        case ViewerCommands.RegularExpression:
            .searchRegexOption = not .searchRegexOption

        default:
            return
        }

        // A query that was literal may be incomplete regexp syntax, and vice versa. Re-run the
        // field validator before deciding whether there is work to schedule.
        discard .searchBox.revalidate()
        .refreshSearchPresentation()
        .restartSearch()
        catch .saveState()
    }
}

// Returns the column of the explored listing a sort command orders by.
func sortColumnOf(id: WndId)->u32
{
    switch id
    {
    case ViewerCommands.SortType:     return 1
    case ViewerCommands.SortSize:     return 2
    case ViewerCommands.SortModified: return 3
    default: return 0
    }
}

// Returns the command name of ordering the explored listing by `column`.
func sortCommandName(column: u32)->string
{
    let texts = appStrings()
    switch column
    {
    case 1:  return texts.cmd_SortType
    case 2:  return texts.cmd_SortSize
    case 3:  return texts.cmd_SortModified
    default: return texts.cmd_SortName
    }
}
