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
    const Pitch = 31.0

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
        let area  = .workspace.clientRect()
        let inset = .themeMetrics().floating_Inset
        let width = Math.min(Width, area.width - 2 * inset)
        let top   = .stripInset() + inset
        .panel.setPosition({area.right() - inset - width, top, width, Math.max(0, area.bottom() - top - inset)})
        .panel.applyLayout()
    }

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

        for &row in data[0].rows where not row.group and not row.value.isEmpty()
        {
            let title = row.label()
            if not title.count do
                continue
            var value: String
            for &candidate in data[1].rows where candidate.field == row.field and candidate.name == row.name
            {
                value = candidate.value
                break
            }

            .addFact(title, row.value, value)
        }

        for &row in data[1].rows where not row.group and not row.value.isEmpty()
        {
            let title = row.label()
            if not title.count do
                continue
            var found = false
            for &fact in .facts where fact.label == title do
                found = true
            if not found do
                .addFact(title, "", row.value)
        }

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
        let painter = evt.paintContext.painter
        let area    = .clientRect()
        let colors  = .themeColors()
        let app     = appStrings()
        let inset   = .themeMetrics().floating_Inset
        let title   = .theme().createDefaultFont(21, .Bold)
        let words   = .theme().createDefaultFont(12)
        let mono    = .theme().createDefaultFontFs(12)
        let first   = Math.round(area.width * 0.40)
        let second  = Math.round((first + area.width) / 2)
        let span    = second - first - inset
        painter.drawString(inset, inset, app.scene_ComparisonSheet, title, colors.text)
        painter.drawString(inset, inset + 31, Format.toString(app.scene_ComparisonFacts, .different, .facts.count), mono, colors.faintText)
        painter.drawString(first, 81, Painter.elideString(.names[0], words, span, .deviceScale()), words, colors.text)
        painter.drawString(second, 81, Painter.elideString(.names[1], words, span, .deviceScale()), words, colors.text)
        painter.fillRect(inset, 104, area.width - inset * 2, 1, colors.line)
        let top = 112.0
        painter.pushClippingRect({inset, top, area.width - inset * 2, Math.max(area.bottom() - top - 12, 0)})
        var y = top + 8 - .scroll
        .paintSection(painter, app.scene_Different, y)
        y += Pitch
        for &fact, index in .facts
        {
            if index == .different
            {
                y += 10
                .paintSection(painter, app.scene_Identical, y)
                y += Pitch
            }

            let differs = index < .different
            let color   = differs ? colors.text : colors.faintText
            painter.drawString(inset, y, Painter.elideString(fact.label, words, first - inset - 10, .deviceScale()), words, colors.softText)
            painter.drawString(first, y, Painter.elideString(fact.left, mono, span, .deviceScale()), mono, color)
            if differs do
                painter.drawString(second, y, Painter.elideString(fact.right, mono, span, .deviceScale()), mono, color)
            painter.fillRect(inset, y + Pitch - 8, area.width - inset * 2, 1, colors.line)
            y += Pitch
        }

        painter.popClippingRect()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Wheel
        {
            let maxScroll = Math.max(190 + cast(f32, .facts.count) * Pitch - .clientRect().height, 0)
            .scroll = Math.clamp(.scroll + (evt.delta.y > 0 ? -Pitch * 3 : Pitch * 3), 0, maxScroll)
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
        let font = .theme().createDefaultFont(11, .SemiBold)
        painter.drawString(.themeMetrics().floating_Inset, y, String.toUpper(text, .Unicode), font, .themeColors().faintText)
    }
}

impl ViewerWorkspace
{
    mtd wantsComparisonSheet()->bool
    {
        let scene = .scene()
        return scene and scene.compared and scene.views.count == 2
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
        sheet.layoutSheet()
        .activeDocument().lens.close()
        sheet.panel.bringToFront()
        discard .app().animator.arrive(sheet.panel)
        .activeDocument().refreshExplorerCaption()
    }

    mtd closeComparisonSheet()
    {
        if .comparisonSheet and .comparisonSheet.panel.isLocallyVisible() do
            discard .app().animator.leave(.comparisonSheet.panel)
    }
}
