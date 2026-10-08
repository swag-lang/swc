impl ViewerWindow
{
    // Creates the appearance button, which saves the theme and language the user picks and opens
    // the about box, and the accent rail along the top edge.
    private mtd createAppearanceChrome()
    {
        .appearanceButton = AppearanceButton.create(.surface!, "scope.appearance")
        .appearanceButton.sigThemeChanged += func|window = me|(button)
        {
            window.themeIndex = cast(u32, button.appearanceTheme)
            catch window.saveState()
        }

        .appearanceButton.sigLanguageChanged += func|window = me|(button)
        {
            window.language = button.language
            catch window.saveState()
        }

        .appearanceButton.sigAboutRequested += func|window = me|(_)
        {
            window.showAbout()
        }

        .accentRail = Separator.create(me, .Top, .Accent)
    }

    // Builds the global command bar: the open, open-with-default, close and full-screen buttons,
    // the centered search group, and the viewer selector closing its right edge.
    private mtd createCommandBar()
    {
        .commandBar = ViewerActionBar.create(me)
        let iconSize              = themeActionIconSize(.themeMetrics())
        let actionSize            = themeActionButtonSize(.themeMetrics())
        let dropDownWidth         = themeDropDownButtonWidth(.themeMetrics())
        let searchNavigationWidth = 2 * actionSize + SearchCountWidth + 8
        let searchBarWidth        = dropDownWidth + SearchFieldWidth + searchNavigationWidth + 2 * SearchGroupSpacing

        with .commandButtons = IconBar.create(.commandBar, iconSize, itemPadding: .themeMetrics().btnIcon_Padding)
        {
            .dockStyle = .Left
        }

        with .openButton = .commandButtons.addButton(.theme().icon(.OpenFile, iconSize))
        {
            .toolTip    = appStrings().ui_Open
            .sigPressed += func|window = me|(_) { window.chooseFile() }
        }

        with .openDefaultButton = .commandButtons.addButton(.theme().icon(.OpenExternal, iconSize))
        {
            .toolTip = appStrings().ui_OpenDefault
            .enable(false)
            .sigPressed += func|window = me|(_) { window.openCurrentFileDefault() }
        }

        with .closeButton = .commandButtons.addButton(.theme().icon(.WndClose, iconSize))
        {
            .toolTip = appStrings().ui_CloseFile
            .enable(false)
            .sigPressed += func|window = me|(_) { window.closeFile() }
        }

        with .fullScreenButton = .commandButtons.addToggleButton(.theme().icon(.FullScreen, iconSize))
        {
            .toolTip = appStrings().ui_FullScreen
            .sigCheckedChanged += func|window = me|(button) { window.setFullScreen(button.isChecked) }
        }

        with .searchGroup = StackLayoutCtrl.create(.commandBar, .Center, {0, 0, searchBarWidth, actionSize})
        {
            .backgroundStyle = .Transparent
            .spacing         = SearchGroupSpacing
            .hide()
        }

        .commandBar.centerGroup = .searchGroup

        with .searchOptionsButton = Viewer.createActionDropDown(.searchGroup, .Options)
        {
            .layoutSpec.alignY = .Center
            .toolTip = appStrings().ui_SearchOptions
            .setArrowPosition(.RightDownward)
            .sigPressed += func|window = me|(_) { window.showSearchOptionsMenu() }
        }

        with .searchBox = EditBox.create(.searchGroup, "", {0, 0, SearchFieldWidth, 36}, flags: .ClearButton)
        {
            .setIcon(me.theme().icon(.Search, iconSize))
            .setPlaceholder(appStrings().ui_Search)
            .setValidator(func|window = me|(edit)->EditBoxCheckResult => window.validateSearchEdit(edit))
            .sigTextChanged += func|window = me|(_) { window.restartSearch() }
            .sigSubmitted   += func|window = me|(_) { window.findNext() }
            .sigCancelled   += func|window = me|(_) { window.hideSearch() }
            .enable(false)
        }

        with .searchNavigation = StackLayoutCtrl.create(.searchGroup, .Center, {0, 0, searchNavigationWidth, actionSize})
        {
            .backgroundStyle = .Transparent
            .spacing         = 0
        }

        with .searchPrevious = Viewer.createActionButton(.searchNavigation, .SearchPrevious)
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchPrevious
            .sigPressed        += func|window = me|(_) { window.findPrevious() }
            .enable(false)
        }

        with .searchNext = Viewer.createActionButton(.searchNavigation, .SearchNext)
        {
            .layoutSpec.alignY = .Center
            .toolTip           = appStrings().ui_SearchNext
            .sigPressed        += func|window = me|(_) { window.findNext() }
            .enable(false)
        }

        with .searchCountLabel = Label.create(.searchNavigation, "", {0, 0, SearchCountWidth, 36}, null, .SecondaryText)
        {
            .margin.x = 8
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        .commandBar.centerContent()

        // Wide enough for the longest viewer name a shipped viewer registers beside its glyph.
        // Viewer commands have their own row, so this selector can close the global bar's right edge.
        with .viewerCombo = ComboBox.create(.commandBar, {0, 0, 180, 36})
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_Viewer
            .hide()
            .sigChanged += func|window = me|(_, index) { window.selectViewer(index) }
        }
    }

    // Builds the information band above the document: the file panel toggle, the file icon, name
    // and size, and the content statistics on the right.
    private mtd createInfoBar(panelGutter: f32)
    {
        // File identity and content statistics are read before the document. The information
        // surface follows the same panel composition as both side panes: a rounded semantic
        // ground inside one shared chrome seam. Viewer tools belong to the dedicated band below.
        with .infoBarHost = Wnd.create'Wnd(me, {0, 0, 0, InfoHeight + panelGutter * 2})
        {
            .dockStyle       = .Top
            .backgroundStyle = .ToolBar
            .padding         = {panelGutter, panelGutter, panelGutter, panelGutter}
        }

        with .infoBar = Wnd.create'ViewerInfoBar(.infoBarHost)
        {
            .dockStyle       = .Center
            .backgroundStyle = .InformationPanel
            .padding         = {8, 2, 8, 2}
        }

        with .infoContentGroup = Wnd.create'ViewerInfoLayout(.infoBar, {0, 0, 0, 36})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with .filesButton = Viewer.createActionButton(.infoContentGroup, .History, .Toggle)
        {
            .toolTip = appStrings().ui_Files
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = me|(button)
            {
                window.setFilePanelVisible(button.isChecked)
                catch window.saveState()
            }
        }

        .infoContentGroup.filesButton = .filesButton

        with .infoFileGroup = StackLayoutCtrl.create(.infoContentGroup, .Left, {0, 0, 0, 36})
        {
            .backgroundStyle = .Transparent
            .spacing         = 0
        }

        with .infoIconLabel = Label.create(.infoFileGroup, "", {0, 0, 24, 36})
        {
            .margin.z = me.themeMetrics().btnIcon_SpacingIcon
            .setIconAlignment(.Center, .Center)
        }

        with .infoNameLabel = Label.create(.infoFileGroup, "", {0, 0, 0, 36}, null, .Ellipsis)
        {
            .layoutSpec.policyX = .Expand
            .layoutSpec.weightX = 0
            .style.setFont(me.theme().createDefaultFont(13, .Bold), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with .infoSizeLabel = Label.create(.infoFileGroup, "", {0, 0, 0, 36}, null, .SecondaryText)
        {
            .margin.x = 8
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with .infoStatsLabel = Label.create(.infoContentGroup, "", {0, 0, 0, 36}, null, .SecondaryText | .Ellipsis)
        {
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Right, .OpticalCenter)
        }

        .infoContentGroup.fileGroup    = .infoFileGroup
        .infoContentGroup.generalLabel = .infoStatsLabel
    }

    private mtd createViewerBar()
    {
        with .viewerBar = Wnd.create'ViewerActionBar(me, {0, 0, 0, BarHeight})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .ToolBar
            .padding         = {12, 6, 12, 6}
            .fillCenterGroup = true
        }
    }

    // Creates one of the file lists of the side panel: a single-selection list of names that
    // fills `parent` and never scrolls sideways.
    private func createFileList(parent: *Wnd, rowIconSize: f32)->*ListCtrl
    {
        with let list = ListCtrl.createSimple(parent)
        {
            .dockStyle = .Center
            .setIconSize(rowIconSize)
            .setSelectionMode(.Single)
            .updateFlags(.HotTrack | .Ellipsis)
            .scrollWnd.padding.x = 0
            .scrollWnd.padding.z = 0
            .scrollWnd.updateFlags(.DisableHorizontal)
        }

        return list
    }

    // Builds the left file panel, hidden until toggled: a splitter holding the recent files with
    // their clear button, and the folder files with their same-kind filter and folder history.
    private mtd createFilePanel(panelGutter: f32)
    {
        let compactSize = themeCompactButtonSize(.themeMetrics())
        let rowIconSize = themeRowIconSize(.themeMetrics())

        // The toolbar-colored lane is the static seam shared with the application chrome. The
        // rounded structural panel sits inside it, so the lists read as one integrated surface
        // instead of a square block divided from the document by an unrelated rule.
        with .filePanelHost = Wnd.create'Wnd(me, {0, 0, PanelWidth + panelGutter, 0})
        {
            .dockStyle       = .Left
            .backgroundStyle = .ToolBar

            // The information lane supplies the upper seam and the viewer bar supplies the
            // lower chrome. Only the exposed outer edges need their own integration gutter.
            .padding = {panelGutter, 0, 0, 0}
            .hide()
        }

        with .filePanel = SplitterCtrl.create(.filePanelHost, {0, 0, PanelWidth, 0}, vertical: true)
        {
            .dockStyle       = .Center
            .minSize.x       = PanelWidth
            .maxSize.x       = PanelWidth
            .backgroundStyle = .Transparent
        }

        with .recentPane = Wnd.create'Wnd(.filePanel)
        {
            .backgroundStyle = .Panel
            .padding         = {0, 8, 0, 8}
        }

        with let recentHeader = Wnd.create'Wnd(.recentPane, {0, 0, 0, compactSize})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .margin          = {10, 0, 10, 0}
        }

        with .recentClearButton = IconButton.create(recentHeader, .theme().icon(.RemoveAll, rowIconSize), {0, 0, compactSize, compactSize})
        {
            .dockStyle  = .Right
            .toolTip    = appStrings().ui_ClearHistory
            .sigPressed += func|window = me|(_) { window.confirmClearRecent() }
        }

        with .recentLabel = Label.create(recentHeader, appStrings().ui_Recent, {0, 0, 0, compactSize}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with .recentList = createFileList(.recentPane, rowIconSize)
        {
            .sigSelectionChanged += func|window = me|(list) { window.openListSelection(list, window.recent.toSlice()) }
            .sigRightClicked     += func|window = me|(list, position) { window.showFileMenu(list, window.recent.toSlice(), list.listView.localToSurface(position)) }
        }

        with .folderPane = Wnd.create'Wnd(.filePanel)
        {
            .backgroundStyle = .Panel
            .padding         = {0, 8, 0, 8}
        }

        // The header carries the filter beside the folder name: the toggle changes what this
        // list holds, and the next/previous arrows walk the same list.
        with let folderHeader = Wnd.create'Wnd(.folderPane, {0, 0, 0, compactSize})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .margin          = {10, 0, 10, 0}
        }

        with .kindButton = IconButton.create(folderHeader, .theme().icon(.Filter, rowIconSize), {0, 0, compactSize, compactSize}, flags: .Toggle)
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_SameKind
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = me|(button) { window.setFolderSameKind(button.isChecked) }
        }

        with .folderHistoryButton = IconButton.create(folderHeader, .theme().icon(.History, rowIconSize), {0, 0, themeDropDownButtonWidth(.themeMetrics()), compactSize}, flags: .CenterContent)
        {
            .dockStyle = .Right
            .margin.z  = 8
            .toolTip   = appStrings().ui_FolderHistory
            .setArrowPosition(.RightDownward)
            .enable(false)
            .sigPressed += func|window = me|(_) { window.showFolderHistory() }
        }

        with .folderLabel = Label.create(folderHeader, appStrings().ui_Folder, {0, 0, 0, compactSize}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with .folderList = createFileList(.folderPane, rowIconSize)
        {
            .sigSelectionChanged += func|window = me|(list) { window.openListSelection(list, window.siblings.toSlice()) }
            .sigRightClicked     += func|window = me|(list, position) { window.showFileMenu(list, window.siblings.toSlice(), list.listView.localToSurface(position)) }
        }

        with let recentItem = .filePanel.addPane(.recentPane, RecentHeight)
        {
            .minimumSize  = PaneMinSize
            .preserveSize = true
        }

        .filePanel.addPane(.folderPane).minimumSize = PaneMinSize
    }

    // Builds the document panel with its empty-state prompt and the loading, search and drop
    // overlays drawn above the active viewer.
    private mtd createDocumentPanel(panelGutter: f32)
    {
        // The document is the middle panel of the same composition. It owns the seams on both
        // sides, so showing either optional side panel never doubles the four-pixel rhythm.
        with .documentHost = Wnd.create'Wnd(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .ToolBar
            .padding         = {panelGutter, 0, panelGutter, 0}
        }

        with .documentPanel = Wnd.create'Wnd(.documentHost)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Panel
            .style.addStyleSheetColors("wnd_Bk $view_Bk")
        }

        with .emptyView = StackLayoutCtrl.create(.documentPanel, .VerticalCenter)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .padding         = {48, 48, 48, 48}
            .spacing         = 12
        }

        with .emptyIconLabel = Label.create(.emptyView, "", {0, 0, 48, 48})
        {
            .layoutSpec.alignX = .Center
            .setIconAlignment(.Center, .Center)
        }

        with .emptyLabel = Label.create(.emptyView, Format.toString("<b>%</b>", appStrings().ui_DropTitle), {0, 0, 480, 0}, null, .WordWrap | .AutoHeight)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        with .emptyHintLabel = Label.create(.emptyView, appStrings().ui_DropHint, {0, 0, 480, 0}, null, .WordWrap | .AutoHeight | .SecondaryText)
        {
            .layoutSpec.alignX = .Center
            .setTextAlignment(.Center, .Center)
        }

        .loadingOverlay = ViewerLoadingOverlay.create(.documentPanel)
        .searchOverlay  = ViewerSearchOverlay.create(.documentPanel)
        .dropHighlight  = ViewerDropHighlight.create(.documentPanel)
    }

    private mtd hookChildEvents()
    {
        .hookOnChildEvent = func|window = me|(_, evt)
        {
            switch evt
            {
            case KeyEvent as key where window.routePlaybackKey(key):         return true
            case KeyEvent as key where window.routeSearchNavigationKey(key): return true
            case MouseEvent as mouse where mouse.kind == .Move or mouse.kind == .Enter: window.updateFullScreenChrome(mouse.surfacePos)
            }

            return false
        }
    }
}
