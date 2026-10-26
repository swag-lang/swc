impl LibraryWnd
{
    // Counts the loaded captures per source application, or per tag, for the sidebar groups.
    mtd collectNamedFilters(applications: bool)->Array'LibraryNamedFilter
    {
        var result: retval
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

    // Adds a sidebar group named `name` with one line per value and its count; adds nothing when
    // there is no value.
    mtd addNamedFilterGroup(name: string, kind: LibrarySidebarFilter, values: *Array'LibraryNamedFilter)
    {
        if values.isEmpty() do
            return

        with let root = .listCtrl.createLine(name, .theme().icon(.Filter, themeRowIconSize(.themeMetrics())))
        {
            .userData0 = cast(Swag.U64.Max)
            .userData3 = cast(cast(u64, kind))
        }

        let rootCount = root.setItem(1, Format.toString("% ", values.count))
        rootCount.horzAlign = .Right

        for value, i in values[]
        {
            var icon: Icon
            if kind == .Application and
               not value.executable.isEmpty() and
               Path.isValidPathName(value.executable)
            {
                icon       = .app().fileIcon(value.executable)
                icon.color = Argb.White
            }

            with let line = .listCtrl.createLine(value.name, icon, parentLine: root)
            {
                .userData0 = cast(i)
                .userData3 = cast(cast(u64, kind))
            }

            let count = line.setItem(1, Format.toString("% ", value.count))
            count.horzAlign = .Right
        }

        .listCtrl.expand(root)
    }

    // Gives the wording column exactly the horizontal room left by the fixed count column,
    // header separators and compact vertical bar. Deriving that room from the laid-out view is
    // what prevents a fixed-width rail from manufacturing a horizontal scroll bar.
    mtd layoutSidebarColumns()
    {
        if .listCtrl == null do
            return
        let available = .listCtrl.listView.paddedClientRect().width
        if available <= 0 do
            return

        let nameColumn = 0'u32
        let others     = .listCtrl.header.contentWidth() - .listCtrl.header.itemWidthForColumn(nameColumn)
        .listCtrl.setColumnWidth(nameColumn, Math.max(80, available - others))
        .listCtrl.computeLayout()
    }

    // Selects the sidebar line of the filter in force: the application, the tag, or the date.
    mtd selectActiveSidebarLine()
    {
        var wantedKind = LibrarySidebarFilter.Date
        if not .applicationFilter.isEmpty() do
            wantedKind = .Application
        elif not .tagFilter.isEmpty() do
            wantedKind = .Tag

        for i in .listCtrl.lineCount()
        {
            let line = unwrap .listCtrl.lineAt(cast(u32, i))
            let kind = cast(LibrarySidebarFilter, cast(u64, line.userData3))
            if kind != wantedKind do
                continue

            var matches = false
            switch kind
            {
            case .Date:
                matches = cast(u64, line.userData0) == .view.filterYear and
                          cast(u64, line.userData1) == .view.filterMonth and
                          cast(u64, line.userData2) == .view.filterDay

            case .Application:
                let idx = cast(u64, line.userData0)
                matches = idx < .sidebarApplications.count and Utf8.compare(.sidebarApplications[idx].name.toSlice(), .applicationFilter, .Latin1NoCase) == 0

            case .Tag:
                let idx = cast(u64, line.userData0)
                matches = idx < .sidebarTags.count and Utf8.compare(.sidebarTags[idx].name.toSlice(), .tagFilter, .Latin1NoCase) == 0
            }

            if matches
            {
                .listCtrl.selectLine(cast(u32, i))
                return
            }
        }
    }

    // Rebuilds the sidebar: all captures, the year, month, and day tree of their dates, then the
    // application and tag groups.
    mtd rebuildSidebar()
    {
        .updatingSidebar = true
        defer .updatingSidebar = false
        .listCtrl.clear()

        let line = .listCtrl.createLine(appStrings().ui_AllCaptures, .main.icon(.Archive, themeRowIconSize(.themeMetrics())))
        var item = line.setItem(1, Format.toString("% ", g_Library.files.count))
        item.horzAlign = .Right

        g_Library.files.sort(func(a, b) => b.lastWriteTime <=> a.lastWriteTime)

        var lastDateTime:    DateTime
        var hasLastDateTime: bool
        var lastLine:        *ListLine?
        var lastLineYear:    *ListLine?
        var lastLineMonth:   *ListLine?
        var lastLineDay:     *ListLine?

        let icon1 = .main.icon(.Calendar, themeRowIconSize(.themeMetrics()))
        var cptYear, cptMonth, cptDay = 0

        #[Swag.Mixin]
        func fillLastYear()
        {
            if lastLineYear
            {
                item           = lastLineYear.setItem(1, Format.toString("% ", cptYear))
                item.horzAlign = .Right
                cptYear        = 0
            }
        }

        #[Swag.Mixin]
        func fillLastMonth()
        {
            if lastLineMonth
            {
                item           = lastLineMonth.setItem(1, Format.toString("% ", cptMonth))
                item.horzAlign = .Right
                cptMonth       = 0
            }
        }

        #[Swag.Mixin]
        func fillLastDay()
        {
            if lastLineDay
            {
                item           = lastLineDay.setItem(1, Format.toString("% ", cptDay))
                item.horzAlign = .Right
                cptDay         = 0
            }
        }

        for fi in g_Library.files
        {
            if not hasLastDateTime or fi.lastWriteTime.year != lastDateTime.year
            {
                fillLastYear()
                lastLine           = .listCtrl.createLine(Format.toString("%", fi.lastWriteTime.year), icon1)
                lastLine.userData0 = cast(cast(u64, fi.lastWriteTime.year))
                lastLineYear       = lastLine
            }

            if not hasLastDateTime or fi.lastWriteTime.month != lastDateTime.month
            {
                fillLastMonth()
                let monthLabel = Format.toString("%", DateTime.monthName(fi.lastWriteTime.month))
                lastLine           = .listCtrl.createLine(monthLabel, icon1, lastLineYear)
                lastLine.userData0 = cast(cast(u64, fi.lastWriteTime.year))
                lastLine.userData1 = cast(cast(u64, fi.lastWriteTime.month))
                lastLineMonth      = lastLine
            }

            if not hasLastDateTime or fi.lastWriteTime.day != lastDateTime.day
            {
                fillLastDay()
                let dayLabel = Format.toString("%, %",
                                               DateTime.dayOfWeekName(fi.lastWriteTime.dayOfWeek()),
                                               fi.lastWriteTime.day)
                lastLine           = .listCtrl.createLine(dayLabel, icon1, lastLineMonth)
                lastLine.userData0 = cast(cast(u64, fi.lastWriteTime.year))
                lastLine.userData1 = cast(cast(u64, fi.lastWriteTime.month))
                lastLine.userData2 = cast(cast(u64, fi.lastWriteTime.day))
                lastLineDay        = lastLine
            }

            lastDateTime    = fi.lastWriteTime
            hasLastDateTime = true
            cptYear, cptMonth, cptDay += 1
        }

        fillLastYear()
        fillLastMonth()
        fillLastDay()

        .addNamedFilterGroup(appStrings().act_Application, .Application, &.sidebarApplications)
        .addNamedFilterGroup(appStrings().act_Tags, .Tag, &.sidebarTags)
        .selectActiveSidebarLine()
        .layoutSidebarColumns()
    }

    mtd refreshAutomaticFilters(force = false)
    {
        if .listCtrl == null do
            return

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

    // Filters the library by the sidebar `line` that was picked: a date, an application, or a
    // tag.
    mtd applySidebarFilter(line: *ListLine)
    {
        if .updatingSidebar do
            return

        .view.filterYear, .view.filterMonth, .view.filterDay = 0
        .applicationFilter.clear()
        .tagFilter.clear()

        let kind = cast(LibrarySidebarFilter, cast(u64, line.userData3))
        switch kind
        {
        case .Date:
            .view.filterYear  = cast(u64, line.userData0)
            .view.filterMonth = cast(u64, line.userData1)
            .view.filterDay   = cast(u64, line.userData2)

        case .Application:
            let idx = cast(u64, line.userData0)
            if idx < .sidebarApplications.count do
                .applicationFilter = .sidebarApplications[idx].name

        case .Tag:
            let idx = cast(u64, line.userData0)
            if idx < .sidebarTags.count do
                .tagFilter = .sidebarTags[idx].name
        }

        .view.filter()
    }

    mtd uniqueFilterValues(applications: bool)->Array'String
    {
        var result: retval
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
    }
}

// The commands each group of the library options offers, in the order a page lists them. A page
// borrows its identifiers, which these constants keep alive for as long as the program runs.
const ThumbnailSizeIds = [ActionRecentSize.LibSmall, ActionRecentSize.LibMedium, ActionRecentSize.LibBig]
const SortIds          = [ActionLibSort.Recent, ActionLibSort.Modified, ActionLibSort.Name, ActionLibSort.Application, ActionLibSort.WindowTitle, ActionLibSort.Dimensions, ActionLibSort.FileSize, ActionLibSort.Similar]
const ContentFilterIds = [ActionLibFilter.AllItems, ActionLibFilter.Captures, ActionLibFilter.ScreenCaptures, ActionLibFilter.ImportedCaptures, ActionLibFilter.Images]
const RatingFilterIds  = [ActionLibFilter.RatingAny, ActionLibFilter.Rating1, ActionLibFilter.Rating2, ActionLibFilter.Rating3, ActionLibFilter.Rating4, ActionLibFilter.Rating5]
const LinkFilterIds    = [ActionLibFilter.UpToDateLinkedImage, ActionLibFilter.UnSavedLinkedImage, ActionLibFilter.LinkedImage, ActionLibFilter.UnLinkedImage]
