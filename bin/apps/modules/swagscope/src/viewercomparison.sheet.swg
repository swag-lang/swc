#global internal

using Core, Gui, Pixel

struct ComparisonFact
{
    label: String
    left:  String
    right: String
}

struct ComparisonSheet
{
    using wnd:      Wnd
    late workspace: *ViewerWorkspace
    late panel:     *FloatingPanel
    facts:          Array'ComparisonFact
    names:          [2] String
    different:      u64
    scroll:         f32
}

impl ComparisonSheet
{
    const Width = 540.0

    func create(workspace: *ViewerWorkspace)->*ComparisonSheet
    {
        let panel = FloatingPanel.create(workspace, id: "scope.scene.information")
        panel.padding = {}
        panel.wndFlags.add(.TopMost)
        let result = Wnd.create'ComparisonSheet(panel)
        result.workspace       = workspace
        result.panel           = panel
        result.backgroundStyle = .Transparent
        result.dockStyle       = .Center
        panel.hide()
        return result
    }

    mtd layoutSheet()
    {
        let area   = .workspace.clientRect()
        let inset  = .themeMetrics().floating_Inset
        let width  = Math.clamp(area.width - 2 * inset, 0, Width)
        let top    = .workspace.stripInset() + inset
        let height = Math.min(.contentHeight(), Math.max(0, area.bottom() - top - inset))
        .panel.setPosition({area.right() - inset - width, top, width, height})
        .panel.applyLayout()
        .scroll = Math.min(.scroll, .scrollLimit())
    }

    private mtd headerHeight()->f32
    {
        let metrics = .themeMetrics()
        return metrics.floating_Inset + cast(f32, metrics.infoSheet_TitleFontSize) + 2 * metrics.infoSheet_LineHeight
    }

    private mtd contentHeight()->f32
    {
        let metrics     = .themeMetrics()
        let factsHeight = cast(f32, .facts.count) * metrics.infoSheet_LineHeight
        var height      = .headerHeight() + metrics.infoSheet_LineGap + factsHeight + metrics.floating_Inset
        if .different do
            height += metrics.infoSheet_LineHeight
        if .different < .facts.count do
            height += metrics.infoSheet_LineHeight + (.different ? metrics.infoSheet_BlockGap : 0)
        return height
    }

    private mtd scrollLimit()->f32 => Math.max(0, .contentHeight() - .clientRect().height)

    mtd refresh()
    {
        let scene = .workspace.scene()
        if not scene or not scene.compared or scene.views.count != 2
        {
            .panel.hide()
            return
        }

        .facts.clear()
        .different = 0
        var data: [2] MediaInfoData
        for &view, side in scene.views
        {
            .names[side] = Path.fileName(view.path) orelse view.path.toString()
            if view.document do
                data[side] = comparisonFacts(view.document)
        }

        var paired: Array'bool
        paired.resize(data[1].rows.count)
        for &row in data[0].rows where not row.group and not row.value.isEmpty()
        {
            let title = row.label()
            if not title.count do
                continue
            var value: String
            for &candidate, index in data[1].rows
            {
                if paired[index] or
                   candidate.group or
                   candidate.value.isEmpty() or
                   candidate.field != row.field or
                   candidate.name != row.name do
                    continue
                paired[index] = true
                value         = candidate.value
                break
            }

            .addFact(title, row.value, value)
        }

        for &row, index in data[1].rows where not paired[index] and not row.group and not row.value.isEmpty()
        {
            let title = row.label()
            if title.count do
                .addFact(title, "", row.value)
        }

        .layoutSheet()
        .invalidate()
    }

    private mtd addFact(label, left, right: string)
    {
        let fact = ComparisonFact{String.from(label), String.from(left), String.from(right)}
        if left != right
        {
            .facts.insertAt(.different, fact)
            .different += 1
        }
        else
        {
            .facts.add(fact)
        }
    }
}

private func comparisonFacts(document: *ViewerWindow)->MediaInfoData
{
    var data: MediaInfoData
    switch document.currentView
    {
    case Viewers.Film.Panel as film:
        data = film.information

    case Viewers.Picture.Panel as picture:
        data = picture.information

    case Viewers.PlainText.Panel as text:
        data.add(.Encoding, text.encodingName())
        if text.hasStatistics do
            data.addTextStatistics(&text.statistics)

    case Viewers.Code.Panel as code:
        data.add(.Language, code.languageName)
        data.add(.Encoding, "UTF-8")
        if code.hasStatistics do
            data.addTextStatistics(&code.statistics, withWords: false)

    case Viewers.Typeface.Panel as font:
        let face = font.document.face
        if face
        {
            data.add(.Typeface, face.familyName)
            data.add(.Style, face.styleName)
            data.add(.UnitsPerEm, Format.toString("%", face.unitsPerEm))
        }

    default:
        break
    }

    let extension = Path.extension(document.currentFile) orelse ""
    data.addText(appStrings().explore_Type, extension)
    data.addText(appStrings().explore_Size, document.currentFileSize)
    return data
}

impl IWnd for ComparisonSheet
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter  = evt.paintContext.painter
        let area     = .clientRect()
        let colors   = .themeColors()
        let metrics  = .themeMetrics()
        let app      = appStrings()
        let inset    = metrics.floating_Inset
        let pitch    = metrics.infoSheet_LineHeight
        let title    = .theme().createDefaultFont(metrics.infoSheet_TitleFontSize, .Bold)
        let words    = .theme().createDefaultFont(metrics.defaultFontSize)
        let mono     = .theme().createDefaultFontFs(metrics.defaultFontSize)
        let first    = Math.round(area.width * 0.37)
        let second   = Math.round((first + area.right() - inset) / 2)
        let span     = Math.max(second - first - metrics.infoSheet_LineGap, 0)
        let identity = inset + cast(f32, metrics.infoSheet_TitleFontSize) + metrics.infoSheet_LineGap
        let top      = .headerHeight()
        painter.drawString(inset, inset, app.scene_ComparisonSheet, title, colors.text)
        painter.drawString(inset, identity, Format.toString(app.scene_ComparisonFacts, .different, .facts.count), mono, colors.faintText)
        let names = top - pitch + metrics.infoSheet_LineGap
        painter.drawString(first, names, Painter.elideString(.names[0], words, span, .deviceScale()), words, colors.text)
        painter.drawString(second, names, Painter.elideString(.names[1], words, span, .deviceScale()), words, colors.text)
        painter.fillRect(inset, top, area.width - inset * 2, metrics.separator_HairlineSize, colors.line)
        painter.pushClippingRect({inset, top + metrics.infoSheet_LineGap, area.width - inset * 2,
                                  Math.max(area.bottom() - top - metrics.infoSheet_LineGap - inset, 0)})
        var y = top + metrics.infoSheet_LineGap - .scroll
        if .different
        {
            .paintSection(painter, app.scene_Different, y)
            y += pitch
        }

        for &fact, index in .facts
        {
            if index == .different
            {
                if .different do
                    y += metrics.infoSheet_BlockGap
                .paintSection(painter, app.scene_Identical, y)
                y += pitch
            }

            let differs    = index < .different
            let color      = differs ? colors.text : colors.faintText
            let valueWidth = differs ? span : Math.max(area.right() - inset - first, 0)
            painter.drawString(inset, y, Painter.elideString(fact.label, words, Math.max(first - 2 * inset, 0), .deviceScale()), words, colors.softText)
            painter.drawString(first, y, Painter.elideString(fact.left, mono, valueWidth, .deviceScale()), mono, color)
            if differs do
                painter.drawString(second, y, Painter.elideString(fact.right, mono, span, .deviceScale()), mono, color)
            y += pitch
        }

        painter.popClippingRect()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Wheel
        {
            let step = .themeMetrics().infoSheet_LineHeight * 3
            .scroll = Math.clamp(.scroll - evt.delta.y * step, 0, .scrollLimit())
            .invalidate()
            return
        }

        evt.accepted = evt.kind == .Accept
    }
}

impl ComparisonSheet
{
    private mtd paintSection(painter: *Painter, text: string, y: f32)
    {
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(metrics.sectionLabel_FontSize, .SemiBold)
        painter.drawString(metrics.floating_Inset, y, String.toUpper(text, .Unicode), font, .themeColors().faintText)
    }
}

impl ViewerWorkspace
{
    mtd wantsComparisonSheet()->bool
    {
        let scene = .scene()
        return scene and scene.compared and scene.views.count == 2 and not scene.maximized
    }

    mtd toggleComparisonSheet()
    {
        if not .comparisonSheet do
            .comparisonSheet = ComparisonSheet.create(me)
        let sheet = .comparisonSheet
        if sheet.panel.isLocallyVisible()
        {
            .closeComparisonSheet()
            return
        }

        sheet.scroll = 0
        sheet.refresh()
        .activeDocument().lens.close()
        sheet.panel.bringToFront()
        discard .app().animator.arrive(sheet.panel)
        .activeDocument().refreshExplorerCaption()
    }

    mtd closeComparisonSheet()
    {
        if not .comparisonSheet or not .comparisonSheet.panel.isLocallyVisible() do
            return
        discard .app().animator.leave(.comparisonSheet.panel)
        .activeDocument().refreshExplorerCaption()
    }
}
