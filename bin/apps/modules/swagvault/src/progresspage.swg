using Core, Gui, Pixel

// The share of a long operation that is done, set as a huge figure with its percent sign beside it.
//
// It is the fact the reader came to the page for, so it is set large, and the sign is set smaller
// and fainter on the same baseline: the number is what is read.
struct ProgressFigure
{
    using wnd: Wnd

    percent: s32
}

impl ProgressFigure
{
    const NumberSize = 96'u32
    const SignSize   = 40'u32
    const SignGap    = 12'f32

    // Creates the figure in `parent`, at zero.
    func create(parent: *Wnd)->*ProgressFigure
    {
        let height      = parent.theme().createDefaultFont(NumberSize, .Light).height
        with let result = Wnd.create'ProgressFigure(parent, Math.Rectangle{0, 0, 0, Math.ceil(height)})
        {
            .backgroundStyle = .Transparent
        }

        return result
    }

    // Shows `percent`.
    mtd setPercent(percent: s32)
    {
        if .percent == percent do
            return
        .percent = percent
        .invalidate()
    }
}

impl IWnd for ProgressFigure
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let number  = .theme().createDefaultFont(NumberSize, .Light)
        let sign    = .theme().createDefaultFont(SignSize, .Light)
        let text    = Format.toString("%", .percent)

        let baseline = room.y + number.ascent
        painter.drawString(room.x, room.y, text, number, colors.text)
        let x = room.x + Painter.measureString(text, number).width + SignGap
        painter.drawString(x, baseline - sign.ascent, "%", sign, colors.faintText)
    }
}

// The page that follows a creation, a resize or a camouflage refresh while it runs.
//
// The container's name, the share done as a huge figure over an Arc line, what is being done
// beside a mono reading of how far and how long, a sentence saying why it takes this long, and
// the one way to stop it. Nothing else is on screen: the work is the page.
struct ProgressPage
{
    using wnd: Wnd

    late
    {
        window:   *MainWindow
        column:   *StackLayoutCtrl
        fileName: *Label
        figure:   *ProgressFigure
        bar:      *ProgressBar
        line:     *Wnd
        what:     *Label
        reading:  *Label
        help:     *Label
        stop:     *PushButton
    }
}

impl ProgressPage
{
    const BarHeight = 4'f32      // Height of the Arc line.
    const LineGap   = 16'f32     // Air between the figure, the line, the reading and the sentence.
    const StopGap   = 32'f32     // Air before the way to stop.

    // Creates the page in `window`, hidden.
    func create(window: *MainWindow)->*ProgressPage
    {
        with let result = Wnd.create'ProgressPage(window, "vault.progress")
        {
            .window          = window
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .hide()
        }

        result.column = createPageColumn(result)

        with result.fileName = Label.create(result.column, "", {}, null, .SecondaryText | .AutoHeight)
        {
            .setTextAlignment(.Left, .Top)
            .style.setFont(result.theme().createDefaultFont(15), .Regular)
        }

        with result.figure = ProgressFigure.create(result.column)
        {
            .margin.y = LineGap
        }

        with result.bar = ProgressBar.create(result.column, Math.Rectangle{0, 0, 0, BarHeight})
        {
            .margin.y = LineGap
        }

        with result.line = Wnd.create'Wnd(result.column, Math.Rectangle{0, 0, 0, NoticeLine.Height})
        {
            .backgroundStyle = .Transparent
            .margin.y        = LineGap
        }

        with result.what = Label.create(result.line, "", {}, null, .SecondaryText)
        {
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.reading = Label.create(result.line, "", {}, null, .SecondaryText)
        {
            .setTextAlignment(.Right, .OpticalCenter)
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .style.addStyleSheetColors("label_TextLight $label_TextFaint")
        }

        with result.help = Label.create(result.column, "", {}, null, .WordWrap | .SecondaryText | .AutoHeight)
        {
            .margin.y = LineGap * 2
            .setTextAlignment(.Left, .Top)
            .style.addStyleSheetColors("label_TextLight $label_TextFaint")
        }

        with result.stop = PushButton.create(result.column, appStrings().ui_StopCreating)
        {
            .layoutSpec.alignX = .Start
            .margin.y          = StopGap
            .sigPressed        += func|window|(_) { window.stopLongOperation() }
        }

        return result
    }

    // Shows the page for an operation on `path`: what it does, and why it takes this long.
    mtd begin(path: string, what, help, stop: string)
    {
        .fileName.setText(Path.fileName(path) orelse path)
        .what.setText(what)
        .help.setText(help)
        .stop.setText(stop)
        .stop.enable(true)
        .setProgress(0, 0, 0, "")
        .arrange()
    }

    // Shows how far the operation is: the share done, the bytes written of the bytes to write, and
    // how long is left when that can be said.
    mtd setProgress(ratio: f32, done, total: u64, left: string)
    {
        .figure.setPercent(cast(s32, Math.saturate(ratio) * 100))
        .bar.setValue(ratio)

        var reading: String
        if total
        {
            reading = Format.toString(appStrings().ui_ProgressOf, capacityText(done), capacityText(total))
            if left.count do
                reading = Format.toString("% · %", reading, left)
        }

        .reading.setText(reading)
        .arrangeLine()
    }

    // Places the column in the middle of the page.
    mtd arrange()
    {
        if .stop == null do
            return
        placePageColumn(me, .column, centred: true)
        .arrangeLine()
    }

    // Sets what is being done at the start of its line, and the mono reading at its end.
    mtd arrangeLine()
    {
        let room    = .line.clientRect()
        let reading = Math.min(room.width, Math.ceil(Painter.measureString(.reading.text(), unwrap .reading.font().regular).width))
        .reading.arrange(Math.Rectangle{room.right() - reading, room.y, reading, room.height})
        .what.arrange(Math.Rectangle{room.x, room.y, Math.max(0, room.width - reading - LineGap), room.height})
    }
}

impl IWnd for ProgressPage
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .arrange()
    }
}
