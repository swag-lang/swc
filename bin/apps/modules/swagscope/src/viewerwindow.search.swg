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
        let canFilter = .activeChoiceIndex < .instances.count and .instances[.activeChoiceIndex].filterSearch != null
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
        if .activeChoiceIndex < .instances.count
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
        var presentation: Viewer.SearchPresentation
        presentation.placeholder = appStrings().ui_Search
        if .activeChoiceIndex < .instances.count
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
        .searchGroup.spacing = hasMenu ? SearchGroupSpacing : 0
        .searchBox.resize(hasMenu ? SearchFieldWidth : SearchNoOptionsFieldWidth, 36)
        discard .searchBox.revalidate()
        .searchGroup.computeLayout()
        .layoutSearchBar()
    }

    // Searches the active viewer again for the text of the search box. Filter mode hands the query
    // to the viewer's filter; otherwise matches come from the viewer or a scan of the file, and
    // `selectLast` selects the last one instead of the first.
    mtd restartSearch(selectLast = false)
    {
        .forgetSearch()
        .searchSelectLast = selectLast
        .searchQuery      = .searchBox.text()
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
            var options = .searchOptions()
            var expression: Parser.RegExp
            if options.regularExpression
            {
                catch expression.compile(.searchQuery, ignoreCase: not options.matchCase)
                {
                    .searchComplete = true
                    .refreshSearchReadout()
                    return
                }

                options.expression = &expression
            }

            instance.filterSearch(.searchQuery, options)
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
            var plan: Viewer.SearchPlan
            let state = instance.prepareSearch(.searchQuery, &plan)
            if state != .Valid
            {
                .searchComplete = true
                if state == .InvalidVisible do
                    .searchError = #move plan.error
                .refreshSearchReadout()
                return
            }

            .searchSpan = Math.max(plan.span, 1)
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
        if .searchFilterMode
        {
            .searchCountLabel.setText("")
            .searchCountLabel.toolTip = ""
            .searchPrevious.enable(false)
            .searchNext.enable(false)
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
            // A viewer still reading its document counts what it has found so far.
            if .searchIndex < .searchMatches.count do
                .searchCountLabel.setText(Format.toString("%/%…", .searchIndex + 1, .searchMatches.count))
            else do
                .searchCountLabel.setText("…")
            .searchCountLabel.toolTip = appStrings().ui_Searching
        }
        elif .searchMatches.isEmpty()
        {
            .searchCountLabel.setText("0/0")
            .searchCountLabel.toolTip = appStrings().ui_NoMatch
        }
        else
        {
            .searchCountLabel.setText(Format.toString("%/%", .searchIndex + 1, .searchMatches.count))
            .searchCountLabel.toolTip = .searchCountLabel.text()
        }

        let canNavigate = not .searchMatches.isEmpty()
        .searchPrevious.enable(canNavigate)
        .searchNext.enable(canNavigate)
        .searchBox.toolTip = .searchError.isEmpty() ? .searchToolTip.toString() : .searchError.toString()
    }

    // Scrolls the active viewer to the current match and refreshes the readout and highlight, leaving
    // the keyboard in the search box when the reveal started there.
    private mtd revealCurrentSearchMatch()
    {
        if .searchIndex >= .searchMatches.count or .activeChoiceIndex >= .instances.count do
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
        if .searchIndex >= .searchMatches.count and not .searchMatches.isEmpty()
        {
            .searchIndex = .searchSelectLast ? .searchMatches.count - 1 : 0
            .revealCurrentSearchMatch()
        }

        .refreshSearchReadout()
    }

    // Brings the find bar over the document and gives it the keyboard; while a folder is
    // explored, its filter takes the query instead.
    mtd showSearch()
    {
        if .explorerActive and .explorer and .explorer.isLocallyVisible()
        {
            .explorer.revealFilter()
            return
        }

        if not .searchBox.isEnabled() do
            return
        .searchShown = true
        .searchBar.show()
        .layoutSearchBar()
        .searchBox.setFocus()
        .searchBox.selectAll()
    }

    // Puts the find bar away and gives the keyboard back to the document. The query stays: the
    // next and previous matches still answer their keys, and the bar comes back holding it.
    mtd hideSearch()
    {
        .searchShown = false
        .searchBar.hide()
        .viewerFocusTarget()?.setFocus()
    }

    // Keeps document navigation available while the search field owns the keyboard. Page keys
    // also work from the rest of the action bar; when focus is already inside the viewer the
    // forwarding helper declines and the original event follows its normal path.
    mtd routeSearchNavigationKey(evt: *KeyEvent)->bool
    {
        if .forwardingViewerKey or evt.kind != .Pressed or .searchIndex >= .searchMatches.count do
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
    // while the reader asked for it, and restarts the search for the new viewer.
    mtd updateSearchAvailability()
    {
        let active         = .activeChoiceIndex < .instances.count
        let available      = active and .instances[.activeChoiceIndex].revealMatch != null
        let focused        = .focusedWindow()
        let searchHadFocus = focused and (focused == .searchGroup or .searchGroup.isOwnerOf(focused))

        .refreshSearchPresentation()
        .searchBox.enable(available)
        .searchOptionsButton.enable(available)
        .searchBar.show(available and .searchShown)
        .currentActions?.show()
        .layoutSearchBar()
        .restartSearch()
        if not available and searchHadFocus do
            .viewerFocusTarget()?.setFocus()
    }

    // Cancels the search in progress and hides its highlight; `clearPresentation` also clears the
    // matches the viewer highlights.
    mtd stopSearch(clearPresentation = true)
    {
        .stopTimer(&.searchTimer)

        .searchStream.close()
        .searchCarry.clear()
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
        .searchIndex    = Swag.U64.Max
        .searchMatch    = Swag.U64.Max
        .searchComplete = false
    }

    mtd beginSearch()
    {
        .searchStream = catch File.openReadLive(.currentFile)
        {
            .finishSearch()
            return
        }

        .searchCarryBase = 0
        .searchProcessed = 0
        .searchCarry.clear()
        .searchTimer = .addTimer(1'ms)
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

        var bytes: Array'u8
        bytes.resize(SearchChunkSize)
        let count = catch .searchStream.read(bytes.toSlice())
        {
            .finishSearch()
            return
        }

        bytes.resize(count)
        .searchCarry += cast(string, bytes.toSlice())
        let eof      = count == 0
        let instance = &.instances[.activeChoiceIndex]

        // A regular expression may span an arbitrary number of chunks, and ^/$ refer to the
        // document rather than to an implementation buffer. Keep reading incrementally so the
        // interface remains responsive, then evaluate once against the complete source.
        if .searchRegexOption and not instance.collectFileMatches and not eof
        {
            .searchTimer = .addTimer(1'ms)
            return
        }

        let deferSize = .searchSpan + SearchCarryMargin
        var stableEnd = 0'u64
        if eof do
            stableEnd = .searchCarry.length
        elif .searchCarry.length > deferSize do
            stableEnd = .searchCarry.length - deferSize

        var candidates: Array'Viewer.SearchMatch
        if instance.collectFileMatches and instance.view do
            instance.collectFileMatches(.searchCarry, .searchCarryBase, &candidates)
        else do
            Viewer.collectTextMatches(.searchCarry, .searchQuery, .searchOptions(), 0, 0, .searchCarryBase, &candidates)
        for match in candidates where match.offset >= .searchProcessed and (eof or match.offset < .searchCarryBase + stableEnd) do
            .searchMatches.add(match)

        .searchProcessed = .searchCarryBase + stableEnd
        if eof
        {
            .finishSearch()
            return
        }

        let retainStart = stableEnd > SearchCarryMargin ? stableEnd - SearchCarryMargin : 0
        .searchCarryBase += retainStart
        .searchCarry     = .searchCarry.toString()[retainStart to]
        .searchTimer     = .addTimer(1'ms)
    }
}
