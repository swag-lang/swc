impl ViewerWindow
{
    // Opens the shared appearance sheet and persists the reader's theme and language choices.
    private mtd createAppearanceChrome()
    {
        .appearanceButton = AppearanceButton.create(unwrap .surface, "scope.appearance", documentTheme: true)
        .appearanceButton.sigThemeChanged += func|window = me|(button)
        {
            window.themeIndex = cast(u32, button.appearanceTheme)
            window.layoutFileInfo()
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

    // Builds the shared search row. The host reserves its space above the document.
    private mtd createSearchBar()
    {
        let height = themeActionButtonSize(.themeMetrics())
        with .searchBar = FloatingPanel.create(me, id: "scope.search")
        {
            .padding = {x: SearchGroupSpacing, y: SearchGroupSpacing, z: SearchGroupSpacing, w: SearchGroupSpacing}
            .hide()
        }

        .searchGroup = Wnd.create'Wnd(.searchBar)
        .searchGroup.backgroundStyle = .Transparent
        with .searchBox = EditBox.create(.searchGroup, "", {0, 0, SearchFieldWidth, height}, flags: .ClearButton)
        {
            .setIcon(me.theme().icon(.Search, themeActionIconSize(me.themeMetrics())))
            .setPlaceholder(appStrings().ui_Search)
            .setValidator(func|window = me|(edit)->EditBoxCheckResult => window.validateSearchEdit(edit))
            .sigTextChanged += func|window = me|(_)
            {
                window.restartSearch()
            }

            .sigSubmitted += func|window = me|(_)
            {
                if window.isExploring() do
                    window.explorer!.focusContent()
                else do
                    window.findNext()
            }

            .sigCancelled += func|window = me|(_)
            {
                window.hideSearch()
            }

            .enable(false)
        }

        .searchNavigation = Wnd.create'Wnd(.searchGroup)
        .searchNavigation.backgroundStyle = .Transparent
        with .searchCountLabel = Label.create(.searchNavigation, "", {}, null, .SecondaryText)
        {
            .style.setFont(me.theme().createDefaultFontFs(12), .Regular)
            .setTextAlignment(.Center, .OpticalCenter)
        }

        with .searchPrevious = Viewer.createActionButton(.searchNavigation, .SearchPrevious)
        {
            .toolTip    = appStrings().ui_SearchPrevious
            .sigPressed += func|window = me|(_) { window.findPrevious() }
            .enable(false)
        }

        with .searchNext = Viewer.createActionButton(.searchNavigation, .SearchNext)
        {
            .toolTip    = appStrings().ui_SearchNext
            .sigPressed += func|window = me|(_) { window.findNext() }
            .enable(false)
        }

        with .searchOptionsButton = Viewer.createActionDropDown(.searchGroup, .MatchWholeWord)
        {
            .toolTip = appStrings().ui_SearchOptions
            .setArrowPosition(.RightDownward)
            .sigPressed += func|window = me|(_) { window.showSearchOptionsMenu() }
        }

        with .searchCloseButton = Viewer.createActionButton(.searchGroup, .WndClose)
        {
            .toolTip    = appStrings().ui_CloseSearch
            .sigPressed += func|window = me|(_) { window.hideSearch() }
        }
    }

    // Builds the floating bar the active viewer's commands stand in, at the foot of the document.
    private mtd createViewerBar()
    {
        // The viewer's commands stand on a mini-bar: its small corner and its tight padding.
        with .viewerBar = FloatingPanel.create(me, {0, 0, 0, BarHeight}, "scope.commands")
        {
            let pad = me.themeMetrics().miniBar_Padding
            .corner  = me.themeMetrics().miniBar_Corner
            .padding = Math.Vector4{x: pad * 2, y: pad, z: pad * 2, w: pad}
            .hide()
        }
    }

    // Builds the sheet of readings `I` opens, and the hint teaching the door while the window is
    // empty.
    private mtd createSheetAndHint()
    {
        .information = ViewerInformation.create(me, me)
        .infoSheet   = InfoSheet.create(me, "scope.information", closeButton: false)
        .infoSheet.setFillHeight(true)
        with .hintLine = HintLine.create(me, "scope.hint")
        {
            .addHint(Input.formatKeyShortcut(.Control, .Space), appStrings().ui_HintLens)
        }
    }

    // Builds the document with its home, the faint line of readings at its foot,
    // and the loading and search overlays drawn above the active viewer.
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
        with .outlinePanelPlaceholder = Wnd.create'Wnd(.mainSplitter)
        {
            .backgroundStyle = .Transparent
            .hide()
        }

        let gutter        = .themeMetrics().floating_Inset
        let leftWidth     = (.leftPanelWidth > 0 ? .leftPanelWidth : RightPanelDefaultWidth) + gutter
        with let outlineItem = .mainSplitter.addPane(.outlinePanelPlaceholder, leftWidth)
        {
            .minimumSize  = RightPanelMinWidth + gutter
            .maximumSize  = RightPanelMaxWidth + gutter
            .preserveSize = true
        }

        .mainSplitter.addPane(.documentHost).minimumSize = DocumentMinWidth
        with .sidePanelPlaceholder = Wnd.create'Wnd(.mainSplitter)
        {
            .backgroundStyle = .Transparent
            .hide()
        }

        with let sideItem = .mainSplitter.addPane(.sidePanelPlaceholder, RightPanelDefaultWidth + gutter)
        {
            .minimumSize  = RightPanelMinWidth + gutter
            .maximumSize  = RightPanelMaxWidth + gutter
            .preserveSize = true
        }

        .mainSplitter.setPaneVisible(LeftPanelIndex, false)
        .mainSplitter.setPaneVisible(RightPanelIndex, false)
    }

    // Keeps the document below the strip floating over the top of the window, out of full screen,
    // and the panels beside it the floating inset away from the top as well, as the sheet stands.
    mtd updateDocumentInsets()
    {
        let strip  = .fullScreen or .isEdgeToEdge() ? 0 : .stripInset()
        let top    = strip + .themeMetrics().floating_Inset
        let search = .searchBar != null and .searchBar.isLocallyVisible() ?
                     Math.max(.searchBar.position.height, themeActionButtonSize(.themeMetrics())) + .themeMetrics().floating_Inset : 0
        .documentHost.padding = Math.Vector4{0, strip + search, 0, 0}
        if .currentView is Markdown.View as markdown
        {
            // Let the page reach the chrome when both use the same reading appearance.
            if Viewers.MarkdownText.g_ViewerSettings.themeIndex == 0 or .appearanceButton.appearanceTheme == .Document
            {
                .documentHost.padding.y = 0
                markdown.padding.y      = strip + search
            }
            else
            {
                markdown.padding.y = 0
            }
        }

        if .viewerBar != null
        {
            let commands     = .currentCommands
            let keepCommands = not .fullScreen or (.infoSheet != null and .infoSheet.isLocallyVisible())
            .documentPanel.margin.w = commands and keepCommands ?
                                      commands.position.height + .viewerBar.padding.y + .viewerBar.padding.w +
                                      2 * .themeMetrics().miniBar_Distance : 0
        }

        if .currentSidePanelHost do
            .currentSidePanelHost.padding.y = top
    }

    private mtd hookChildEvents()
    {
        // The splitter's resize precedes its panes. Align overlays only once the document has
        // received its new bounds, so a narrower window cannot leave search outside the work.
        .documentPanel.hookOnEvent = func|window = me|(_, evt)
        {
            if evt is ResizeEvent do
                window.layoutFloatingParts()
            return false
        }

        .hookOnChildEvent = func|window = me|(_, evt)
        {
            switch evt
            {
            case KeyEvent as key where key.kind == .Pressed and key.key == .Space and key.modifiers == .Control:
                window.sendCommandEvent(ViewerCommands.Lens)
                return true

            case KeyEvent as key where window.routePlaybackKey(key):
                return true

            case KeyEvent as key where window.routeSearchNavigationKey(key):
                return true

            case MouseEvent as mouse where mouse.kind == .Move or mouse.kind == .Enter:
                window.notePointer(mouse.surfacePos)

            case TaskEvent:
                window.retryRetirement()
            }

            return false
        }
    }
}
