impl LibraryWnd
{
    // The captures themselves, on a recessed ground of their own.
    mtd createCaptureGrid()
    {
        with .captureHost = Wnd.create'ScrollWnd(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Panel
            .style.addStyleSheetColors("wnd_Bk $view_Bk")
        }

        with .view = Wnd.create'LibraryView(me.captureHost)
        {
            .libWnd    = me
            .padding   = 8
            .scrollWnd = me.captureHost
            .mainWnd   = me.main
        }

        .captureHost.setView(.view)
    }

    // The date list of the side bar, followed by the application and tag groups once the
    // previews have loaded.
    mtd createDateList()
    {
        with .listCtrl = ListCtrl.createMultiColumns(me.sideBar)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .addColumn("name", SideBarWidth - LibCountWidth - LibRowIndent)
            .addColumn("count", LibCountWidth)
            .listView.style.addStyleSheetColors("listItem_SelectedBk $listItem_FocusSelectedBk")
            .setLineHeight(30)
            .updateFlags(.PreserveSelectionOnEmptyClick | .ReserveExpandMargin)
            .scrollWnd.updateFlags(.CompactBars | .AlwaysShowVertical | .TransparentBars)
            .header.hide()
            .sigSelectionChanged += func|libWnd = me|(list)
            {
                let sel = list.selectedLine()
                if not sel do
                    return
                libWnd.applySidebarFilter(sel)
            }
        }
    }

    // The folder path bar: it shows the real library folder and lets the user walk it, since
    // its sub-folders, the recycle bin included, are reachable from the chevrons.
    mtd createBreadcrumb()
    {
        with .breadcrumb = BreadcrumbCtrl.create(me.barPanel, {0, 0, 0, themeActionButtonSize(me.themeMetrics())})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .sigItemPressed  += func|libWnd = me|(bc, idx) { libWnd.navigateFolder(bc.items[idx].tag) }
            .sigFillMenu     += func|libWnd = me|(bc, idx, menu) { libWnd.fillBreadcrumbMenu(bc, idx, menu) }
            .sigMenuSelected += func|libWnd = me|(?, ?, id) { libWnd.navigateFolder(id) }
        }
    }

    // One named drop-down of the command bar: a glyph, the word beside it, and the arrow that
    // says a menu opens.
    mtd createMenuButton(icon: Icon, text: string)->*IconButton
    {
        with let button = IconButton.create(me.commandBar, icon, {0, 0, 0, themeActionButtonSize(me.themeMetrics())})
        {
            .preferredSize.x = 0
            .setText(text)
            .updateFlags(.CenterContent)
            .setTextPosition(.Right)
            .setArrowPosition(.RightDownward)
        }

        return button
    }

    // The command row of the library: the presentation menus, the folder menu, the loading
    // state, and the live search against the right edge.
    mtd createCommandBar()
    {
        let metrics  = .themeMetrics()
        let iconSize = themeActionIconSize(metrics)
        with .commandBar = StackLayoutCtrl.create(me.barPanel, .Left, {0, 0, 0, themeActionButtonSize(metrics)})
        {
            .dockStyle       = .Top
            .spacing         = LibButtonGap
            .padding         = {2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding, 2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding}
            .backgroundStyle = .Transparent
        }

        // Thumbnail size and the information painted over thumbnails share one menu, because
        // both control presentation rather than library contents.
        .viewBtn = .createMenuButton(.theme().icon(.ActualSize, iconSize), appStrings().ui_BarView)
        .viewBtn.sigPressed += func|libWnd = me|(btn)
        {
            with let menu = MenuCtrl.createPopup(libWnd)
            {
                .updateFlags(.HideShortcuts)
                .addItem(ActionRecentSize.LibSmall)
                .addItem(ActionRecentSize.LibMedium)
                .addItem(ActionRecentSize.LibBig)
                .addSeparator()

                .addItem(ActionLibView.Ratings)
                .addItem(ActionLibView.LinkMarkers)
            }

            discard menu.doModal(assume cast(*IconButton, btn), autoDestroy: true)
        }

        .sortBtn = .createMenuButton(.theme().icon(.Sort, iconSize), appStrings().ui_BarSort)
        .sortBtn.sigPressed += func|libWnd = me|(btn)
        {
            with let menu = MenuCtrl.createPopup(libWnd)
            {
                .updateFlags(.HideShortcuts)
                .addItem(ActionLibSort.Recent)
                .addItem(ActionLibSort.Modified)
                .addItem(ActionLibSort.Name)
                .addItem(ActionLibSort.Application)
                .addItem(ActionLibSort.WindowTitle)
                .addItem(ActionLibSort.Dimensions)
                .addItem(ActionLibSort.FileSize)
                .addItem(ActionLibSort.Similar)
                .addSeparator()
                .addItem(ActionLibSort.Invert)
            }

            discard menu.doModal(assume cast(*IconButton, btn), autoDestroy: true)
        }

        .filterBtn = .createMenuButton(.theme().icon(.Filter, iconSize), appStrings().ui_BarFilter)
        .filterBtn.sigPressed += func|libWnd = me|(btn) { libWnd.showFilterMenu(assume cast(*IconButton, btn)) }

        // Library roots and ordinary image folders are explicit choices, named like every
        // neighbouring command instead of leaving one unexplained glyph in the sentence.
        .folderBtn            = .createMenuButton(.theme().icon(.OpenFile, iconSize), appStrings().ui_BarFolders)
        .folderBtn.toolTip    = appStrings().tip_LibraryFolders
        .folderBtn.sigPressed += func|libWnd = me|(btn) { libWnd.showFolderMenu(assume cast(*IconButton, btn)) }

        // Loading state stays with the commands it updates, before the flexible gap, so it
        // appears without moving the search field away from the right edge.
        .view.imgSpin = Spinner.create(.commandBar, {0, 0, iconSize, iconSize})
        .view.imgSpin.hide()

        let spacer = Wnd.create'Wnd(.commandBar)
        spacer.layoutSpec.policyX = .Expand

        with .searchEdit = EditBox.create(me.commandBar, "", {0, 0, 220, themeActionButtonSize(metrics)}, flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .setForm(.Rectangle)
            .setPlaceholder(appStrings().ui_Search)
            .sigTextChanged += func|libWnd = me|(ed) { libWnd.setSearch(ed.text()) }
        }
    }
}
