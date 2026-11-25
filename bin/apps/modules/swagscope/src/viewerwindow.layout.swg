impl ViewerWindow
{
    // Opens the shared appearance sheet and persists the reader's theme and language choices.
    private mtd createAppearanceChrome()
    {
        .appearanceButton = AppearanceButton.create(unwrap .surface, "scope.appearance", documentTheme: true)
        .appearanceButton.sigThemeChanged += func|window = me|(button)
        {
            window.themeIndex = cast(u32, button.appearanceTheme)
            window.captionDocument().layoutFileInfo()
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

        with .searchCancelButton = Viewer.createActionButton(.searchNavigation, .Stop)
        {
            .toolTip    = appStrings().ui_SearchCancel
            .sigPressed += func|window = me|(_) { window.cancelSearch() }
            .hide()
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

        .createCellCaption()
    }

    private mtd showViewerOverlay(panel: *FloatingPanel, show: bool, animate = true)
    {
        if not animate
        {
            panel.show(show)
            return
        }
        if panel.isLocallyVisible() == show do
            return

        let metrics  = .themeMetrics()
        let duration = Time.Duration.fromSeconds(metrics.motion_PanelSeconds)
        if show
        {
            let travel = metrics.motion_AnchorTravel
            discard .app().animator.arrive(panel, {0, travel}, duration, .EaseInOut)
        }
        else do
            discard .app().animator.leave(panel, duration, .EaseInOut)
    }

    mtd hasSoloCaption()->bool => .workspace and .workspace.scenes.count == 1 and .workspace.tabStripHeight() == 0 and
                                 .workspace.documentCount() == 1 and not .workspace.isTiled() and
                                 .isWorkspaceActive() and not .fullScreen

    mtd hasCellFooter()->bool => .workspace and .workspace.vacancy != me and (.hasSoloCaption() or .workspace.usesCellCaptions()) and
                                 (not .fullScreen or .workspace.isTiled()) and
                                 (.isExploring() or not .currentFile.isEmpty() or not .pendingFile.isEmpty())

    mtd layoutCellCaption()
    {
        if .cellCaption == null do
            return
        let showClose = .hasCellFooter()
        let exploring = .isExploring()
        let path: string = exploring ? .explorer!.requested : (.pendingFile.isEmpty() ? .currentFile : .pendingFile)
        let name = Path.fileName(path) orelse path
        let close = .readingLine.close
        close.show(showClose)
        if showClose
        {
            let action   = .hasSoloCaption() and not exploring ? appStrings().ui_CloseFile : appStrings().scene_CloseView
            let shortcut = .acceptsViewCommands() and .isWorkspaceActive() ? .keyShortcutName(ViewerCommands.Close) : String{}
            close.toolTip = viewCloseHint(name, action, shortcut)
        }

        let caption = .cellCaption
        if not showClose or exploring
        {
            caption.hide()
            .readingLine.computeLayout()
            return
        }

        let footer = .workspace!.usesCellCaptions()
        let parent = footer ? cast(*Wnd, .readingLine) : cast(*Wnd, me)
        if caption.parent != parent do
            caption.setParent(parent)
        let label = footer ? .workspace.mediaCaption(me, name) : String.from(name)
        caption.setFile(path, label)
        caption.show()
        .readingLine.computeLayout()
        if footer do
            return

        let frame = .surface!.wnd
        let room = frame.captionContentRect()
        let width = caption.widthFor(room.width)
        let x = Math.clamp(frame.clientRect().horzCenter() - width * 0.5, room.x, Math.max(room.x, room.right() - width))
        let origin = .surfaceToLocal(frame.localToSurface(Math.Point{x, room.vertCenter()}))
        caption.place(origin.x, origin.y, width)
    }

    private mtd createCellCaption()
    {
        .cellCaption = ViewerFileCaption.create(me)
        .readingLine.close.sigPressed += func|document = me|(_) { document.workspace?.closeDocument(document) }
        .readingLine.caption = .cellCaption
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

        with .readingLine = ViewerReadingLine.create(me)
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

        let gutter           = .themeMetrics().floating_Inset
        let leftWidth        = (.leftPanelWidth > 0 ? .leftPanelWidth : RightPanelDefaultWidth) + gutter
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

    // A splitter inside a cell shares the available width between the document and its optional side panel.
    func fitDocumentPanes(splitter: *SplitterCtrl, width: f32)
    {
        if splitter.items.count <= RightPanelIndex do
            return
        let metrics = splitter.themeMetrics()
        let panel   = RightPanelMinWidth + metrics.floating_Inset
        let room    = Math.max(0, width - metrics.splitView_BarSize)
        let scale   = Math.min(1.0, room / (DocumentMinWidth + panel))
        splitter.items[LeftPanelIndex]!.minimumSize     = Math.floor(panel * scale)
        splitter.items[RightPanelIndex]!.minimumSize    = Math.floor(panel * scale)
        splitter.items[DocumentPanelIndex]!.minimumSize = Math.floor(DocumentMinWidth * scale)
    }

    // Keeps the document below the strip floating over the top of the window, out of full screen,
    // and the panels beside it the floating inset away from the top as well, as the sheet stands.
    mtd updateDocumentInsets()
    {
        let metrics = .themeMetrics()
        let inset = .hasCellFooter() ? Math.clamp(.clientRect().width / 16, metrics.miniBar_Padding, metrics.floating_Inset) : metrics.floating_Inset
        .readingLine.margin.x = inset
        .readingLine.margin.z = inset
        let compact    = .compactVideoCell()
        let tiledVideo = .currentView is Viewers.Film.Panel and (.workspace?.isTiled() orelse false)
        let strip = .fullScreen or .isEdgeToEdge() ? 0.0 : .stripInset()
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
            let commands     = visibleViewerCommands(.currentCommands)
            if .currentView is Viewers.Film.Panel as film where film.bottomVeil.compact != compact
            {
                film.bottomVeil.compact = compact
                let height = compact ? themeActionButtonSize(.themeMetrics()) : Viewers.Film.BottomHeight
                film.commands.resize(film.commands.position.width, height)
            }

            if .currentView is Viewers.Sound.Panel as sound
            {
                let bar = Viewers.Sound.TransportHeight + .viewerBar.padding.y + .viewerBar.padding.w
                sound.setCompactTransport((.workspace?.isTiled() orelse false) and .clientRect().height < 3 * bar)
            }

            // The dedicated comparison paints its own canvas above the two transport bars.
            let comparison = tiledVideo and (.workspace?.wantsComparisonSheet() orelse false) and
                             (.workspace?.isMediaScene() orelse false) and not .fullScreen
            let clearance  = comparison ? .themeMetrics().floating_Inset : .themeMetrics().miniBar_Distance
            .documentPanel.margin.w = commands and (comparison or not .overlaysViewerBar()) ?
                                      commands.position.height + .viewerBar.padding.y + .viewerBar.padding.w +
                                      2 * clearance : 0
        }

        if .currentSidePanelHost is ViewerSidePanelHost as side do
            side.placeBelowStrip(strip)
    }

    mtd compactVideoCell()->bool
    {
        return .currentView is Viewers.Film.Panel and
               (.workspace?.isTiled() orelse false) and
               .clientRect().height < 3 * (Viewers.Film.BottomHeight + 2 * .viewerBar.padding.y)
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
