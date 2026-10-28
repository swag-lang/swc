impl ViewerWindow
{
    // Creates the owner of the theme and language the reader picks, which saves them and opens the
    // about box. Its choices are lens entries, so its button stays off the window chrome.
    private mtd createAppearanceChrome()
    {
        .appearanceButton = AppearanceButton.create(unwrap .surface, "scope.appearance")
        .appearanceButton.hide()
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
    }

    // Builds the find bar floating at the top of the document while the reader searches: the
    // options of the search, the query, and the way through its matches.
    private mtd createSearchBar()
    {
        let iconSize              = themeActionIconSize(.themeMetrics())
        let actionSize            = themeActionButtonSize(.themeMetrics())
        let dropDownWidth         = themeDropDownButtonWidth(.themeMetrics())
        let searchNavigationWidth = 2 * actionSize + SearchCountWidth + 8
        let searchBarWidth        = dropDownWidth + SearchFieldWidth + searchNavigationWidth + 2 * SearchGroupSpacing

        with .searchBar = FloatingPanel.create(me, {0, 0, searchBarWidth, actionSize}, "scope.search")
        {
            .padding = {8, 6, 8, 6}
            .hide()
        }

        with .searchGroup = StackLayoutCtrl.create(.searchBar, .Center, Math.Rectangle{0, 0, searchBarWidth, actionSize})
        {
            .backgroundStyle = .Transparent
            .spacing         = SearchGroupSpacing
        }

        with .searchOptionsButton = Viewer.createActionDropDown(.searchGroup, .MatchWholeWord)
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

        with .searchNavigation = StackLayoutCtrl.create(.searchGroup, .Center, Math.Rectangle{0, 0, searchNavigationWidth, actionSize})
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
    }

    // Builds the floating bar the active viewer's commands stand in, at the foot of the document.
    private mtd createViewerBar()
    {
        with .viewerBar = FloatingPanel.create(me, {0, 0, 0, BarHeight}, "scope.commands")
        {
            .padding = {12, 6, 12, 6}
            .hide()
        }
    }

    // Builds the sheet of readings `I` opens, and the hint teaching the door while the window is
    // empty.
    private mtd createSheetAndHint()
    {
        .infoSheet = InfoSheet.create(me, "scope.information")
        with .hintLine = HintLine.create(me, "scope.hint")
        {
            .addHint(Gui.strings().key_Space, appStrings().ui_HintLens)
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
            .scrollWnd.updateFlags(.DisableHorizontal | .CompactBars)
        }

        return list
    }

    // Builds the left file panel, hidden until asked for: a sheet-shaped card beside the work
    // holding the recent files with their clear button, and the folder files with their
    // same-kind filter and folder history.
    private mtd createFilePanel()
    {
        let compactSize = themeCompactButtonSize(.themeMetrics())
        let rowIconSize = themeRowIconSize(.themeMetrics())
        let gutter      = .themeMetrics().floating_Inset

        // The card stands in the air of the window, the floating inset away from its edges; the
        // splitter beside it lets the reader widen it.
        with .filePanelHost = Wnd.create'Wnd(.mainSplitter, Math.Rectangle{0, 0, .leftPanelWidth + gutter, 0})
        {
            .backgroundStyle = .Transparent
            .padding         = Math.Vector4{gutter, 0, 0, gutter}
            .hide()
        }

        with let card = FloatingPanel.create(.filePanelHost)
        {
            .dockStyle = .Center
            .padding   = {4, 8, 4, 8}
            .setShadow(false)
        }

        with .filePanel = SplitterCtrl.create(card, Math.Rectangle{0, 0, .leftPanelWidth, 0}, vertical: true)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with .recentPane = Wnd.create'Wnd(.filePanel)
        {
            .backgroundStyle = .Transparent
            .padding         = {0, 4, 0, 4}
        }

        with let recentHeader = Wnd.create'Wnd(.recentPane, Math.Rectangle{0, 0, 0, compactSize})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .margin          = {10, 0, 10, 0}
        }

        with .closeFilesButton = IconButton.create(recentHeader, .theme().icon(.WndClose, rowIconSize), Math.Rectangle{0, 0, compactSize, compactSize})
        {
            .dockStyle  = .Right
            .toolTip    = appStrings().ui_CloseFiles
            .sigPressed += func|window = me|(_)
            {
                window.setFilePanelVisible(false)
                catch window.saveState()
            }
        }

        with .recentClearButton = IconButton.create(recentHeader, .theme().icon(.RemoveAll, rowIconSize), Math.Rectangle{0, 0, compactSize, compactSize})
        {
            .dockStyle  = .Right
            .toolTip    = appStrings().ui_ClearHistory
            .sigPressed += func|window = me|(_) { window.confirmClearRecent() }
        }

        with .recentLabel = Label.create(recentHeader, appStrings().ui_Recent, Math.Rectangle{0, 0, 0, compactSize}, null, .SecondaryText)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with .recentList = createFileList(.recentPane, rowIconSize)
        {
            .sigSelectionChanged += func|window = me|(list)
            {
                window.openListSelection(list, window.recent.toSlice())
            }

            .sigRightClicked += func|window = me|(list, position)
            {
                window.showFileMenu(list,
                                    window.recent.toSlice(),
                                    list.listView.localToSurface(position))
            }
        }

        with .folderPane = Wnd.create'Wnd(.filePanel)
        {
            .backgroundStyle = .Transparent
            .padding         = {0, 4, 0, 4}
        }

        // The header carries the filter beside the folder name: the toggle changes what this
        // list holds, and the next/previous arrows walk the same list.
        with let folderHeader = Wnd.create'Wnd(.folderPane, Math.Rectangle{0, 0, 0, compactSize})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
            .margin          = {10, 0, 10, 0}
        }

        with .closeFoldersButton = IconButton.create(folderHeader, .theme().icon(.WndClose, rowIconSize), Math.Rectangle{0, 0, compactSize, compactSize})
        {
            .dockStyle  = .Right
            .toolTip    = appStrings().ui_CloseFiles
            .sigPressed += func|window = me|(_)
            {
                window.setFilePanelVisible(false)
                catch window.saveState()
            }
        }

        with .kindButton = IconButton.create(folderHeader, .theme().icon(.Filter, rowIconSize), Math.Rectangle{0, 0, compactSize, compactSize}, flags: .Toggle)
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_SameKind
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|window = me|(button) { window.setFolderSameKind(button.isChecked) }
        }

        with .folderHistoryButton = IconButton.create(folderHeader,
                                                      .theme().icon(.History, rowIconSize),
                                                      Math.Rectangle{0, 0, themeDropDownButtonWidth(.themeMetrics()), compactSize},
                                                      flags: .CenterContent)
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_FolderHistory
            .setArrowPosition(.RightDownward)
            .enable(false)
            .sigPressed += func|window = me|(_) { window.showFolderHistory() }
        }

        with .folderLabel = Label.create(folderHeader, appStrings().ui_Folder, Math.Rectangle{0, 0, 0, compactSize}, null, .SecondaryText | .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Left, .Center)
        }

        with .folderFilterBox = EditBox.create(.folderPane, "", Math.Rectangle{0, 0, 0, compactSize})
        {
            .dockStyle = .Top
            .margin    = {8, 4, 8, 4}
            .setIcon(.theme().icon(.Search, themeRowIconSize(.themeMetrics())))
            .setPlaceholder(appStrings().ui_FilterFiles)
            .updateFlags(.ClearButton)
            .sigTextChanged += func|window = me|(edit) { window.setFolderFilter(edit.text()) }
        }

        with .folderList = createFileList(.folderPane, rowIconSize)
        {
            .sigSelectionChanged += func|window = me|(list)
            {
                window.openListSelection(list, window.siblings.toSlice())
            }

            .sigRightClicked += func|window = me|(list, position)
            {
                window.showFileMenu(list,
                                    window.siblings.toSlice(),
                                    list.listView.localToSurface(position))
            }
        }

        with let recentItem = .filePanel.addPane(.recentPane, RecentHeight)
        {
            .minimumSize  = PaneMinSize
            .preserveSize = true
        }

        .filePanel.addPane(.folderPane).minimumSize = PaneMinSize
        with let panelItem = .mainSplitter.addPane(.filePanelHost, .leftPanelWidth + gutter)
        {
            .minimumSize  = PanelMinWidth + gutter
            .maximumSize  = PanelMaxWidth + gutter
            .preserveSize = true
        }

        .mainSplitter.setPaneVisible(0, .panelVisible)
    }

    // Builds the document with its home, the faint line of readings at its foot,
    // and the loading, search and drop overlays drawn above the active viewer.
    private mtd createDocumentPanel()
    {
        with .documentHost = Wnd.create'Wnd(.mainSplitter)
        {
            .backgroundStyle = .Transparent
        }

        with .readingLine = ViewerReadingLine.create(.documentHost)
        {
            .dockStyle = .Bottom
            .margin    = Math.Vector4{me.themeMetrics().floating_Inset, 0, me.themeMetrics().floating_Inset, 4}
            .hide()
        }

        with .documentPanel = Wnd.create'Wnd(.documentHost)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
        }

        .home = ViewerHome.create(.documentPanel, me)

        .loadingOverlay = ViewerLoadingOverlay.create(.documentPanel)
        .searchOverlay  = ViewerSearchOverlay.create(.documentPanel)
        .dropHighlight  = ViewerDropHighlight.create(.documentPanel)
        .mainSplitter.addPane(.documentHost).minimumSize = DocumentMinWidth
        with .sidePanelPlaceholder = Wnd.create'Wnd(.mainSplitter)
        {
            .backgroundStyle = .Transparent
            .hide()
        }

        let gutter        = .themeMetrics().floating_Inset
        with let sideItem = .mainSplitter.addPane(.sidePanelPlaceholder, RightPanelDefaultWidth + gutter)
        {
            .minimumSize  = RightPanelMinWidth + gutter
            .maximumSize  = RightPanelMaxWidth + gutter
            .preserveSize = true
        }

        .mainSplitter.setPaneVisible(2, false)
    }

    // Keeps the document below the strip floating over the top of the window, out of full screen,
    // and the panels beside it the floating inset away from the top as well, as the sheet stands.
    private mtd updateDocumentInsets()
    {
        let strip = .fullScreen ? 0 : .stripInset()
        let top   = Math.max(strip, .themeMetrics().floating_Inset)
        .documentHost.padding    = Math.Vector4{0, strip, 0, 0}
        .filePanelHost.padding.y = top
        if .currentSidePanelHost do
            .currentSidePanelHost.padding.y = top
    }

    private mtd hookChildEvents()
    {
        .mainSplitter.hookOnEvent = func|window = me|(_, evt)
        {
            if evt is ResizeEvent do
                window.layoutFloatingParts()
            return false
        }

        .hookOnChildEvent = func|window = me|(_, evt)
        {
            switch evt
            {
            case KeyEvent as key where window.routePlaybackKey(key):         return true
            case KeyEvent as key where window.routeSearchNavigationKey(key): return true
            case MouseEvent as mouse where mouse.kind == .Move or mouse.kind == .Enter: window.notePointer(mouse.surfacePos)
            case TaskEvent: window.retryRetirement()
            }

            return false
        }
    }
}
