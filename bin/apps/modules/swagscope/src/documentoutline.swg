#global internal

using Core, Gui

// Visible strings of the document outline.
struct DocumentOutlineStrings
{
    title:   string = "Outline"                          // Title of the panel and tooltip of its toggle.
    empty:   string = "No outline in this document."     // Status of a document without headings.
    loading: string = "Reading outline…"                 // Status while the headings are read.
    close:   string = "Close Outline"                    // Tooltip of the close button.
    filter:  string = "Filter headings by name"          // Placeholder of the heading filter.
    noMatch: string = "No headings match."               // Status when the heading filter has no result.
}

private const FrenchOutlineStringsName = "lang/fr/scope.outline.tweak"
private const FrenchOutlineStrings     = #include("../datas/lang/fr/scope.outline.tweak")

private var g_DocumentOutlineStrings: DocumentOutlineStrings

// Distinguishes a document outline from the other viewer-owned side panels.
const OutlineToggleId = "scope.outline.toggle"

func outlineTitle()->string => g_DocumentOutlineStrings.title

#run
{
    expect Gui.validateStrings'DocumentOutlineStrings(cast(string, FrenchOutlineStrings))
}

private func loadMarkdownHeadings(fileName: string)->Array'DocumentHeading fail
{
    let source = try File.readAllBytes(fileName)
    return Markdown.parseHeadings(cast(string, source.toSlice()))
}

// One heading hierarchy shared by every document viewer, hosted beside its document.
struct DocumentOutline
{
    using wnd: Wnd

    late
    {
        status:    *Label
        filterBox: *EditBox
        toggle:    *IconButton
        list:      *ListCtrl
    }

    title:        *Label?
    section:      *SectionLabel?
    closeButton:  *IconButton?
    rows:         Array'(*ListLine)
    rowTitles:    Array'String
    levels:       Array'u32
    load:         Viewer.BackgroundLoad'(Array'DocumentHeading)
    failure:      String
    markdownFile: String
    filter:       String
    loaded:       bool
    marking:      bool                   // Whether the selection is being moved to follow the reading, not by the reader.
    reading:      u64 = Swag.U64.Max     // Target last given to `markReading`, marked again when the rows change.
    follow:       (func||())?            // Marks the heading of what the document shows now; set by the reader of that document.
    headings:     Array'DocumentHeading
    sigSelected:  SigArray'func||(*Wnd, u64)
    sigPublished: SigArray'func||(*DocumentOutline)     // Emitted after the headings listed changed.
}

impl DocumentOutline
{
    // Creates the outline panel and its toggle in the side lane of the viewer `host` is building.
    func create(host: Viewer.Host, floatingSurface = true)->*DocumentOutline
    {
        host.application().resources.addEmbedded(FrenchOutlineStringsName, FrenchOutlineStrings)
        Gui.registerStrings'DocumentOutlineStrings(&g_DocumentOutlineStrings, "scope.outline")
        let theme = host.contentParent().theme()
        let side  = host.createSidePanel(276,
                                         theme.icon(.Outline, themeActionIconSize(&theme.metrics)),
                                         g_DocumentOutlineStrings.title,
                                         floatingSurface: floatingSurface)
        side.toggle.id = OutlineToggleId

        with let result = Wnd.create'DocumentOutline(side.content, "scope.outline")
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .padding         = floatingSurface ? Math.Vector4{12, 8, 12, 8} : Math.Vector4{0, 8, 0, 8}
            .toggle          = side.toggle
        }

        // An outline opened over a document marks the heading in view at once, not at the first scroll.
        result.toggle.sigCheckedChanged += func|panel = result|(button)
        {
            if button.isChecked do
                panel.followReading()
        }

        let size = themeCompactButtonSize(result.themeMetrics())

        with let header = Wnd.create'Wnd(result, Math.Rectangle{0, 0, 0, size})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        if floatingSurface
        {
            with result.closeButton = IconButton.create(header, theme.icon(.WndClose, themeRowIconSize(result.themeMetrics())), Math.Rectangle{0, 0, size, size})
            {
                .dockStyle  = .Right
                .sigPressed += func|panel = result|(_)
                {
                    panel.toggle.setChecked(false)
                    panel.toggle.sigCheckedChanged.call(panel.toggle)
                }
            }

            with result.title = Label.create(header, "", {}, null, .Ellipsis)
            {
                .dockStyle = .Center
                .setTextAlignment(.Left, .Center)
                .style.setFont(theme.createDefaultFont(13, .Bold), .Regular)
            }
        }
        else
        {
            with result.section = SectionLabel.create(header, g_DocumentOutlineStrings.title)
            {
                .dockStyle = .Center
            }
        }

        with result.status = Label.create(result, "", {}, null, .WordWrap | .AutoHeight | .SecondaryText)
        {
            .dockStyle = .Top
            .margin.y  = 8
        }

        with result.filterBox = EditBox.create(result, "", Math.Rectangle{0, 0, 0, size})
        {
            .dockStyle = .Top
            .margin    = {0, 8, 0, 0}
            .setIcon(theme.icon(.Search, themeRowIconSize(&theme.metrics)))
            .setPlaceholder(g_DocumentOutlineStrings.filter)
            .updateFlags(.ClearButton)
            .sigTextChanged += func|panel = result|(edit) { panel.setFilter(edit.text()) }
        }

        with result.list = ListCtrl.createSimple(result, {}, "scope.outline.list")
        {
            .dockStyle       = .Center
            .margin.y        = 8
            .backgroundStyle = .Transparent
            .listView.backgroundStyle = .Transparent
            .setFirstColumnIconMargin(false)
            .setIndentWidth(16)
            .updateFlags(.HotTrack | .Ellipsis)
            .sigSelectionChanged += func|panel = result|(list)
            {
                if panel.marking do
                    return
                if let line = list.selectedLine() do
                    panel.sigSelected.call(panel, targetOf(line))
            }
        }

        result.hookOnChildEvent = func|panel = result|(_, evt)
        {
            if evt is MouseEvent as mouse
            {
                if mouse.kind == .Move or mouse.kind == .Enter
                {
                    panel.list.scrollWnd.revealScrollBars()
                    panel.updateHeadingTooltip(mouse.surfacePos)
                }
                elif mouse.kind == .Leave
                {
                    panel.list.listView.toolTip = ""
                }
            }

            return false
        }

        result.refresh()
        return result
    }

    mtd clear()
    {
        .rows.clear()
        .rowTitles.clear()
        .levels.clear()
        .list.clear()
    }

    // Returns the row under a surface point, or `U64.Max` outside the listed headings.
    private mtd rowAt(surfacePos: Math.Point)->u64
    {
        let view  = .list.listView
        let local = view.surfaceToLocal(surfacePos)
        if local.x < 0 or
           local.x >= view.clientRect().width or
           local.y < 0 or
           local.y >= view.clientRect().height do
            return Swag.U64.Max
        let row = cast(u64, (local.y + .list.scrollWnd.scrollPosition().y) / .list.lineHeight())
        return row < .rows.count ? row : Swag.U64.Max
    }

    // Uses the full heading as a tooltip when its row is shortened to fit the panel.
    private mtd updateHeadingTooltip(surfacePos: Math.Point)
    {
        let row = .rowAt(surfacePos)
        .list.listView.toolTip = row < .rowTitles.count ? .rowTitles[row].toString() : ""
    }

    // Keeps a quiet outline on the document's local palette, independently of application panels.
    mtd setReadingColors(colors: string)
    {
        .backgroundStyle = .View

        func apply(wnd: *Wnd, colors: string)
        {
            wnd.style.setStyleSheetColors(colors)
            wnd.computeStyle()
            for child in wnd.children do
                apply(child, colors)
        }

        apply(me, colors)
        .invalidate()
    }

    // Appends a heading with its whitespace collapsed, indented one level per enclosing heading of
    // a lower `level`. `target` is stored plus one so that target zero is not a null user pointer.
    mtd add(title: string, level: u32, target: u64)
    {
        while .levels.count and .levels.back() >= level do
            discard .levels.popBack()

        var label: String
        var space: bool

        // A continuation byte can match Latin-1 whitespace inside a valid UTF-8 character.
        Utf8.visitRunes(title)
        {
            if Unicode.isSpace(c)
            {
                space = not label.isEmpty()
            }
            else
            {
                if space do
                    label += ' '
                label.append(c)
                space = false
            }
        }

        // The heading is document text, set literally; a first-level one is a bold run.
        let line = .list.createLine(label)
        if level == 1 do
            line.items[0]!.name.set(label, {bold: true})
        line.level     = Math.min(level ? level - 1 : 0, 5)
        line.userData0 = cast(*void, target + 1)
        .rows.add(line)
        .rowTitles.add(label)
        .levels.add(level)
    }

    // Shows `headings`, rebuilding the rows only when a title, level or offset differs from what is
    // listed, so republishing the same outline does not reset the list.
    mtd publish(headings: const [..] DocumentHeading)
    {
        var changed = .headings.count != headings.count
        if not changed
        {
            for heading, index in headings
            {
                let previous = &.headings[index]
                if heading.title != previous.title or
                   heading.level != previous.level or
                   heading.sourceOffset != previous.sourceOffset
                {
                    changed = true
                    break
                }
            }
        }

        if not changed
        {
            .refresh()
            return
        }

        .headings.clear()
        .headings.add(headings)
        .rebuildRows()
        .refresh()

        // Headings and the first layout arrive in no fixed order: the later of the two marks.
        .followReading()
        .sigPublished.call(me)
    }

    // Recreates only headings whose titles contain the local outline filter.
    mtd setFilter(filter: string)
    {
        if .filter == filter do
            return
        .filter = filter
        .rebuildRows()
        .refresh()
    }

    private mtd rebuildRows()
    {
        .clear()
        let filter  = .filter.toString()
        let matcher = assume Text.NameMatcher.create(filter)
        for heading in .headings where .filter.isEmpty() or matcher.isMatch(heading.title.toString()) do
            .add(heading.title, heading.level, heading.sourceOffset)

        // The rows are new: the heading being read is found among them again.
        .markReading(.reading)
    }

    mtd refresh()
    {
        .title?.setText(g_DocumentOutlineStrings.title)
        .section?.setText(g_DocumentOutlineStrings.title)
        .filterBox.setPlaceholder(g_DocumentOutlineStrings.filter)
        .toggle.toolTip = g_DocumentOutlineStrings.title
        if .closeButton do
            .closeButton.toolTip = g_DocumentOutlineStrings.close
        var statusText: String
        if not .failure.isEmpty() do
            statusText = .failure.toString()
        elif .load.isPending() do
            statusText = g_DocumentOutlineStrings.loading
        elif not .headings.isEmpty() and not .filter.isEmpty() and .rows.isEmpty() do
            statusText = g_DocumentOutlineStrings.noMatch
        else do
            statusText = g_DocumentOutlineStrings.empty
        .status.setText(statusText)
        .status.show(.levels.isEmpty() or (not .headings.isEmpty() and not .filter.isEmpty() and .rows.isEmpty()))
        .list.computeLayout()
        .applyLayout()
    }

    // Returns the target a row was added with; it is stored plus one, see `add`.
    private func targetOf(line: *ListLine)->u64 => cast(u64, line.userData0) - 1

    // Returns the target of the heading selected in the list, or `U64.Max` without one.
    mtd markedTarget()->u64
    {
        let line = .list.selectedLine()
        return line ? targetOf(line) : Swag.U64.Max
    }

    // Marks the heading being read: the last one listed at or before `target`, or none when the
    // reader is above the first. Nothing is emitted, since the document is already there.
    //
    // At the end of a document, `atEnd`, every later heading is on screen with no room to rise to
    // the top, so a later heading the reader chose there stays marked.
    mtd markReading(target: u64, atEnd = false)
    {
        if target == Swag.U64.Max do
            return
        .reading = target
        let marked = .markedTarget()
        if atEnd and marked != Swag.U64.Max and marked >= target do
            return

        var row       = Swag.U64.Max
        var rowTarget = Swag.U64.Max
        for line, index in .rows where targetOf(line) <= target
        {
            row       = index
            rowTarget = targetOf(line)
        }

        if rowTarget == marked do
            return

        .marking = true
        defer .marking = false
        if row == Swag.U64.Max
        {
            .list.unselectAll()
            return
        }

        .list.selectLine(cast(u32, row))
        .list.ensureVisibleLine(cast(u32, row))
    }

    // Marks the heading of what the document shows now, through the reader that bound it. Does
    // nothing before a document is bound or laid out.
    mtd followReading()
    {
        if .follow do
            .follow()
    }

    // Marks the heading of what the document shows now, as `followReading`, only while the
    // outline is open. Finding the text being read walks the document's layout, too much to do
    // on every scroll for a closed outline, which marks the heading again as it opens.
    mtd followOpenReading()
    {
        if .toggle.isChecked do
            .followReading()
    }

    mtd bindHtml(view: *HtmlView)
    {
        .follow = func|panel = me, view|()
        {
            panel.markReading(view.readingOffset(), atEnd: view.readingProgress() >= 1)
        }

        let headings = view.headings()
        .publish(headings.toSlice())
        view.sigDocumentChanged += func|panel = me|(html)
        {
            let headings = html.headings()
            panel.publish(headings.toSlice())
        }

        .sigSelected += func|view|(_, offset)
        {
            discard view.revealFileOffset(offset, "")
        }

        // The heading being read follows the page as it moves.
        view.sigScrolled += func|panel = me|(_)
        {
            panel.followOpenReading()
        }
    }

    mtd bindMarkdown(view: *Markdown.View, fileName: string)
    {
        .markdownFile = fileName
        .follow       = func|panel = me, view|()
        {
            panel.markReading(view.readingOffset(), atEnd: view.readingProgress() >= 1)
        }

        .toggle.sigCheckedChanged += func|panel = me, view|(button)
        {
            if button.isChecked
            {
                panel.startMarkdown()
                panel.filterBox.setFocus()
            }
            else
            {
                view.setFocus()
            }
        }

        .sigSelected += func|view|(_, offset)
        {
            discard view.revealHeading(offset)
        }

        // The heading being read follows the document as it moves.
        view.sigScrolled += func|panel = me|(_)
        {
            panel.followOpenReading()
        }
    }

    mtd startMarkdown()
    {
        if .loaded or .load.started do
            return
        .load.start(.markdownFile, &loadMarkdownHeadings, me)
        .refresh()
    }

    mtd retire()->bool
    {
        return .load.retire()
    }
}

impl IWnd for DocumentOutline
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt) do
            return
        var headings: Array'DocumentHeading
        .failure = .load.finish(&headings)
        .loaded  = true
        .publish(headings.toSlice())
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .refresh()
        .wnd.IWnd.onNotifyEvent(evt)
    }
}
