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
                    result.add({capture.sourceApplication, capture.sourceExecutable, 1})
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
                    result.add({tag[], "", 1})
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
            if kind == .Application and not value.executable.isEmpty() and Path.isValidPathName(value.executable)
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
            let line = .listCtrl.lineAt(cast(u32, i))!
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
                lastLine           = .listCtrl.createLine(Format.toString("%", DateTime.monthName(fi.lastWriteTime.month)), icon1, lastLineYear)
                lastLine.userData0 = cast(cast(u64, fi.lastWriteTime.year))
                lastLine.userData1 = cast(cast(u64, fi.lastWriteTime.month))
                lastLineMonth      = lastLine
            }

            if not hasLastDateTime or fi.lastWriteTime.day != lastDateTime.day
            {
                fillLastDay()
                lastLine           = .listCtrl.createLine(Format.toString("%, %", DateTime.dayOfWeekName(fi.lastWriteTime.dayOfWeek()), fi.lastWriteTime.day), icon1, lastLineMonth)
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

    mtd applyDynamicFilter(id: WndId?)
    {
        if not id do
            return
        if Utf8.startsWith(id, "capture.library.app:")
        {
            .applicationFilter = id[("capture.library.app:").count to]
            .view.filter()
        }
        elif Utf8.startsWith(id, "capture.library.tag:")
        {
            .tagFilter = id[("capture.library.tag:").count to]
            .view.filter()
        }
    }

    // Shows the filter menu under `btn`: the content kinds, the link states, the rating, and one
    // entry per known application and tag.
    mtd showFilterMenu(btn: *IconButton)
    {
        let applications = .uniqueFilterValues(true)
        let tags         = .uniqueFilterValues(false)

        .menuValues.clear()
        .menuValues.reserve(2 * (applications.count + tags.count) + 2)

        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(ActionLibFilter.Reset)
            .addSeparator()
            .addItems([ActionLibFilter.AllItems, ActionLibFilter.Captures, ActionLibFilter.ScreenCaptures, ActionLibFilter.ImportedCaptures, ActionLibFilter.Images])
            .addSeparator()
            .addItem(ActionLibFilter.FavoritesOnly)

            with let apps = MenuCtrl.createPopup(menu, owner: me)
            {
                me.menuValues.add("capture.library.app:")
                .addItem(appStrings().act_AllApplications, me.menuValues.back(), checked: me.applicationFilter.isEmpty())
                for application in applications
                {
                    me.menuValues.add(Format.toString("capture.library.app:%", application[]))
                    .addItem(application[], me.menuValues.back(), checked: Utf8.compare(application.toSlice(), me.applicationFilter, .Latin1NoCase) == 0)
                }

                menu.addPopup(appStrings().act_Application, apps)
            }

            with let tagMenu = MenuCtrl.createPopup(menu, owner: me)
            {
                me.menuValues.add("capture.library.tag:")
                .addItem(appStrings().act_AllTags, me.menuValues.back(), checked: me.tagFilter.isEmpty())
                for tag in tags
                {
                    me.menuValues.add(Format.toString("capture.library.tag:%", tag[]))
                    .addItem(tag[], me.menuValues.back(), checked: Utf8.compare(tag.toSlice(), me.tagFilter, .Latin1NoCase) == 0)
                }

                menu.addPopup(appStrings().act_Tags, tagMenu)
            }

            .addSeparator()
            .addItems([ActionLibFilter.RatingAny, ActionLibFilter.Rating1, ActionLibFilter.Rating2, ActionLibFilter.Rating3, ActionLibFilter.Rating4, ActionLibFilter.Rating5])
            .addSeparator()
            .addItem(ActionLibFilter.UpToDateLinkedImage)
            .addItem(ActionLibFilter.UnSavedLinkedImage)
            .addItem(ActionLibFilter.LinkedImage)
            .addItem(ActionLibFilter.UnLinkedImage)
        }

        .applyDynamicFilter(menu.doModal(btn, autoDestroy: true))
    }
}
