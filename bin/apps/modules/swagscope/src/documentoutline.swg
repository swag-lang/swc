#global internal

using Core, Gui

struct DocumentOutlineStrings
{
    title:   string = "Outline"
    empty:   string = "No outline in this document."
    loading: string = "Reading outline…"
    close:   string = "Close outline"
}

private var g_DocumentOutlineStrings: DocumentOutlineStrings
private const FrenchOutlineStrings = #include("../datas/lang/fr/scope.outline.tweak")

#run { expect Gui.validateStrings'DocumentOutlineStrings(cast(string) FrenchOutlineStrings) }

private func loadMarkdownHeadings(fileName: string)->Array'DocumentHeading fail
{
    let source = try File.readAllBytes(fileName)
    return Markdown.parseHeadings(cast(string) source.toSlice())
}

// One hierarchy shared by every document viewer, hosted in the information panel lane.
struct DocumentOutline
{
    using wnd: Wnd

    late
    {
        title:       *Label
        status:      *Label
        closeButton: *IconButton
        toggle:      *IconButton
        list:        *ListCtrl
    }

    rows:         Array'(*ListLine)
    levels:       Array'u32
    load:         Viewer.BackgroundLoad'(Array'DocumentHeading)
    loadTimer:    *Timer?
    failure:      String
    markdownFile: String
    loaded:       bool
    headings:     Array'DocumentHeading
    sigSelected:  SigArray'func||(*DocumentOutline, u64)
}

impl DocumentOutline
{
    func create(host: Viewer.Host)->*DocumentOutline
    {
        host.application().resources.addEmbedded("lang/fr/scope.outline.tweak", FrenchOutlineStrings)
        Gui.registerStrings'DocumentOutlineStrings(&g_DocumentOutlineStrings, "scope.outline")
        let theme  = host.contentParent().theme()
        let side   = host.createSidePanel(276, theme.icon(.Information, themeActionIconSize(&theme.metrics)), g_DocumentOutlineStrings.title)
        let result = Wnd.create'DocumentOutline(side.content, "scope.outline")
        result.dockStyle       = .Center
        result.backgroundStyle = .Transparent
        result.padding         = {12, 8, 12, 8}
        result.toggle          = side.toggle
        let size   = themeCompactButtonSize(result.themeMetrics())
        let header = Wnd.create'Wnd(result, {0, 0, 0, size})
        header.dockStyle              = .Top
        header.backgroundStyle        = .Transparent
        result.closeButton            = IconButton.create(header, theme.icon(.WndClose, themeRowIconSize(result.themeMetrics())), {0, 0, size, size})
        result.closeButton.dockStyle  = .Right
        result.closeButton.sigPressed += func|panel = result|(button)
        {
            discard button
            panel.toggle.setChecked(false)
            panel.toggle.sigCheckedChanged.call(panel.toggle)
        }

        result.title = Label.create(header, "", {}, null, .Ellipsis)
        result.title.dockStyle = .Center
        result.title.setTextAlignment(.Left, .Center)
        result.title.style.setFont(theme.createDefaultFont(13, .Bold), .Regular)
        result.status               = Label.create(result, "", {}, null, .WordWrap | .AutoHeight | .SecondaryText)
        result.status.dockStyle     = .Top
        result.status.margin.y      = 8
        result.list                 = ListCtrl.createSimple(result, {}, "scope.outline.list")
        result.list.dockStyle       = .Center
        result.list.margin.y        = 8
        result.list.backgroundStyle = .Transparent
        result.list.listView.backgroundStyle = .Transparent
        result.list.setFirstColumnIconMargin(false)
        result.list.setIndentWidth(16)
        result.list.updateFlags(.HotTrack | .Ellipsis)
        result.list.sigSelectionChanged += func|panel = result|(list)
        {
            if let line = list.selectedLine() do
                panel.sigSelected.call(panel, cast(u64) line.userData0 - 1)
        }

        result.refresh()
        return result
    }

    mtd clear()
    {
        .rows.clear()
        .levels.clear()
        .list.clear()
    }

    mtd add(title: string, level: u32, target: u64)
    {
        while .levels.count and .levels.back() >= level do
            discard .levels.popBack()

        var label: String
        var space: bool
        for byte in title
        {
            if Latin1.isSpace(byte) do
                space = not label.isEmpty()
            else
            {
                if space do
                    label += ' '
                label += byte
                space = false
            }
        }

        // Every heading stays visible. Indentation expresses depth without disclosure controls.
        let line = .list.createLine(label.toString())
        line.level     = cast(u32) .levels.count
        line.userData0 = cast(*void) (target + 1)
        .rows.add(line)
        .levels.add(level)
    }

    mtd publish(headings: const [..] DocumentHeading)
    {
        var changed = .headings.count != headings.count
        if not changed
        {
            for heading, index in headings
            {
                let previous = &.headings[index]
                if heading.title != previous.title or heading.level != previous.level or heading.sourceOffset != previous.sourceOffset
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
        .clear()
        for heading in headings do
            .add(heading.title.toString(), heading.level, heading.sourceOffset)
        .refresh()
    }

    mtd refresh()
    {
        .title.setText(g_DocumentOutlineStrings.title)
        .toggle.toolTip      = g_DocumentOutlineStrings.title
        .closeButton.toolTip = g_DocumentOutlineStrings.close
        .status.setText(not .failure.isEmpty() ? .failure.toString() : .loadTimer ? g_DocumentOutlineStrings.loading : g_DocumentOutlineStrings.empty)
        .status.show(.levels.isEmpty())
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

        .sigSelected += func|view|(panel, offset)
        {
            discard panel
            discard view.revealFileOffset(offset, "")
        }
    }

    mtd bindMarkdown(view: *Markdown.View, fileName: string)
    {
        .markdownFile = fileName
        .toggle.sigCheckedChanged += func|panel = me|(button)
        {
            if button.isChecked do
                panel.startMarkdown()
        }

        .sigSelected += func|view|(panel, offset)
        {
            discard panel
            discard view.revealHeading(offset)
        }
    }

    mtd startMarkdown()
    {
        if .loaded or .load.started do
            return
        .load.start(.markdownFile.toString(), &loadMarkdownHeadings)
        .loadTimer = .addTimer(Viewer.BackgroundPollInterval)
        .refresh()
    }

    mtd retire()->bool
    {
        if not .load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        return true
    }
}

impl IWnd for DocumentOutline
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer or not .load.isDone() do
            return
        .removeTimer(evt.timer)
        .loadTimer = null
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
