#global internal
#global namespace Viewers.Binary

using Core, Pixel, Gui

// The report page of a binary: what the file is, before any structure.
//
// The file's name over a mono identity line, its figures in large light type, its sections as one
// proportional bar with their legend, then what it imports, library by library. Everything comes
// from the [[Overview]] the format reader filled; the structure tree stays one lens entry away.
struct ReportPage
{
    using wnd: Wnd

    document: *Document?     // Borrowed from the panel that owns both.
    title:    String         // The file's name.
}

private
{
    // The page's edges on a wide window and on a narrow one, the width that separates them, and the
    // air above the title.
    const WideMargin   = 120.0
    const NarrowMargin = 40.0
    const WideWidth    = 1100.0
    const TopAir       = 36.0

    // Sizes of the title, of a figure and of its label, of the identity line, and of the lines
    // that list sections and imports.
    const TitleSize     = 26'u32
    const FigureSize    = 36'u32
    const LabelSize     = 13'u32
    const MonoSize      = 12'u32
    const SmallMonoSize = 11'u32

    // Air between two figures, between two bands of the page, and inside the legend; the height of
    // the sections bar, and the pitch of an import line and where its names start.
    const FigureGap   = 64.0
    const BandGap     = 34.0
    const LabelGap    = 12.0
    const BarHeight   = 14.0
    const BarJoint    = 2.0
    const LegendGap   = 20.0
    const LegendDot   = 3.5
    const ImportPitch = 28.0
    const NamesColumn = 180.0
}

impl ReportPage
{
    func create(parent: *Wnd)->*ReportPage
    {
        with let result = Wnd.create'ReportPage(parent, "scope.binary.page", {})
        {
            .backgroundStyle = .View
            .dockStyle       = .Center
        }

        return result
    }

    // Shows the overview of `document`, under the file name `title`.
    mtd setDocument(document: *Document, title: string)
    {
        .document = document
        .title    = title
        .invalidate()
    }

    // Returns the colour of section `index` in the bar and its legend.
    //
    // The largest sections take the series hues, in file order; the small ones share the faint ink,
    // so the hues go to what holds the bytes.
    private mtd sectionColor(sections: const *Array'OverviewSection, index: u64)->Color
    {
        let colors = .themeColors()
        let hues   = colors.series.count

        // A section ranks by how many others store more, the earlier one first on a tie.
        let rank = func|sections|(at: u64)->u64
        {
            var result = 0'u64
            for other, otherAt in sections
            {
                let size = sections[at].size
                if other.size > size or (other.size == size and otherAt < at) do
                    result += 1
            }

            return result
        }

        if rank(index) >= hues do
            return colors.faintText
        var hue = 0'u64
        for at in index where rank(at) < hues do
            hue += 1
        return colors.series[hue]
    }

    // Draws the figures in a row from `left`, each its number over its label, and returns their bottom.
    private mtd paintFigures(painter: *Painter, left, top: f32, overview: const *Overview)->f32
    {
        let colors = .themeColors()
        let number = .theme().createDefaultFont(FigureSize, .Light)
        let label  = .theme().createDefaultFont(LabelSize)
        let texts  = texts()

        let count  = cast(u64, overview.sections.count)
        let values = [Viewer.groupThousands(count),
                      Viewer.groupThousands(overview.imports),
                      Format.toString("%{f1}", overview.entropy),
                      Viewer.groupThousands(overview.strings)]
        let labels = [count == 1 ? texts.word_Section : texts.word_Sections, texts.ui_Imports, texts.ui_Entropy, texts.ui_Strings]

        var x = left
        for index in values.count
        {
            painter.drawString(x, top, values[index], number, colors.text)
            painter.drawString(x, top + number.height, labels[index], label, colors.softText)
            let width = Math.max(Painter.measureString(values[index], number).width, Painter.measureString(labels[index], label).width)
            x += width + FigureGap
        }

        return top + number.height + label.height
    }

    // Draws the sections as one bar split in proportion to the bytes each stores, with its legend
    // under it, and returns the bottom of the legend.
    private mtd paintSections(painter: *Painter, left, right, top: f32, sections: const *Array'OverviewSection)->f32
    {
        let colors = .themeColors()
        let name   = .theme().createDefaultFont(LabelSize - 1)
        let share  = .theme().createDefaultFontFs(SmallMonoSize)

        var total = 0'u64
        for section in sections do
            total += section.size

        // The bar: each section a run as long as its share, a hairline of air between two.
        let width = right - left - cast(f32, sections.count - 1) * BarJoint
        var x     = left
        for section, index in sections
        {
            let run = width * cast(f32, section.size) / cast(f32, total)
            painter.fillRoundRect(Math.Rectangle{x, top, run, BarHeight}, 3, 3, .sectionColor(sections, index))
            x += run + BarJoint
        }

        // The legend: a dot in the section's colour, its name, and its share in mono.
        var y = top + BarHeight + LabelGap + 4
        x = left
        for section, index in sections
        {
            let percent = Format.toString("% %%", cast(u64, Math.round(cast(f32, section.size) * 100 / cast(f32, total))))
            let nameW   = Painter.measureString(section.name, name).width
            let shareW  = Painter.measureString(percent, share).width
            let itemW   = 2 * LegendDot + 6 + nameW + 4 + shareW
            if x > left and x + itemW > right
            {
                x = left
                y += name.height + 6
            }

            let center = y + name.height * 0.5
            painter.fillCircle(x + LegendDot, center, LegendDot, .sectionColor(sections, index))
            painter.drawString(x + 2 * LegendDot + 6, name.opticalLineTop(center), section.name, name, colors.softText)
            painter.drawString(x + 2 * LegendDot + 6 + nameW + 4, share.opticalLineTop(center), percent, share, colors.faintText)
            x += itemW + LegendGap
        }

        return y + name.height
    }

    // Draws one line per imported library from `top`, its first names and its count beside it, as
    // many as the page holds.
    private mtd paintImports(painter: *Painter, left, right, top: f32, libraries: const *Array'OverviewLibrary)
    {
        let colors  = .themeColors()
        let library = .theme().createDefaultFontFs(MonoSize, .Bold)
        let names   = .theme().createDefaultFont(LabelSize)
        let bottom  = .clientRect().bottom() - ImportPitch

        var y = top
        for entry, index in libraries
        {
            let center = y + ImportPitch * 0.5
            if y + ImportPitch > bottom and index + 1 < libraries.count
            {
                let rest = Format.toString(texts().ui_MoreLibraries, libraries.count - index)
                painter.drawString(left, names.opticalLineTop(center), rest, names, colors.faintText)
                return
            }

            var line: String
            for symbol, at in entry.symbols
            {
                if at do
                    line += ", "
                line += symbol[]
            }

            if entry.count > entry.symbols.count do
                line += Format.toString(" … %", entry.count)
            painter.drawString(left, library.opticalLineTop(center), entry.name, library, colors.text)
            painter.pushClippingRect(Math.Rectangle{left + NamesColumn, y, right - left - NamesColumn, ImportPitch})
            painter.drawString(left + NamesColumn, names.opticalLineTop(center), line, names, colors.softText)
            painter.popClippingRect()
            y += ImportPitch
        }
    }
}

impl IWnd for ReportPage
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .document do
            return

        let painter  = evt.paintContext.painter
        let colors   = .themeColors()
        let client   = .clientRect()
        let overview = &.document.report.overview
        let margin   = client.width >= WideWidth ? WideMargin : NarrowMargin
        let left     = client.x + margin
        let right    = client.right() - margin
        painter.setParams(.Antialiased)

        // What the file is: its name over the words of its identity and its size, in mono.
        let title = .theme().createDefaultFont(TitleSize, .Bold)
        let mono  = .theme().createDefaultFontFs(MonoSize)
        var y     = client.y + TopAir
        painter.drawString(left, y, .title, title, colors.text)
        y += title.height + 2

        var identity: String
        for word in overview.identity
        {
            identity += word[]
            identity += " · "
        }

        identity += StrConv.toDisplaySize(.document.image.fileSize)
        painter.drawString(left, y, identity, mono, colors.faintText)
        y += mono.height + BandGap

        y = .paintFigures(painter, left, y, overview) + BandGap

        if not overview.sections.isEmpty()
        {
            let label = .theme().createDefaultFont(.themeMetrics().sectionLabel_FontSize)
            SectionLabel.paint(me, painter, Math.Rectangle{left, y, right - left, label.height}, texts().shr_Sections)
            y = .paintSections(painter, left, right, y + label.height + LabelGap, &overview.sections) + BandGap
        }

        if not overview.libraries.isEmpty()
        {
            let label = .theme().createDefaultFont(.themeMetrics().sectionLabel_FontSize)
            SectionLabel.paint(me, painter, Math.Rectangle{left, y, right - left, label.height}, texts().shr_Imports)
            .paintImports(painter, left, right, y + label.height + 9, &overview.libraries)
        }
    }
}
