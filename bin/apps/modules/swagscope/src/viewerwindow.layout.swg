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

        .mainSplitter.setPaneVisible(1, false)
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
            // The page paints under the chrome; only its scroll viewport keeps clear of it.
            .documentHost.padding.y = 0
            markdown.padding.y      = strip + search
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
