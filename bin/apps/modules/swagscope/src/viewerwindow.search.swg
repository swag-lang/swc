impl ViewerWindow
{
    mtd findNext()
    {
        .navigateSearch(1)
    }

    mtd findPrevious()
    {
        .navigateSearch(-1)
    }

    mtd lineComparison()->*SceneComparison?
    {
        let workspace = .workspace
        let compare = workspace?.comparison
        if workspace and compare and compare.isLocallyVisible() and compare.hasLineNumbers() and workspace.activeDocument() == me do
            return compare
        return null
    }

    private mtd searchOptions()->Viewer.SearchOptions =>
    {
        matchCase: .searchMatchCaseOption,
        wholeWord: .searchWholeWordOption,
        regularExpression: .searchRegexOption}

    // Pops up the search options: search or filter mode when the active viewer can filter, then
    // match case, whole word and regular expression. The same choices are entries of the lens;
    // [[ViewerWindow.setSearchOption]] applies either.
    private mtd showSearchOptionsMenu()
    {
        let chosen = .createSearchOptionsMenu().doModal(.searchOptionsButton, autoDestroy: true) orelse ""
        if chosen.count do
            .setSearchOption(chosen)
    }

    // Builds the current search choices. Kept module-visible so the menu's checked state can be
    // verified without entering a modal loop in the headless test host.
    internal mtd createSearchOptionsMenu()->*MenuCtrl
    {
        let texts     = appStrings()
        let menu      = MenuCtrl.createPopup(me, owner: me)
        let canFilter = not .lineComparison() and .activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].filterSearch != null
        if canFilter
        {
            menu.addRadioItem(texts.ui_SearchMode, ViewerCommands.SearchMode, checked: not .searchFilterMode)
            menu.addRadioItem(texts.ui_FilterMode, ViewerCommands.FilterMode, checked: .searchFilterMode)
            menu.addSeparator()
        }

        menu.addItem(texts.ui_SearchMatchCase, ViewerCommands.MatchCase, checked: .searchMatchCaseOption)
        menu.addItem(texts.ui_SearchWholeWord, ViewerCommands.WholeWord, checked: .searchWholeWordOption)
        menu.addItem(texts.ui_SearchRegularExpression, ViewerCommands.RegularExpression, checked: .searchRegexOption)
        return menu
    }

    // Validates the query in the search box: a viewer with its own query syntax judges it,
    // otherwise the text options decide whether it is a valid pattern. An empty query is valid.
    private mtd validateSearchEdit(edit: *EditBox)->EditBoxCheckResult
    {
        if not (edit.text()).count do
            return .Valid
        if not .lineComparison() and .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.view and instance.prepareSearch
            {
                var plan: Viewer.SearchPlan
                return instance.prepareSearch(edit.text(), &plan)
            }
        }

        return Viewer.patternIsValid(edit.text(), .searchOptions()) ? .Valid : .InvalidVisible
    }

    // Applies the active viewer's search wording and capabilities to the search group: placeholder,
    // tooltip, options button and field width. Leaves filter mode when the viewer cannot filter.
    private mtd refreshSearchPresentation()
    {
        if .isExploring()
        {
            .searchToolTip = appStrings().ui_FilterFiles
            .searchBox.setPlaceholder(.searchToolTip)
            .searchBox.toolTip = .searchToolTip
            .searchBox.setIcon(.theme().icon(.Search, themeActionIconSize(.themeMetrics())))
            .searchOptionsButton.show()
            .searchOptionsButton.setIcon(.theme().icon(.MatchWholeWord, themeActionIconSize(.themeMetrics())))
            .searchOptionsButton.toolTip = appStrings().ui_SearchOptions
            .searchNavigation.hide()
            .searchBox.resize(SearchFieldWidth, 36)
            .searchGroup.applyLayout()
            .layoutSearchBar()
            return
        }

        .searchNavigation.show()
        var presentation: Viewer.SearchPresentation
        presentation.placeholder = appStrings().ui_Search
        if not .lineComparison() and .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.view and instance.describeSearch do
                instance.describeSearch(&presentation)
        }

        if not presentation.canFilter do
            .searchFilterMode = false

        if .searchFilterMode
        {
            .searchToolTip = #move presentation.filterToolTip
            .searchBox.setPlaceholder(presentation.filterPlaceholder)
        }
        else
        {
            .searchToolTip = #move presentation.toolTip
            .searchBox.setPlaceholder(presentation.placeholder)
        }

        .searchBox.toolTip = .searchToolTip
        .searchOptionsButton.show(presentation.useTextOptions or presentation.canFilter)
        if presentation.canFilter
        {
            .searchOptionsButton.setIcon(.theme().icon(.searchFilterMode ? .Filter : .Search, themeActionIconSize(.themeMetrics())))
            .searchBox.setIcon({})
        }
        else
        {
            // The gear belongs to the options of the viewer, in its own bar; the matching rules
            // of the search take a glyph of their own.
            .searchOptionsButton.setIcon(.theme().icon(.MatchWholeWord, themeActionIconSize(.themeMetrics())))
            .searchBox.setIcon(.theme().icon(.Search, themeActionIconSize(.themeMetrics())))
        }

        var searchToolTip = appStrings().ui_SearchOptions
        if presentation.canFilter do
            searchToolTip = .searchFilterMode ? appStrings().ui_FilterMode : appStrings().ui_SearchMode
        .searchOptionsButton.toolTip = searchToolTip

        // With no options button, let the enlarged field meet navigation directly. Keeping the
        // usual inter-group gap as well would leave an empty button-sized visual group.
        let hasMenu = presentation.useTextOptions or presentation.canFilter
        .searchBox.resize(hasMenu ? SearchFieldWidth : SearchNoOptionsFieldWidth, 36)
        discard .searchBox.revalidate()
        .searchGroup.applyLayout()
        .layoutSearchBar()
    }

    // Searches the active viewer again for the text of the search box. Filter mode hands the query
    // to the viewer's filter; otherwise matches come from the viewer or a scan of the file, and
    // `selectLast` selects the last one instead of the first. `keepPosition` rebuilds results
    // for a restored document without scrolling away from its saved viewport.
    mtd restartSearch(selectLast = false, keepPosition = false)
    {
        if .isExploring()
        {
            // The Explorer stays visible until the file viewer replaces it. The shared field is
            // cleared for that file, but its empty text must not erase the folder's filter.
            if .explorerTransition do
                return
            if .explorer!.filter.text() == .searchBox.text() do
                .explorer.fill()
            else do
                .explorer.filter.setText(.searchBox.text())
            .refreshSearchReadout()
            return
        }

        if let comparison = .lineComparison()
        {
            .forgetSearch()
            .searchComparison   = comparison
            .searchQuery        = .searchBox.text()
            .searchSelectLast   = selectLast
            .searchKeepPosition = keepPosition
            .searchError.clear()
            if not .searchQuery.isEmpty() and .searchBox.isValid() do
                comparison.collectMatches(.searchQuery, .searchOptions(), &.searchMatches)
            .finishSearch()
            comparison.invalidate()
            return
        }

        // Capture viewer-owned query context before clearing the previous result presentation.
        // A hexadecimal selection is also the scope for a `selection:` query, and clearing the
        // old search mark may collapse that selection.
        var preparedPlan: Viewer.SearchPlan
        var preparedState = EditBoxCheckResult.Incomplete
        var hasPreparedPlan: bool
        let requestedQuery = .searchBox.text()
        if .searchBox.isEnabled() and not .currentFile.isEmpty() and
           .activeChoiceIndex < .instances.count and not .searchFilterMode and requestedQuery.count
        {
            let candidate = &.instances[.activeChoiceIndex]
            if candidate.prepareSearch and candidate.view and not candidate.collectMatches
            {
                preparedState = candidate.prepareSearch(requestedQuery, &preparedPlan)
                hasPreparedPlan = true
            }
        }

        .forgetSearch()
        .searchSelectLast   = selectLast
        .searchKeepPosition = keepPosition
        .searchQuery      = requestedQuery
        .searchSpan       = Math.max(.searchQuery.length, 1)
        .searchError.clear()
        .refreshSearchReadout()

        if not .searchBox.isEnabled() or
           .currentFile.isEmpty() or
           .activeChoiceIndex >= .instances.count do
            return

        let instance = &.instances[.activeChoiceIndex]
        if .searchFilterMode and instance.filterSearch and instance.view
        {
            instance.filterSearch(.searchQuery, .searchOptions())
            .searchComplete = true
            .refreshSearchReadout()
            return
        }

        // Leaving filter mode restores the complete report before the same field starts finding
        // occurrences in it. An empty filter is also delivered above, so clearing the field is an
        // immediate return to the unfiltered tree.
        if instance.filterSearch and instance.view do
            instance.filterSearch("", .searchOptions())

        if .searchQuery.isEmpty() do
            return

        if not .searchBox.isValid() and not (instance.prepareSearch and instance.view)
        {
            .searchComplete = true
            .refreshSearchReadout()
            return
        }

        if instance.collectMatches and instance.view
        {
            .searchProgress = 0
            if .collectViewerMatches() do
                .finishSearch()
            else do
                .continueViewerSearch()
            return
        }

        if instance.prepareSearch and instance.view
        {
            var plan = preparedPlan
            let state = hasPreparedPlan ? preparedState : instance.prepareSearch(.searchQuery, &plan)
            if state != .Valid
            {
                .searchComplete = true
                if state == .InvalidVisible do
                    .searchError = #move plan.error
                .refreshSearchReadout()
                return
            }

            .searchSpan = Math.max(plan.span, 1)
            .searchByteRange = plan.byteRange
        }

        if instance.useSearchMatches and instance.view do
            instance.useSearchMatches(&.searchMatches)

        .beginSearch()
    }

    // Asks the active viewer for the matches it can answer for now, and reports whether it has
    // answered for the whole document.
    //
    // A viewer that extracts its text in the background answers a page at a time. Its first match
    // is revealed as soon as it exists rather than once the last page has been read, and the rest
    // of the document keeps being read behind it.
    private mtd collectViewerMatches()->bool
    {
        let instance = &.instances[.activeChoiceIndex]
        var options  = .searchOptions()
        var expression: Parser.RegExp
        if options.regularExpression
        {
            catch expression.compile(.searchQuery, ignoreCase: not options.matchCase) { return true }
            options.expression = &expression
        }

        let complete = instance.collectMatches!(.searchQuery, options, &.searchProgress, &.searchMatches)
        if not complete and
           not .searchSelectLast and
           not .searchKeepPosition and
           .searchIndex >= .searchMatches.count and
           not .searchMatches.isEmpty()
        {
            .searchIndex = 0
            .revealCurrentSearchMatch()
        }

        return complete
    }

    // Comes back to a viewer still reading its document from the search timer.
    private mtd continueViewerSearch()
    {
        .searchTimer = .addTimer(Viewer.BackgroundPollInterval)
        .refreshSearchReadout()
    }

    // Moves to the next or previous match, wrapping around. A query edited since the last search
    // restarts it first, landing on the last match when moving backward.
    private mtd navigateSearch(direction: s32)
    {
        if not .searchBox.isEnabled() or not (.searchBox.text()).count do
            return
        if .searchQuery != .searchBox.text()
        {
            .restartSearch(selectLast: direction < 0)
            return
        }

        if .searchMatches.isEmpty() do
            return

        if direction < 0 do
            .searchIndex = .searchIndex ? .searchIndex - 1 : .searchMatches.count - 1
        else do
            .searchIndex = (.searchIndex + 1) % .searchMatches.count
        .revealCurrentSearchMatch()
    }

    // Shows the search state in the count label, its tooltip and the navigation buttons: an error,
    // an invalid pattern, a running count, no match, or the current position.
    private mtd refreshSearchReadout()
    {
        defer .layoutSearchBar()
        if .isExploring()
        {
            .searchCountLabel.setText("")
            .searchCountLabel.toolTip = ""
            .searchPrevious.enable(false)
            .searchNext.enable(false)
            .searchCancelButton.show(false)
            .searchCancelButton.enable(false)
            .searchBox.toolTip = .searchToolTip
            return
        }

        if .searchFilterMode
        {
            .searchCountLabel.setText("")
            .searchCountLabel.toolTip = ""
            .searchPrevious.enable(false)
            .searchNext.enable(false)
            .searchCancelButton.show(false)
            .searchCancelButton.enable(false)
            .searchBox.toolTip = .searchToolTip
            return
        }

        if .searchQuery.isEmpty()
        {
            .searchCountLabel.setText("")
            .searchCountLabel.toolTip = ""
        }
        elif not .searchError.isEmpty()
        {
            .searchCountLabel.setText("!")
            .searchCountLabel.toolTip = .searchError
        }
        elif not .searchBox.isValid()
        {
            .searchCountLabel.setText("0/0")
            .searchCountLabel.toolTip = appStrings().ui_SearchInvalidRegularExpression
        }
        elif not .searchComplete
        {
            var current = Format.toString("…")
            if .searchIndex < .searchMatches.count do
                current = Format.toString("%", .searchIndex + 1)
            var total = Format.toString("%", .searchMatches.count)
            if .searchMatchesCapped do
                total += "+"
            var status = Format.toString("%/%…", current, total)
            .searchCountLabel.toolTip = appStrings().ui_Searching
            if .searchStream.isOpen()
            {
                let processed = StrConv.toDisplaySize(.searchProcessed)
                status = Format.toString("% · %", status, processed)
                .searchCountLabel.toolTip = Format.toString(appStrings().ui_SearchProgress,
                                                            processed,
                                                            StrConv.toDisplaySize(.searchTotalBytes))
            }

            if .searchMatchesCapped do
                .searchCountLabel.toolTip += Format.toString(" · %",
                                                             Format.toString(appStrings().ui_SearchResultsLimited, SearchMatchLimit))
            .searchCountLabel.setText(status)
        }
        elif .searchMatches.isEmpty()
        {
            .searchCountLabel.setText("0/0")
            .searchCountLabel.toolTip = .searchCancelled ?
                                        Format.toString(appStrings().ui_SearchCancelled, StrConv.toDisplaySize(.searchProcessed)) :
                                        appStrings().ui_NoMatch
            if not .searchCancelled and .activeChoiceIndex < .instances.count
            {
                let instance = &.instances[.activeChoiceIndex]
                if instance.view and instance.explainSearch
                {
                    let reason = instance.explainSearch(.searchQuery)
                    if not reason.isEmpty() do
                        .searchCountLabel.toolTip = Format.toString("% · %", appStrings().ui_NoMatch, reason)
                }
            }
        }
        else
        {
            var total = Format.toString("%", .searchMatches.count)
            if .searchMatchesCapped do
                total += "+"
            .searchCountLabel.setText(Format.toString("%/%", .searchIndex + 1, total))
            .searchCountLabel.toolTip = .searchCountLabel.text()
            if .searchMatchesCapped do
                .searchCountLabel.toolTip = Format.toString(appStrings().ui_SearchResultsLimited, SearchMatchLimit)
            if .searchCancelled
            {
                .searchCountLabel.toolTip = Format.toString(appStrings().ui_SearchCancelled,
                                                            StrConv.toDisplaySize(.searchProcessed))
                if .searchMatchesCapped do
                    .searchCountLabel.toolTip += Format.toString(" · %",
                                                                 Format.toString(appStrings().ui_SearchResultsLimited, SearchMatchLimit))
            }

            // A count over a document some of which could not be read says what it leaves out.
            if .activeChoiceIndex < .instances.count
            {
                let instance = &.instances[.activeChoiceIndex]
                if instance.view and instance.explainSearch
                {
                    let reason = instance.explainSearch(.searchQuery)
                    if not reason.isEmpty()
                    {
                        // Mark a count whose search could not cover the whole document. The
                        // tooltip names the missing pages or unreadable text.
                        .searchCountLabel.setText(Format.toString("%*", .searchCountLabel.text()))
                        .searchCountLabel.toolTip = Format.toString("% · %", .searchCountLabel.text(), reason)
                    }
                }
            }
        }

        let canNavigate = not .searchMatches.isEmpty()
        .searchPrevious.enable(canNavigate)
        .searchNext.enable(canNavigate)
        let canCancel = .searchStream.isOpen() and not .isExploring()
        .searchCancelButton.show(canCancel)
        .searchCancelButton.enable(canCancel)
        .searchBox.toolTip = .searchError.isEmpty() ? .searchToolTip.toString() : .searchError.toString()
    }

    // Scrolls the active viewer to the current match and refreshes the readout and highlight, leaving
    // the keyboard in the search box when the reveal started there.
    private mtd revealCurrentSearchMatch()
    {
        if .searchIndex >= .searchMatches.count do
            return
        if let comparison = .searchComparison
        {
            if comparison == .lineComparison()
            {
                comparison.revealLineRow(.searchMatches[.searchIndex].major)
                .refreshSearchReadout()
            }

            return
        }

        if .activeChoiceIndex >= .instances.count do
            return
        let instance = &.instances[.activeChoiceIndex]
        if not instance.revealMatch or not instance.view do
            return

        // Revealing may legitimately focus a document when invoked outside the search bar. Live
        // typing is different: the viewer scrolls and selects behind the field, while the caret
        // stays in the query so the next letter extends it instead of going into the document.
        let preserveSearchFocus = .searchBox.hasFocus()
        defer if preserveSearchFocus do
            .searchBox.setFocus()

        let match = .searchMatches[.searchIndex]
        if not instance.revealMatch(match, .searchQuery) do
            return
        .searchMatch = match.offset
        .refreshSearchReadout()
        .refreshSearchHighlight()
    }

    // Places the highlight over the current match, clipped to the viewer, and keeps polling its bounds
    // on a timer while it stays current. Hides the highlight when the viewer cannot locate the match.
    private mtd refreshSearchHighlight()
    {
        if .searchIndex >= .searchMatches.count or .activeChoiceIndex >= .instances.count
        {
            .searchOverlay.hide()
            return
        }

        let instance = &.instances[.activeChoiceIndex]
        if not instance.view or not instance.searchBounds
        {
            .searchOverlay.hide()
            return
        }

        var bounds: Math.Rectangle
        if instance.searchBounds(.searchMatches[.searchIndex], &bounds)
        {
            let viewport = instance.view.surfaceRect()
            bounds.intersect(viewport)
            if not bounds.isEmpty() do
                .searchOverlay.showMatch(bounds)
            else do
                .searchOverlay.hide()
        }
        else
        {
            .searchOverlay.hide()
        }

        // A streamed document can materialize the result after revealMatch returns, and any
        // viewer can still adjust its scroll or layout. Follow the geometry for as long as this
        // occurrence is current rather than freezing an overlay at yesterday's coordinates.
        if not .searchBoundsTimer do
            .searchBoundsTimer = .addTimer(SearchBoundsPoll)
    }

    private mtd finishSearch()
    {
        .stopSearch(clearPresentation: false)
        .searchComplete = true
        if .searchSelectLast and not .searchMatches.isEmpty()
        {
            .searchIndex = .searchMatches.count - 1
        }
        elif .searchIndex >= .searchMatches.count and not .searchMatches.isEmpty()
        {
            .searchIndex = 0
        }

        if not .searchKeepPosition and not .searchMatches.isEmpty() do
            .revealCurrentSearchMatch()

        .refreshSearchReadout()
    }

    // Stops the current file scan immediately while preserving matches already found.
    mtd cancelSearch()
    {
        if not .searchStream.isOpen() do
            return
        .searchCancelled = true
        .finishSearch()
    }

    // Opens the search strip above the document and gives it the keyboard.
    mtd showSearch()
    {
        if not .searchBox.isEnabled() do
            return
        if .isExploring()
        {
            .layoutSearchBar()
            .searchBox.setFocus()
            .searchBox.selectAll()
            return
        }

        .searchShown = true
        .searchBar.show()
        if .searchComparison != .lineComparison() do
            .updateSearchAvailability()
        .updateDocumentInsets()
        .documentHost.applyLayout()
        .layoutFloatingParts()
        .explorer?.layoutTools()
        .searchBox.setFocus()
        .searchBox.selectAll()
    }

    // Puts the find bar away and gives the keyboard back to the document. The query stays: the
    // next and previous matches still answer their keys, and the bar comes back holding it.
    mtd hideSearch()
    {
        if .isExploring()
        {
            .explorer!.focusContent()
            return
        }

        .searchShown = false
        .searchBar.hide()
        .updateDocumentInsets()
        .documentHost.applyLayout()
        .layoutFloatingParts()
        .viewerFocusTarget()?.setFocus()
    }

    // Keeps document navigation available while the search field owns the keyboard. Page keys
    // also work from the rest of the action bar; when focus is already inside the viewer the
    // forwarding helper declines and the original event follows its normal path.
    mtd routeSearchNavigationKey(evt: *KeyEvent)->bool
    {
        if .forwardingViewerKey or evt.kind != .Pressed do
            return false
        let focus     = .focusedWindow()
        let searching = .searchGroup.isVisible() and focus and .searchGroup.isOwnerOf(focus)
        if searching and evt.key == .Escape
        {
            .hideSearch()
            return true
        }

        if searching and evt.key == .Return and evt.modifiers == .Shift
        {
            .findPrevious()
            return true
        }

        if Viewer.pageKeyDirection(evt) do
            return .forwardKeyToViewer(evt, takeFocus: false)
        if .searchIndex >= .searchMatches.count do
            return false

        let pageKey         = evt.modifiers == .None and (evt.key == .PageUp or evt.key == .PageDown)
        let focused         = .focusedWindow()
        let inSearchField   = focused and (focused == .searchBox or .searchBox.isOwnerOf(focused))
        let fieldNavigation = inSearchField and
                              ((evt.modifiers == .None and (evt.key == .Up or evt.key == .Down)) or
                               (evt.modifiers == .Control and (evt.key == .Home or evt.key == .End)))
        if not pageKey and not fieldNavigation do
            return false

        return .forwardKeyToViewer(evt, takeFocus: false)
    }

    // Offers the find bar only while the active viewer can reveal matches, keeps it on screen
    // while the reader asked for it, and restarts the search for the new viewer. An open lens asks
    // the new viewer for its rows as well.
    mtd updateSearchAvailability()
    {
        let active         = .activeChoiceIndex < .instances.count
        let available      = .isExploring() or .lineComparison() != null or (active and .instances[.activeChoiceIndex].revealMatch != null)
        let focused        = .focusedWindow()
        let searchHadFocus = focused and (focused == .searchGroup or .searchGroup.isOwnerOf(focused))

        .refreshSearchPresentation()
        .searchBox.enable(available)
        .searchOptionsButton.enable(available)
        .searchBar.show(available and .searchShown and not .isExploring())
        .updateDocumentInsets()
        .documentHost.applyLayout()
        .currentActions?.show()
        .layoutSearchBar()
        .restartSearch()
        if not available and searchHadFocus do
            .viewerFocusTarget()?.setFocus()

        // The rows a viewer gave the lens run on that viewer, which a failure, a reload or another
        // file may have destroyed while the lens stayed open.
        if .lens.isOpen() do
            .lens.refresh()
    }

    // Cancels the search in progress and hides its highlight; `clearPresentation` also clears the
    // matches the viewer highlights.
    mtd stopSearch(clearPresentation = true)
    {
        .stopTimer(&.searchTimer)

        .searchStream.close()
        .searchCarry.clear()
        if clearPresentation
        {
            .searchComparison?.invalidate()
            .searchComparison = null
        }

        if clearPresentation and .activeChoiceIndex < .instances.count
        {
            let instance = &.instances[.activeChoiceIndex]
            if instance.view and instance.useSearchMatches do
                instance.useSearchMatches(null)
            if instance.view and instance.clearSearch do
                instance.clearSearch()
        }

        .stopTimer(&.searchBoundsTimer)

        .searchOverlay.hide()
    }

    // Stops the search and forgets its query, its matches, and the match it was on.
    mtd forgetSearch()
    {
        .stopSearch()
        .searchQuery.clear()
        .searchMatches.clear()
        .searchIndex         = Swag.U64.Max
        .searchMatch         = Swag.U64.Max
        .searchComplete      = false
        .searchTotalBytes    = 0
        .searchMatchesCapped = false
        .searchCancelled     = false
        .searchByteRange     = {}
        .searchBytesRead     = 0
    }

    mtd beginSearch()
    {
        .searchMatchesCapped = false
        .searchCancelled     = false
        .searchStream        = catch File.openReadLive(.currentFile)
        {
            if .searchByteRange.length > 0 do
                .searchError = appStrings().ui_SearchRangeUnavailable
            .finishSearch()
            return
        }

        let decoder = .instances[.activeChoiceIndex].fileEncoding
        .searchEncoding = decoder ? decoder() : .Utf8
        .searchTotalBytes = 0
        catch { .searchTotalBytes = try .searchStream.size() }

        .searchBytesRead = 0
        .searchCarryBase = 0
        if .searchByteRange.length > 0
        {
            let byteRange = .searchByteRange
            if .searchTotalBytes < byteRange.offset or byteRange.length > .searchTotalBytes - byteRange.offset
            {
                .searchError = appStrings().ui_SearchRangeUnavailable
                .finishSearch()
                return
            }
            catch .searchStream.seek(.Begin, byteRange.offset)
            {
                .searchError = appStrings().ui_SearchRangeUnavailable
                .finishSearch()
                return
            }
            .searchTotalBytes = byteRange.length
            .searchCarryBase = byteRange.offset
        }
        .searchProcessed = 0
        .searchCarry.clear()
        .searchTimer = .addTimer(1'ms)
        .refreshSearchReadout()
    }

    // Advances the incremental search by one timer tick, through the viewer's collector or one
    // chunk of the file. Matches near a chunk's end wait for the next chunk, so a match crossing
    // the boundary is found once and whole.
    mtd searchStep()
    {
        if .activeChoiceIndex < .instances.count and
           .instances[.activeChoiceIndex].collectMatches and
           .instances[.activeChoiceIndex].view
        {
            if .collectViewerMatches() do
                .finishSearch()
            else do
                .continueViewerSearch()
            return
        }

        if not .searchStream.isOpen() do
            return

        let rangeOrigin = .searchByteRange.length > 0 ? .searchByteRange.offset : 0
        let rangeRemaining = .searchByteRange.length > 0 ? .searchTotalBytes - .searchBytesRead : SearchChunkSize
        let requested = Math.min(SearchChunkSize, rangeRemaining)
        var bytes: Array'u8
        bytes.resize(requested)
        let count = catch .searchStream.read(bytes.toSlice())
        {
            if .searchByteRange.length > 0 do
                .searchError = appStrings().ui_SearchRangeUnavailable
            .finishSearch()
            return
        }

        .searchBytesRead += count
        bytes.resize(count)
        .searchCarry += cast(string, bytes.toSlice())
        let eof      = count == 0 or (.searchByteRange.length > 0 and .searchBytesRead == .searchTotalBytes)
        if .searchByteRange.length > 0 and count == 0 and .searchBytesRead < .searchTotalBytes
        {
            .searchError = appStrings().ui_SearchRangeUnavailable
            .finishSearch()
            return
        }
        let instance = &.instances[.activeChoiceIndex]

        // A regular expression may span an arbitrary number of chunks, and ^/$ refer to the
        // document rather than to an implementation buffer. Keep reading incrementally so the
        // interface remains responsive, then evaluate once against the complete source.
        if .searchRegexOption and not instance.collectFileMatches and not eof
        {
            .searchTimer = .addTimer(1'ms)
            return
        }

        let unit = Text.unitSize(.searchEncoding)
        let deferSize = (.searchSpan + SearchCarryMargin) * unit
        var stableEnd = 0'u64
        if eof do
            stableEnd = .searchCarry.length
        elif .searchCarry.length > deferSize do
            stableEnd = .searchCarry.length - deferSize

        var candidates: Array'Viewer.SearchMatch
        if instance.collectFileMatches and instance.view do
            instance.collectFileMatches(.searchCarry, .searchCarryBase, &candidates)
        elif .searchEncoding != .Utf8 do
            Viewer.collectEncodedMatches(.searchCarry, .searchQuery, .searchEncoding, .searchOptions(), .searchCarryBase, &candidates)
        else do
            Viewer.collectTextMatches(.searchCarry, .searchQuery, .searchOptions(), 0, 0, .searchCarryBase, &candidates)
        let absoluteProcessed = rangeOrigin + .searchProcessed
        for match in candidates where match.offset >= absoluteProcessed and (eof or match.offset < .searchCarryBase + stableEnd)
        {
            if not instance.collectFileMatches or .searchMatches.count < SearchMatchLimit
            {
                .searchMatches.add(match)
            }
            else
            {
                .searchMatchesCapped = true
            }
        }

        if (.searchSelectLast or .searchIndex >= .searchMatches.count) and not .searchMatches.isEmpty()
        {
            .searchIndex = .searchSelectLast ? .searchMatches.count - 1 : 0
            .revealCurrentSearchMatch()
        }

        .searchProcessed = .searchCarryBase + stableEnd - rangeOrigin
        if eof
        {
            .finishSearch()
            return
        }

        var retainStart = stableEnd > SearchCarryMargin * unit ? stableEnd - SearchCarryMargin * unit : 0
        retainStart -= retainStart % unit
        .searchCarryBase += retainStart
        .searchCarry     = .searchCarry.toString()[retainStart to]
        .searchTimer     = .addTimer(1'ms)
        .refreshSearchReadout()
    }
}
