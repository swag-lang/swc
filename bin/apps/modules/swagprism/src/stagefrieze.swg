#global internal

using Core, Gui, Pixel

/*
The steps of the inspected function as a frieze of dots, one per printing that changed the code.

The steps behind the chosen one are Arc dots on an Arc thread, the chosen one a larger Arc dot in a
halo of the selection ground, and the ones ahead faint dots on a hairline. Under the frieze the
first and the last step are named in the faint ink at its ends, and the chosen one under its dot,
with what it did to the count in Arc. A click on a dot chooses its step; the window steps with the
arrow keys.
*/
struct StageFrieze
{
    using wnd: Wnd

    count:     u64
    current:   u64
    first:     String     // Name of the first step.
    last:      String     // Name of the last step.
    chosen:    String     // Name of the chosen step.
    change:    String     // What the chosen step did to the count, such as "−2 instructions".
    sigChosen: SigArray'func||(u64)
}

impl StageFrieze
{
    const Height       = 72.0
    const TrackY       = 14.0     // Centre of the dots, from the top.
    const NameY        = 45.0     // Centre of the names, from the top.
    const DotRadius    = 4.0
    const ChosenRadius = 7.0
    const HaloRadius   = 12.0
    const NameGap      = 8.0     // Air between the chosen name and what it did.

    func create(parent: *Wnd, id: WndId? = null)->*StageFrieze
    {
        with let result = Wnd.create'StageFrieze(parent, null, {}, id)
        {
            .backgroundStyle = .Transparent
        }

        return result
    }

    // Shows `count` steps with `current` chosen, the names of the ends and of the chosen one, and
    // what the chosen one did.
    mtd set(count, current: u64, first, last, chosen, change: string)
    {
        .count   = count
        .current = current
        .first   = first
        .last    = last
        .chosen  = chosen
        .change  = change
        .invalidate()
    }

    // Returns the centre of the dot of step `index`.
    mtd dotX(index: u64)->f32
    {
        let width = .clientRect().width
        if .count < 2 do
            return width * 0.5
        return HaloRadius + cast(f32, index) * (width - 2 * HaloRadius) / cast(f32, .count - 1)
    }

    private mtd nameFont()->*Font   => .theme().createDefaultFont(.themeMetrics().hintLine_FontSize)
    private mtd chosenFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize + 1, .Bold)
    private mtd changeFont()->*Font => .theme().createDefaultFontFs(.themeMetrics().hintLine_FontSize)
}

impl IWnd for StageFrieze
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if .count == 0 do
            return

        let painter  = evt.paintContext.painter
        let colors   = .themeColors()
        let hairline = .themeMetrics().separator_HairlineSize
        let width    = .clientRect().width
        painter.setParams(.Antialiased)

        // The thread: Arc up to the chosen step, a hairline after it.
        let chosenX = .dotX(.current)
        painter.drawLine(.dotX(0), TrackY, chosenX, TrackY, colors.arc, 1.5)
        painter.drawLine(chosenX, TrackY, .dotX(.count - 1), TrackY, colors.line, hairline)
        for index in .count where index != .current do
            painter.fillCircle(.dotX(index), TrackY, DotRadius, index < .current ? colors.arc : colors.line)
        painter.fillCircle(chosenX, TrackY, HaloRadius, colors.selection)
        painter.fillCircle(chosenX, TrackY, ChosenRadius, colors.arc)

        // The chosen name under its dot, kept inside the frieze; an end name it would cover gives way.
        let nameFont    = .nameFont()
        let chosenFont  = .chosenFont()
        let changeFont  = .changeFont()
        let chosenWidth = Painter.measureString(.chosen, chosenFont).width
        let changeWidth = .change.isEmpty() ? 0'f32 : NameGap + Painter.measureString(.change, changeFont).width
        let groupWidth  = chosenWidth + changeWidth
        let groupLeft   = Math.clamp(chosenX - groupWidth * 0.5, 0'f32, Math.max(0'f32, width - groupWidth))
        painter.drawString(groupLeft, chosenFont.opticalLineTop(NameY), .chosen, chosenFont, colors.text)
        if not .change.isEmpty() do
            painter.drawString(groupLeft + chosenWidth + NameGap, changeFont.opticalLineTop(NameY), .change, changeFont, colors.arc)

        let firstWidth = Painter.measureString(.first, nameFont).width
        if .current != 0 and firstWidth + NameGap * 2 < groupLeft do
            painter.drawString(0, nameFont.opticalLineTop(NameY), .first, nameFont, colors.faintText)
        let lastWidth = Painter.measureString(.last, nameFont).width
        if .current != .count - 1 and groupLeft + groupWidth + NameGap * 2 < width - lastWidth do
            painter.drawString(width - lastWidth, nameFont.opticalLineTop(NameY), .last, nameFont, colors.faintText)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed or evt.button != .Left or .count == 0
        {
            evt.accepted = false
            return
        }

        // The nearest dot answers a click anywhere on the frieze.
        let x       = .surfaceToLocal(evt.surfacePos).x
        var nearest = 0'u64
        for index in .count where Math.abs(.dotX(index) - x) < Math.abs(.dotX(nearest) - x) do
            nearest = index
        .sigChosen.call(nearest)
    }
}
