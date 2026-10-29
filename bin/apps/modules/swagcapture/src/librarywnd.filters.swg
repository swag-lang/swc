impl LibraryWnd
{
    // Counts the loaded captures per source application, or per tag, for the sidebar groups.
    mtd collectNamedFilters(applications: bool)->Array'LibraryNamedFilter
    {
        var result: #returntype
        for item in .view.allItems
        {
            .view.mutexLoaded.lock()
            let capture = item!.capture
            .view.mutexLoaded.unlock()
            if not capture do
                continue

            if applications
            {
                if capture.sourceApplication.isEmpty() do
                    continue

                var found = false
                for &entry in result where Utf8.compare(entry.name.toSlice(), capture.sourceApplication, .Latin1NoCase) == 0
                {
                    entry.count += 1
                    if entry.executable.isEmpty() and not capture.sourceExecutable.isEmpty() do
                        entry.executable = capture.sourceExecutable
                    found = true
                }

                if not found do
                    result.add(LibraryNamedFilter{capture.sourceApplication, capture.sourceExecutable, 1})
                continue
            }

            for tag in capture.tags
            {
                var found = false
                for &entry in result where Utf8.compare(entry.name.toSlice(), tag[], .Latin1NoCase) == 0
                {
                    entry.count += 1
                    found       = true
                }

                if not found do
                    result.add(LibraryNamedFilter{tag[], "", 1})
            }
        }

        result.sort(func(a, b) => Utf8.compare(a.name.toSlice(), b.name.toSlice(), .Latin1NoCase))
        return result
    }

    // Returns the words of a date filter: the year, the month and its year, or the day, its
    // month and its year.
    func dateFilterLabel(filter: LibraryDateFilter)->String
    {
        if filter.month == 0 do
            return Format.toString("%", filter.year)
        let month = DateTime.monthName(cast(u8, filter.month))
        if filter.day == 0 do
            return Format.toString("% %", month, filter.year)
        return Format.toString("% % %", filter.day, month, filter.year)
    }

    // Rebuilds what the library can be narrowed to: the dates its captures were taken on, newest
    // first, for the lens; the tags, as chips; the folders, as tabs.
    mtd rebuildSidebar()
    {
        .dateFilters.clear()
        g_Library.files.sort(func(a, b) => b.lastWriteTime <=> a.lastWriteTime)

        var year, month, day = Swag.U64.Max
        var yearIdx, monthIdx, dayIdx: u64
        for fi in g_Library.files
        {
            let t = fi.lastWriteTime
            if t.year != year
            {
                month   = Swag.U64.Max
                day     = Swag.U64.Max
                yearIdx = .dateFilters.count
                .dateFilters.add(LibraryDateFilter{year: t.year})
            }

            if t.month != month
            {
                day      = Swag.U64.Max
                monthIdx = .dateFilters.count
                .dateFilters.add(LibraryDateFilter{year: t.year, month: t.month})
            }

            if t.day != day
            {
                dayIdx = .dateFilters.count
                .dateFilters.add(LibraryDateFilter{year: t.year, month: t.month, day: t.day})
            }

            year  = t.year
            month = t.month
            day   = t.day
            .dateFilters[yearIdx].count += 1
            .dateFilters[monthIdx].count += 1
            .dateFilters[dayIdx].count += 1
        }

        .updateTagChips()
        .updateFolderTabs()
    }

    mtd refreshAutomaticFilters(force = false)
    {
        let applications = .collectNamedFilters(true)
        let tags         = .collectNamedFilters(false)
        if not force and
           Slice.equals(.sidebarApplications.toSlice(), applications.toSlice()) and
           Slice.equals(.sidebarTags.toSlice(), tags.toSlice()) do
            return

        .sidebarApplications = applications
        .sidebarTags         = tags
        .rebuildSidebar()
    }

    // Narrows the library to the captures of a date, or shows every date with a zero year.
    mtd applyDateFilter(filter: LibraryDateFilter)
    {
        .view.filterYear  = filter.year
        .view.filterMonth = filter.month
        .view.filterDay   = filter.day
        .view.filter()
    }

    // Answers the lens on the library page: its commands, the folders to open, the dates, the
    // applications and the tags to narrow it to.
    mtd describeLens(results: *Lens.Results)
    {
        let texts = appStrings()
        let query = results.query.toString()

        // The commands of the page: those of the selection, how it is shown, what it filters and
        // which folder it reads. They route through the page, where the library registers them.
        .describeCommands(results, query, texts.act_Library, SelectionIds)
        .describeActions(results, query)
        .describeCommands(results, query, texts.ui_BarView, ThumbnailSizeIds)
        .describeCommands(results, query, texts.ui_BarView, SortIds)
        .describeCommands(results, query, texts.ui_BarView, OverlayIds)
        .describeCommands(results, query, texts.ui_BarFilter, ContentFilterIds)
        .describeCommands(results, query, texts.ui_BarFilter, [ActionLibFilter.FavoritesOnly])
        .describeCommands(results, query, texts.ui_BarFilter, RatingFilterIds)
        .describeCommands(results, query, texts.ui_BarFilter, LinkFilterIds)
        .describeCommands(results, query, texts.ui_BarFilter, [ActionLibFilter.Reset])
        .describeFolderCommands(results, query)
        .describeFolders(results, query)
        .describeDates(results, query)
        .describeNamed(results, query, texts.act_Application, &.sidebarApplications, application: true)
        .describeNamed(results, query, texts.act_Tags, &.sidebarTags, application: false)
    }

    // Answers the lens at rest on the library page: what can be done with the chosen captures —
    // open, export, tags, favourite, move, delete — and their rating, then what the page shows.
    // Every other command of the page is one word away.
    mtd describeLensRest(results: *Lens.Results)
    {
        let texts  = appStrings()
        let chosen = .selectedFiles()
        if .trashMode
        {
            .describeCommands(results, "", texts.lens_Selection, [ActionLibTrash.Restore, ActionLibTrash.DeleteForever])
        }
        elif not chosen.isEmpty() and .view.focusItem < .view.items.count
        {
            let family  = texts.lens_Selection
            let focused = .view.items[.view.focusItem]
            describeAction(results, "", family, texts.act_OpenSelected, func|libWnd = me, focused|() { libWnd.view.openItem(focused) })
            if focused.kind == .Image do
                describeAction(results, "", family, texts.act_LocateImage, func|focused|() { discard Env.showInFileExplorer(focused.fi.fullName) })
            else
            {
                describeAction(results, "", family, texts.act_ExportSelected, func|libWnd = me|() { libWnd.exportSelected() })
                describeAction(results, "", family, texts.act_EditTags, func|libWnd = me|() { libWnd.editSelectedTags() })
                describeAction(results, "", family, texts.act_FavoriteCapture, func|libWnd = me|() { libWnd.toggleSelectedFavorite() })
            }

            describeAction(results, "", family, texts.act_MoveSelected, func|libWnd = me|() { libWnd.moveSelected() })
            .describeCommands(results, "", family, [ActionFile.DeleteCapture])

            // The rating is one choice among six, one row of segments.
            if focused.kind != .Image
            {
                let rating  = results.addSection(texts.act_Rating)
                rating.inline = true
                let current = focused.capture ? focused.capture.rating : 0
                for value in 6
                {
                    let stars = cast(u8, value)
                    with let entry = rating.addEntry(ratingLabel(stars))
                    {
                        .checked = stars == current
                        .run     = func|libWnd = me, stars|() { libWnd.rateSelected(stars) }
                    }
                }
            }
        }

        // Then what the page shows, one row of segments.
        let filter = results.addSection(texts.ui_BarFilter)
        filter.inline = true
        for id in ContentFilterIds
        {
            let state = .sendComputeCommandStateEvent(id)
            with let entry = filter.addEntry(state.name)
            {
                .checked = state.updatedFields.has(.Checked) and state.checked
                .run     = func|libWnd = me, id|() { libWnd.sendCommandEvent(id) }
            }
        }
    }

    // Returns the section of `results` labelled `label`, adding it the first time.
    func sectionOf(results: *Lens.Results, label: string)->*Lens.Section
    {
        for section in results.sections where section!.label == label do
            return section
        return results.addSection(label)
    }

    // Adds the commands of `ids` the query names, with their wording and state, under `family`.
    mtd describeCommands(results: *Lens.Results, query: string, family: string, ids: const [..] WndId)
    {
        for id in ids
        {
            let state = .sendComputeCommandStateEvent(id)
            if state.updatedFields.has(.Hidden) and state.hidden do
                continue
            if state.name.isEmpty() or not Lens.match(query, state.name).matched do
                continue

            with let entry = sectionOf(results, family).addEntry(state.name)
            {
                .disabled = state.updatedFields.has(.Disabled) and state.disabled
                .run      = func|libWnd = me, id|() { libWnd.sendCommandEvent(id) }
                if state.updatedFields.has(.Checked) and state.checked do
                    .detail = LensCheck
                if state.updatedFields.has(.Icon) do
                    .glyph = state.icon
            }
        }
    }

    // Adds one action the query names under `family`.
    func describeAction(results: *Lens.Results, query: string, family: string, title: string, action: func||())
    {
        if not Lens.match(query, title).matched do
            return
        sectionOf(results, family).addEntry(title).run = action
    }

    // Adds the actions on the selected captures the query names: open, export, tags, favorite
    // and rating, as the context menu of a capture offers them.
    mtd describeActions(results: *Lens.Results, query: string)
    {
        if .trashMode or .view.focusItem >= .view.items.count do
            return

        let texts   = appStrings()
        let family  = texts.act_Library
        let focused = .view.items[.view.focusItem]
        describeAction(results, query, family, texts.act_OpenSelected, func|libWnd = me, focused|() { libWnd.view.openItem(focused) })
        if focused.kind == .Image
        {
            describeAction(results, query, family, texts.act_LocateImage, func|focused|() { discard Env.showInFileExplorer(focused.fi.fullName) })
            return
        }

        describeAction(results, query, family, texts.act_ExportSelected, func|libWnd = me|() { libWnd.exportSelected() })
        describeAction(results, query, family, texts.act_EditTags, func|libWnd = me|() { libWnd.editSelectedTags() })
        describeAction(results, query, family, texts.act_FavoriteCapture, func|libWnd = me|() { libWnd.toggleSelectedFavorite() })
        for rating in 6
        {
            let value = cast(u8, rating)
            describeAction(results, query, family, ratingLabel(value), func|libWnd = me, value|() { libWnd.rateSelected(value) })
        }
    }

    // Adds the commands of the folder menu the query names.
    mtd describeFolderCommands(results: *Lens.Results, query: string)
    {
        let texts  = appStrings()
        let family = texts.ui_BarFolders
        describeAction(results, query, family, texts.act_OpenLibraryFolder, func|libWnd = me|() { libWnd.navigateFolder(Library.getFolder()) })
        describeAction(results, query, family, texts.act_BrowseFolder, func|libWnd = me|() { libWnd.chooseFolder(false) })
        describeAction(results, query, family, texts.act_ChooseLibraryFolder, func|libWnd = me|() { libWnd.chooseFolder(true) })
        describeAction(results, query, family, texts.act_UseDefaultLibrary, func|libWnd = me|() { libWnd.setLibraryFolder("") })
        .describeCommands(results, query, family, FolderIds)
    }

    // Adds the folders the query names: the library, its sub-folders and those of the folder
    // shown, the recycle bin among them.
    mtd describeFolders(results: *Lens.Results, query: string)
    {
        // The paths live on the page until the lens asks again, so a row chosen after the lens
        // closed still names its folder.
        .lensFolders.clear()
        .lensFolders.add(Library.getFolder())
        for folder in .tabFolders where not .lensFolders.contains(folder[]) do
            .lensFolders.add(folder[])
        let dirs = catch Directory.enumerateDirectories(.currentFolder())
        for d in dirs where not .lensFolders.contains(d.fullName) do
            .lensFolders.add(d.fullName)

        for entryFolder, index in .lensFolders
        {
            let folder       = entryFolder[]
            var name: String = Path.fileName(folder) orelse folder.toString()
            if folder == Library.getFolder() do
                name = appStrings().act_Library
            elif folder == Library.getTrashFolder() do
                name = appStrings().act_RecycleBin
            if not Lens.match(query, name).matched do
                continue

            with let entry = sectionOf(results, appStrings().ui_BarFolders).addEntry(name)
            {
                .glyph = me.theme().icon(.Folder)
                .run   = func|libWnd = me, index|()
                {
                    let path: String = libWnd.lensFolders[index]
                    libWnd.navigateFolder(path)
                }
                if folder == me.currentFolder() do
                    .detail = LensCheck
            }
        }
    }

    // Adds the dates the query names; choosing one narrows the library to it.
    mtd describeDates(results: *Lens.Results, query: string)
    {
        let family = appStrings().lens_Dates
        let all    = appStrings().ui_AllCaptures
        if Lens.match(query, all).matched or Lens.match(query, family).matched
        {
            with let entry = sectionOf(results, family).addEntry(all)
            {
                .run = func|libWnd = me|() { libWnd.applyDateFilter({}) }
                if me.view.filterYear == 0 do
                    .detail = LensCheck
            }
        }

        for filter in .dateFilters
        {
            let label = dateFilterLabel(filter)
            if not Lens.match(query, label).matched do
                continue
            with let entry = sectionOf(results, family).addEntry(label)
            {
                .lead = Format.toString("%", filter.count)
                .run  = func|libWnd = me, filter|() { libWnd.applyDateFilter(filter) }
                if filter.year == me.view.filterYear and filter.month == me.view.filterMonth and filter.day == me.view.filterDay do
                    .detail = LensCheck
            }
        }
    }

    // Adds the applications or the tags the query names; choosing one narrows the library to it.
    mtd describeNamed(results: *Lens.Results, query: string, family: string, values: *Array'LibraryNamedFilter, application: bool)
    {
        for value in values[]
        {
            let name = value.name.toString()
            if not Lens.match(query, name).matched and not Lens.match(query, family).matched do
                continue
            with let entry = sectionOf(results, family).addEntry(name)
            {
                .lead = Format.toString("%", value.count)
                if application do
                    .run = func|libWnd = me, name|() { libWnd.setApplicationFilter(name) }
                else do
                    .run = func|libWnd = me, name|() { libWnd.setTagFilter(name) }
                let active = application ? me.applicationFilter.toString() : me.tagFilter.toString()
                if Utf8.compare(value.name.toSlice(), active, .Latin1NoCase) == 0 do
                    .detail = LensCheck
            }
        }
    }

    mtd uniqueFilterValues(applications: bool)->Array'String
    {
        var result: #returntype
        for value in .collectNamedFilters(applications) do
            result.add(value.name)
        return result
    }

    // Shows how the library is presented under `btn`: thumbnail size, order, and the marks painted
    // over each thumbnail.
    mtd showViewOptions(btn: *IconButton)
    {
        let sheet = OptionSheet.View.create(me, func|libWnd = me|(page) { libWnd.describeViewOptions(page) }, owner: me)
        sheet.doModal(btn, autoDestroy: true)
    }

    mtd describeViewOptions(page: *OptionSheet.Page)
    {
        page.addCommandLink(appStrings().ui_ThumbnailSize, ThumbnailSizeIds, me)
        page.addCommandLink(appStrings().ui_SortBy, SortIds, me)
        page.addCommand(ActionLibSort.Invert, me)
        page.addHeading(appStrings().ui_Overlays)
        page.addCommand(ActionLibView.Ratings, me)
        page.addCommand(ActionLibView.LinkMarkers, me)
    }

    // Shows the filters under `btn`: the content kinds, the favorites, one page per application,
    // tag and rating, the link states, and the reset.
    mtd showFilterOptions(btn: *IconButton)
    {
        let sheet = OptionSheet.View.create(me, func|libWnd = me|(page) { libWnd.describeFilterOptions(page) }, owner: me)
        sheet.doModal(btn, autoDestroy: true)
    }

    mtd describeFilterOptions(page: *OptionSheet.Page)
    {
        let texts = appStrings()
        page.addCommandLink(texts.ui_FilterContent, ContentFilterIds, me)
        page.addCommand(ActionLibFilter.FavoritesOnly, me)

        let application = .applicationFilter.isEmpty() ? texts.act_AllApplications : .applicationFilter.toString()
        page.addLink(texts.act_Application, application, func|libWnd = me|(choices)
        {
            choices.addChoice(appStrings().act_AllApplications, libWnd.applicationFilter.isEmpty(), func|libWnd|() { libWnd.setApplicationFilter("") })
            for &one in libWnd.uniqueFilterValues(true)
            {
                let name = one.toString()
                let on   = Utf8.compare(one.toSlice(), libWnd.applicationFilter, .Latin1NoCase) == 0
                choices.addChoice(name, on, func|libWnd, name|() { libWnd.setApplicationFilter(name) })
            }
        })

        let tag = .tagFilter.isEmpty() ? texts.act_AllTags : .tagFilter.toString()
        page.addLink(texts.act_Tags, tag, func|libWnd = me|(choices)
        {
            choices.addChoice(appStrings().act_AllTags, libWnd.tagFilter.isEmpty(), func|libWnd|() { libWnd.setTagFilter("") })
            for &one in libWnd.uniqueFilterValues(false)
            {
                let name = one.toString()
                let on   = Utf8.compare(one.toSlice(), libWnd.tagFilter, .Latin1NoCase) == 0
                choices.addChoice(name, on, func|libWnd, name|() { libWnd.setTagFilter(name) })
            }
        })

        page.addCommandLink(texts.ui_FilterRating, RatingFilterIds, me)
        page.addLink(texts.ui_FilterLinks, "", func|libWnd = me|(links)
        {
            for id in LinkFilterIds do
                links.addCommand(id, libWnd)
        })

        page.addCommand(ActionLibFilter.Reset, me)
    }

    // Shows only the captures of the application `name`, or every capture when it is empty.
    mtd setApplicationFilter(name: string)
    {
        .applicationFilter = name
        .view.filter()
    }

    // Shows only the captures tagged `name`, or every capture when it is empty.
    mtd setTagFilter(name: string)
    {
        .tagFilter = name
        .view.filter()
        .updateTagChips()
    }
}

// The commands each group of the library options offers, in the order a page lists them. A page
// borrows its identifiers, which these constants keep alive for as long as the program runs.
const ThumbnailSizeIds = [ActionRecentSize.LibSmall, ActionRecentSize.LibMedium, ActionRecentSize.LibBig]
const SortIds          = [ActionLibSort.Recent, ActionLibSort.Modified, ActionLibSort.Name, ActionLibSort.Application, ActionLibSort.WindowTitle, ActionLibSort.Dimensions, ActionLibSort.FileSize, ActionLibSort.Similar]
const ContentFilterIds = [ActionLibFilter.AllItems, ActionLibFilter.Captures, ActionLibFilter.ScreenCaptures, ActionLibFilter.ImportedCaptures, ActionLibFilter.Images]
const RatingFilterIds  = [ActionLibFilter.RatingAny, ActionLibFilter.Rating1, ActionLibFilter.Rating2, ActionLibFilter.Rating3, ActionLibFilter.Rating4, ActionLibFilter.Rating5]
const LinkFilterIds    = [ActionLibFilter.UpToDateLinkedImage, ActionLibFilter.UnSavedLinkedImage, ActionLibFilter.LinkedImage, ActionLibFilter.UnLinkedImage]
const OverlayIds       = [ActionLibSort.Invert, ActionLibView.Ratings, ActionLibView.LinkMarkers]
const FolderIds        = [ActionLibTrash.Toggle, ActionLibTrash.Empty]
const SelectionIds     = [ActionFile.CopyImage, ActionFile.RenameCapture, ActionFile.DeleteCapture, ActionFile.CaptureFileLocation, ActionFile.LinkedFileLocation, ActionFile.FileDetails, ActionLibTrash.Restore, ActionLibTrash.DeleteForever]

// The mark of the choice in force, at the end of its row of the lens.
const LensCheck = "✓"

