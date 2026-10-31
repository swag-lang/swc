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
                if let line = list.selectedLine() do
                    panel.sigSelected.call(panel, cast(u64, line.userData0) - 1)
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

    // Uses the full heading as a tooltip when its row is shortened to fit the panel.
    private mtd updateHeadingTooltip(surfacePos: Math.Point)
    {
        let local = .list.listView.surfaceToLocal(surfacePos)
        if local.y < 0 or local.y >= .list.listView.clientRect().height
        {
            .list.listView.toolTip = ""
            return
        }

        let y = local.y + .list.scrollWnd.scrollPosition().y
        let index = cast(u32, y / .list.lineHeight())
        .list.listView.toolTip = index < .rowTitles.count ? .rowTitles[index].toString() : ""
    }

    // Keeps a quiet outline on the document's local palette, independently of application panels.
    mtd setReadingColors(colors: string)
    {
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

        // Keep document text literal: RichString's inline markers belong to presentation, not
        // heading content. A word joiner preserves the visible spelling of marker-like text.
        var literal = String.from(label.toString())
        literal.replace("<", "<\u2060")
        var display = literal
        if level == 1 do
            display = Format.toString("<b>%</b>", literal)

        let line = .list.createLine(display)
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
        let filter = .filter.toString()
        for heading in .headings where .filter.isEmpty() or
                                       heading.title.indexOf(filter, comparisonType: .Latin1NoCase) != Swag.U64.Max do
            .add(heading.title, heading.level, heading.sourceOffset)
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

    mtd bindHtml(view: *HtmlView)
    {
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
    }

    mtd bindMarkdown(view: *Markdown.View, fileName: string)
    {
        .markdownFile = fileName
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
