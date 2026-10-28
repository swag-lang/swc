using Core, Gui

// The commands of the main window.
//
// The window keeps no toolbar: each command is an entry of its lens, found by its name, and the
// ones a key runs are registered as shortcuts so the lens writes the key beside the entry. The
// same identifiers name the entries of the file menu a list row opens.
namespace ViewerCommands
{
    const Lens              = "scope.lens"
    const Information       = "scope.information"
    const Open              = "scope.open"
    const Explore           = "scope.explore"
    const Close             = "scope.close"
    const Reload            = "scope.reload"
    const PreviousFile      = "scope.previousFile"
    const NextFile          = "scope.nextFile"
    const OpenDefault       = "scope.file.openDefault"
    const OpenWith          = "scope.file.openWith"
    const Locate            = "scope.file.locate"
    const CopyPath          = "scope.file.copyPath"
    const CopyName          = "scope.file.copyName"
    const Forget            = "scope.file.forget"
    const Files             = "scope.files"
    const SameKind          = "scope.sameKind"
    const ClearHistory      = "scope.clearHistory"
    const Find              = "scope.find"
    const FindNext          = "scope.findNext"
    const FindPrevious      = "scope.findPrevious"
    const SearchMode        = "scope.search.mode.search"
    const FilterMode        = "scope.search.mode.filter"
    const MatchCase         = "scope.search.matchCase"
    const WholeWord         = "scope.search.wholeWord"
    const RegularExpression = "scope.search.regularExpression"
    const FullScreen        = "scope.fullScreen"
    const SidePanel         = "scope.sidePanel"
    const PlayOnce          = "scope.play.once"
    const PlayRepeat        = "scope.play.repeat"
    const PlayFolder        = "scope.play.folder"
    const PlayShuffle       = "scope.play.shuffle"
    const Back              = "scope.explore.back"
    const Forward           = "scope.explore.forward"
    const Up                = "scope.explore.up"
    const Refresh           = "scope.explore.refresh"
    const EditLocation      = "scope.explore.location"
    const SortName          = "scope.explore.sort.name"
    const SortType          = "scope.explore.sort.type"
    const SortSize          = "scope.explore.sort.size"
    const SortModified      = "scope.explore.sort.modified"
    const SortDescending    = "scope.explore.sort.descending"
    const OnlineMovies      = "scope.explore.onlineMovies"
    const OnlineMusic       = "scope.explore.onlineMusic"
    const ChooseMusic       = "scope.explore.chooseMusic"
    const OpenChosen        = "scope.explore.openChosen"
}

// Files the lens lists in one section for a query typed without the `/` prefix, which stands
// beside every other kind of answer, and with it, which asks for files alone.
const LensFilesBeside = 5'u64
const LensFilesAlone  = 64'u64

impl ViewerWindow
{
    // Creates the lens, registers every command of the window under its family, and the sources
    // that answer with the viewers, the files and the appearance.
    private mtd createLens()
    {
        with .lens = Lens.View.create(me)
        {
            .addSource(.None, func|window = me|(results) { window.describeViewerChoices(results) })
            .addSource(.Action, func|window = me|(results) { window.describeViewerCommands(results) })
            .addSource(.File, func|window = me|(results) { window.describeFiles(results) })
            .addCommands(func()->string => appStrings().lens_File,
                         [ViewerCommands.Open, ViewerCommands.Explore, ViewerCommands.Close, ViewerCommands.Reload,
                          ViewerCommands.PreviousFile, ViewerCommands.NextFile, ViewerCommands.OpenDefault, ViewerCommands.OpenWith,
                          ViewerCommands.Locate, ViewerCommands.CopyPath, ViewerCommands.CopyName, ViewerCommands.Forget,
                          ViewerCommands.Files, ViewerCommands.SameKind, ViewerCommands.ClearHistory])
            .addCommands(func()->string => appStrings().lens_Folder,
                         [ViewerCommands.Back, ViewerCommands.Forward, ViewerCommands.Up, ViewerCommands.Refresh,
                          ViewerCommands.EditLocation, ViewerCommands.SortName, ViewerCommands.SortType, ViewerCommands.SortSize,
                          ViewerCommands.SortModified, ViewerCommands.SortDescending, ViewerCommands.OnlineMovies,
                          ViewerCommands.OnlineMusic, ViewerCommands.ChooseMusic, ViewerCommands.OpenChosen])
            .addCommands(func()->string => appStrings().lens_Find,
                         [ViewerCommands.Find, ViewerCommands.FindNext, ViewerCommands.FindPrevious, ViewerCommands.SearchMode,
                          ViewerCommands.FilterMode, ViewerCommands.MatchCase, ViewerCommands.WholeWord, ViewerCommands.RegularExpression])
            .addCommands(func()->string => appStrings().lens_View,
                         [ViewerCommands.Information, ViewerCommands.SidePanel, ViewerCommands.FullScreen])
            .addCommands(func()->string => appStrings().lens_Playback,
                         [ViewerCommands.PlayOnce, ViewerCommands.PlayRepeat, ViewerCommands.PlayFolder, ViewerCommands.PlayShuffle])
        }

        .appearanceButton.addToLens(.lens)

        // The door has a key of its own where nothing types, and a chord everywhere.
        .registerKeyShortcut(.None, .Space, ViewerCommands.Lens)
        .registerKeyShortcut(.Control, .K, ViewerCommands.Lens)
        .registerKeyShortcut(.None, .I, ViewerCommands.Information)
        .registerKeyShortcut(.Control, .O, ViewerCommands.Open)
        .registerKeyShortcut(.Control, .E, ViewerCommands.Explore)
        .registerKeyShortcut(.None, .F5, ViewerCommands.Reload)
        .registerKeyShortcut(.Control, .F, ViewerCommands.Find)
        .registerKeyShortcut(.None, .F3, ViewerCommands.FindNext)
        .registerKeyShortcut(.Shift, .F3, ViewerCommands.FindPrevious)
        .registerKeyShortcut(.None, .F11, ViewerCommands.FullScreen)
        .registerKeyShortcut(.Alt, .Left, ViewerCommands.Back)
        .registerKeyShortcut(.Alt, .Right, ViewerCommands.Forward)
        .registerKeyShortcut(.Alt, .Up, ViewerCommands.Up)
        .registerKeyShortcut(.Control, .L, ViewerCommands.EditLocation)
    }

    // Answers the lens with the viewers that can show the open file, the one in use checked, or
    // with the ways of showing the explored folder.
    private mtd describeViewerChoices(results: *Lens.Results)
    {
        let texts = appStrings()
        let typed: String = results.query
        let query = typed.toString()
        var section: *Lens.Section?
        if .isExploring()
        {
            let explorer = unwrap .explorer
            for name, mode in [texts.explore_Names, texts.explore_Details, texts.explore_Small, texts.explore_Medium, texts.explore_Large]
            {
                if not Lens.match(query, name).matched and not Lens.match(query, texts.lens_ViewAs).matched do
                    continue
                if not section do
                    section = results.addSection(texts.lens_ViewAs)
                let chosen     = cast(ExplorerMode, cast(u32, mode))
                with let entry = section.addEntry(name)
                {
                    .checked = explorer.mode == chosen
                    .run     = func|explorer, chosen|() { explorer.setMode(chosen) }
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
            if not Lens.match(query, name).matched and not Lens.match(query, texts.lens_ViewAs).matched do
                continue
            if not section do
                section = results.addSection(texts.lens_ViewAs)
            let chosen     = cast(u32, index)
            with let entry = section.addEntry(name)
            {
                .glyph   = me.pluginIcon(plugin, me.themeMetrics().menuPopup_IconSize)
                .checked = chosen == me.activeChoiceIndex
                .run     = func|window = me, chosen|() { window.selectViewer(chosen) }
            }
        }
    }

    // Answers the lens with the rows of the viewer on screen, under its name.
    private mtd describeViewerCommands(results: *Lens.Results)
    {
        if .activeChoiceIndex >= .instances.count or .activeChoiceIndex >= .choices.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if not instance.view or not instance.lensSource do
            return
        let plugin  = &.index.plugins[.choices[.activeChoiceIndex].pluginIndex]
        var entries = Viewer.LensEntries.create(results, plugin.displayName())
        instance.lensSource(&entries)
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
        let typed: String = results.query
        let query = typed.toString()
        .addFileSection(results, texts.ui_Recent, .recent.toSlice(), query, limit, remember: true)
        if .siblingsDirty do
            .rebuildSiblings()
        .addFileSection(results, texts.lens_InFolder, .siblings.toSlice(), query, limit, remember: false)

        var section: *Lens.Section?
        for one in .folderHistory
        {
            if section and section.entries.count >= limit do
                break
            let folder = one.folder.toString()
            let name   = Path.fileName(folder) orelse folder
            if not Lens.match(query, name).matched do
                continue
            if not section do
                section = results.addSection(texts.ui_FolderHistory)
            let file       = one.file.toString()
            with let entry = section.addEntry(name)
            {
                .glyph      = me.theme().icon(.Folder, me.themeMetrics().menuPopup_IconSize)
                .detail     = folder
                .monoDetail = true
                .run        = func|window = me, folder, file|()
                {
                    if window.isExploring() do
                        window.openExplorer(folder)
                    else do
                        window.queueFile(file)
                }
            }
        }
    }

    // Adds the files of `files` whose name answers `query` as one section of the lens.
    private mtd addFileSection(results: *Lens.Results, label: string, files: const [..] String, query: string, limit: u64, remember: bool)
    {
        var section: *Lens.Section?
        for one in files
        {
            if section and section.entries.count >= limit do
                break
            let file = one.toString()
            if file == .currentFile.toString() do
                continue
            let name = Path.fileName(file) orelse file
            if not Lens.match(query, name).matched do
                continue
            if not section do
                section = results.addSection(label)

            var pluginIndex = Swag.U64.Max
            with let entry = section.addEntry(name)
            {
                .detail     = Path.directoryName(file) orelse ""
                .monoDetail = true
                .run        = func|window = me, file, remember|() { window.queueFile(file, remember) }
                if me.index.namePlugin(file, &pluginIndex) do
                    .glyph = me.pluginIcon(&me.index.plugins[pluginIndex], me.themeMetrics().menuPopup_IconSize)
            }
        }
    }

    // Describes one command of the window for the lens and every other presenter: its name, its
    // glyph, and whether it applies, is available and is in force now.
    mtd computeCommandState(evt: *CommandStateEvent)->bool
    {
        let texts     = appStrings()
        let hasFile   = not .currentFile.isEmpty()
        let exploring = .isExploring()
        let search    = .activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].revealMatch != null
        let canFilter = .activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].filterSearch != null

        var name:     string = ""
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
            name     = texts.cmd_Information
            icon     = .commandGlyph(.Information)
            disabled = not hasFile and not exploring
            toggle   = true
            checked  = .infoSheet.isLocallyVisible()
        case ViewerCommands.Open:
            name = texts.cmd_Open
            icon = .commandGlyph(.OpenFile)
        case ViewerCommands.Explore:
            name = texts.cmd_Explore
            icon = .commandGlyph(.Folder)
        case ViewerCommands.Close:
            name   = texts.ui_CloseFile
            hidden = not hasFile and not exploring
        case ViewerCommands.Reload:
            name   = texts.cmd_Reload
            icon   = .commandGlyph(.Update)
            hidden = not hasFile or exploring
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
            icon   = .commandGlyph(.OpenExternal)
            hidden = not hasFile
        case ViewerCommands.OpenWith:
            name   = texts.ui_MenuOpenWith
            icon   = .commandGlyph(.OpenExternal)
            hidden = not hasFile
        case ViewerCommands.Locate:
            name   = texts.ui_MenuLocate
            hidden = not hasFile
        case ViewerCommands.CopyPath:
            name   = texts.ui_MenuCopyPath
            icon   = .commandGlyph(.Copy)
            hidden = not hasFile
        case ViewerCommands.CopyName:
            name   = texts.ui_MenuCopyName
            icon   = .commandGlyph(.Copy)
            hidden = not hasFile
        case ViewerCommands.Forget:
            name   = texts.ui_MenuForget
            icon   = .commandGlyph(.Remove)
            hidden = not hasFile or not .recent.contains(.currentFile)
        case ViewerCommands.Files:
            name    = texts.ui_Files
            icon    = .commandGlyph(.History)
            toggle  = true
            checked = .panelVisible
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
            name   = texts.cmd_Find
            icon   = .commandGlyph(.Search)
            hidden = not search and not exploring
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
            hidden  = not search or not canFilter
            toggle  = true
            checked = not .searchFilterMode
        case ViewerCommands.FilterMode:
            name    = texts.ui_FilterMode
            hidden  = not search or not canFilter
            toggle  = true
            checked = .searchFilterMode
        case ViewerCommands.MatchCase:
            name    = texts.ui_SearchMatchCase
            hidden  = not search
            toggle  = true
            checked = .searchMatchCaseOption
        case ViewerCommands.WholeWord:
            name    = texts.ui_SearchWholeWord
            hidden  = not search
            toggle  = true
            checked = .searchWholeWordOption
        case ViewerCommands.RegularExpression:
            name    = texts.ui_SearchRegularExpression
            hidden  = not search
            toggle  = true
            checked = .searchRegexOption
        case ViewerCommands.FullScreen:
            name    = texts.cmd_FullScreen
            icon    = .commandGlyph(.FullScreen)
            toggle  = true
            checked = .fullScreen
        case ViewerCommands.SidePanel:
            hidden = .currentSidePanelButton == null
            if .currentSidePanelButton
            {
                name    = .currentSidePanelButton.toolTip
                toggle  = true
                checked = .currentSidePanelButton.isChecked
            }
        case ViewerCommands.PlayOnce:
            name    = texts.ui_PlayOnce
            toggle  = true
            checked = .playMode == .Once
        case ViewerCommands.PlayRepeat:
            name    = texts.ui_PlayRepeat
            toggle  = true
            checked = .playMode == .Repeat
        case ViewerCommands.PlayFolder:
            name    = texts.ui_PlayFolder
            toggle  = true
            checked = .playMode == .Folder
        case ViewerCommands.PlayShuffle:
            name    = texts.ui_PlayShuffle
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
            name   = texts.explore_Up
            icon   = .commandGlyph(.ParentFolder)
            hidden = not exploring
        case ViewerCommands.Refresh:
            name   = texts.explore_Refresh
            icon   = .commandGlyph(.Update)
            hidden = not exploring
        case ViewerCommands.EditLocation:
            name   = texts.cmd_EditLocation
            hidden = not exploring
        case ViewerCommands.SortName, ViewerCommands.SortType, ViewerCommands.SortSize, ViewerCommands.SortModified:
            let column = sortColumnOf(evt.id)
            name    = sortCommandName(column)
            icon    = .commandGlyph(.Sort)
            hidden  = not exploring
            toggle  = true
            checked = exploring and .explorer!.sortColumn == column
        case ViewerCommands.SortDescending:
            name    = texts.cmd_SortDescending
            hidden  = not exploring
            toggle  = true
            checked = exploring and .explorer!.descending
        case ViewerCommands.OnlineMovies:
            name    = texts.explore_OnlineMovies
            hidden  = not exploring
            toggle  = true
            checked = .onlineMovies
        case ViewerCommands.OnlineMusic:
            name    = texts.explore_OnlineMusic
            hidden  = not exploring
            toggle  = true
            checked = .onlineMusic
        case ViewerCommands.OpenChosen:
            name     = texts.cmd_OpenChosen
            hidden   = not exploring
            disabled = not exploring or .explorer!.selected >= .explorer.entries.count
        case ViewerCommands.ChooseMusic:
            name     = texts.explore_ChooseMusic
            hidden   = not exploring
            disabled = not exploring or not .explorer!.canChooseMusic()
        default:
            return false
        }

        evt.name = name
        evt.updatedFields.add(.Name)
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

        if disabled
        {
            evt.disabled = true
            evt.updatedFields.add(.Disabled)
        }

        if toggle
        {
            evt.checked = checked
            evt.updatedFields.add(.Checked)
        }

        evt.accepted = true
        return true
    }

    // Returns `icon` at the size of a glyph leading a row of the lens or a menu.
    private mtd commandGlyph(icon: ThemeIcons)->Icon => .theme().icon(icon, .themeMetrics().menuPopup_IconSize)

    // Runs one command of the window, and reports whether it was one.
    mtd runCommand(id: WndId)->bool
    {
        let hasFile = not .currentFile.isEmpty()
        switch id
        {
        case ViewerCommands.Lens:
            // A row of the viewer may open a menu from one of its floating buttons: they stay on
            // screen while the lens is open.
            .revealViewerBar()
            .lens.open()
        case ViewerCommands.Information:       .toggleInformation()
        case ViewerCommands.Open:              .chooseFile()
        case ViewerCommands.Explore:           .exploreFolder()
        case ViewerCommands.Close:             .closeFile()
        case ViewerCommands.Reload:            .reloadCurrentFile()
        case ViewerCommands.PreviousFile:      .navigate(-1)
        case ViewerCommands.NextFile:          .navigate(1)
        case ViewerCommands.OpenDefault:       .openCurrentFileDefault()
        case ViewerCommands.OpenWith where hasFile: Env.openFileWith(.currentFile)
        case ViewerCommands.Locate where hasFile:   Env.showInFileExplorer(.currentFile)
        case ViewerCommands.CopyPath where hasFile: Clipboard.setString(.currentFile)
        case ViewerCommands.CopyName where hasFile: Clipboard.setString(Path.fileName(.currentFile) orelse .currentFile.toString())
        case ViewerCommands.Forget where hasFile:   .forgetRecent(.currentFile.toString())
        case ViewerCommands.Files:             .toggleFilePanel()
        case ViewerCommands.SameKind:          .setFolderSameKind(not .folderSameKind)
        case ViewerCommands.ClearHistory:      .confirmClearRecent()
        case ViewerCommands.Find:              .showSearch()
        case ViewerCommands.FindNext:          .findNext()
        case ViewerCommands.FindPrevious:      .findPrevious()
        case ViewerCommands.SearchMode:        .setSearchOption(id)
        case ViewerCommands.FilterMode:        .setSearchOption(id)
        case ViewerCommands.MatchCase:         .setSearchOption(id)
        case ViewerCommands.WholeWord:         .setSearchOption(id)
        case ViewerCommands.RegularExpression: .setSearchOption(id)
        case ViewerCommands.FullScreen:        .setFullScreen(not .fullScreen)
        case ViewerCommands.SidePanel:
            if .currentSidePanelButton
            {
                let toggle = .currentSidePanelButton
                toggle.setChecked(not toggle.isChecked)
                toggle.sigCheckedChanged.call(toggle)
            }
        case ViewerCommands.PlayOnce:          .setPlayMode(.Once)
        case ViewerCommands.PlayRepeat:        .setPlayMode(.Repeat)
        case ViewerCommands.PlayFolder:        .setPlayMode(.Folder)
        case ViewerCommands.PlayShuffle:       .setPlayMode(.Shuffle)
        default:                               return .runExplorerCommand(id)
        }

        return true
    }

    // Runs one command of the explored folder, and reports whether it was one.
    private mtd runExplorerCommand(id: WndId)->bool
    {
        if not .explorer do
            return false
        let explorer = .explorer
        switch id
        {
        case ViewerCommands.Back:           explorer.goBack()
        case ViewerCommands.Forward:        explorer.goForward()
        case ViewerCommands.Up:             explorer.goUp()
        case ViewerCommands.Refresh:        explorer.forceRefresh()
        case ViewerCommands.EditLocation:   explorer.address.beginEdit()
        case ViewerCommands.SortDescending: explorer.sortBy(explorer.sortColumn, not explorer.descending)
        case ViewerCommands.OnlineMovies:   explorer.setOnlineMedia(not .onlineMovies, .onlineMusic)
        case ViewerCommands.OnlineMusic:    explorer.setOnlineMedia(.onlineMovies, not .onlineMusic)
        case ViewerCommands.ChooseMusic:    explorer.chooseMusic()
        case ViewerCommands.OpenChosen:     explorer.activate(explorer.selected)
        case ViewerCommands.SortName, ViewerCommands.SortType, ViewerCommands.SortSize, ViewerCommands.SortModified:
            explorer.sortBy(sortColumnOf(id), explorer.descending)
        default:
            return false
        }

        return true
    }

    // Shows the sheet of readings about the open file or the explored folder, or hides it.
    mtd toggleInformation()
    {
        if .currentFile.isEmpty() and not .isExploring()
        {
            .infoSheet.close()
            return
        }

        .refreshInformation()
        .infoSheet.toggle()
    }

    // Describes what the window shows in the information sheet: the open file, or the item chosen
    // in the explored folder.
    mtd refreshInformation()
    {
        .infoSheet.clear()
        if .isExploring()
        {
            .explorer!.describeSelection(.infoSheet)
            return
        }

        if .currentFile.isEmpty()
        {
            .infoSheet.close()
            return
        }

        let texts  = appStrings()
        let path   = .explorer ? .explorer.displayPath(.currentFile) : .currentFile.toString()
        let folder = Path.directoryName(path) orelse ""
        .infoSheet.setTitle(Path.fileName(path) orelse path)
        .infoSheet.setIdentity(folder)

        // A size reads as a figure and its unit: the figure is what the reader came for.
        let size  = .currentFileSize.toString()
        let space = Utf8.lastIndexOf(size, " ")
        if space != Swag.U64.Max do
            .infoSheet.addFact(size[0 until space], size[space + 1 to])
        elif size.count do
            .infoSheet.addFact(size)

        if .activeChoiceIndex < .choices.count
        {
            let plugin = &.index.plugins[.choices[.activeChoiceIndex].pluginIndex]
            .infoSheet.addReading(texts.ui_Viewer, plugin.displayName(), mono: false)
        }

        let details = .activeChoiceIndex < .instances.count ? .instances[.activeChoiceIndex].details.toString() : ""
        if details.count do
            .infoSheet.addText(details)

        .infoSheet.addLink(texts.ui_MenuLocate, ViewerCommands.Locate)
        .infoSheet.addLink(texts.ui_MenuCopyPath, ViewerCommands.CopyPath)
        .infoSheet.setAction(texts.ui_MenuOpenDefault, ViewerCommands.OpenDefault)
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
        case ViewerCommands.MatchCase:         .searchMatchCaseOption = not .searchMatchCaseOption
        case ViewerCommands.WholeWord:         .searchWholeWordOption = not .searchWholeWordOption
        case ViewerCommands.RegularExpression: .searchRegexOption = not .searchRegexOption
        default:                               return
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
    default:                          return 0
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
