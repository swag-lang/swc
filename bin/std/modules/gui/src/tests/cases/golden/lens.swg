#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

const LensOpen     = "test.lens.open"
const LensSave     = "test.lens.save"
const LensTheme    = "test.lens.theme"
const LensHidden   = "test.lens.hidden"
const LensDisabled = "test.lens.disabled"
const LensCapture  = "test.lens.capture"
const LensArrow    = "test.lens.arrow"

// The lines of a small document a source answers from.
const LensLines: [5] string = ["if not .centerGroup do", "let group = .centerGroup", "return", "elif .fillCenterGroup do", "var width: f32"]

// Answers the command state of the test commands the way an application's actions do.
func lensCommandState(_: *Wnd, evt: IEvent)->bool
{
    if evt is CommandStateEvent as state where state.kind == .Compute
    {
        switch state.id
        {
        case LensOpen:     state.name = "Open…"
        case LensSave:     state.name = "Save as Image…"
        case LensTheme:    state.name = "Center Theme"
        case LensHidden:   state.name = "Hidden Command"
        case LensDisabled: state.name = "Center Disabled"
        case LensCapture:  state.name = "Capture Area"
        case LensArrow:    state.name = "Arrow"
        default:           return false
        }

        state.updatedFields.add(.Name)
        if state.id == LensSave
        {
            state.updatedFields.add(.Shortcut)
            state.shortcut = "Ctrl S"
        }

        if state.id == LensTheme
        {
            state.updatedFields.add(.Checked)
            state.checked = true
        }

        if state.id == LensHidden
        {
            state.updatedFields.add(.Hidden)
            state.hidden = true
        }

        if state.id == LensDisabled
        {
            state.updatedFields.add(.Disabled | .Reason)
            state.disabled = true
            state.reason   = "Nothing selected"
        }

        state.accepted = true
        return true
    }

    return false
}

// Builds a lens over the host root, with commands in two families and a source of lines.
func lensSetup(host: *Testing.HeadlessHost)->*Lens.View
{
    host.root.backgroundStyle = .Window
    host.root.hookOnEvent     = &lensCommandState

    with let lens = Lens.View.create(&host.root)
    {
        .addCommands("File", [LensOpen, LensSave, LensHidden])
        .addCommands("View", [LensTheme, LensDisabled])
        .addSource(.Line, func(results)
        {
            var section: *Lens.Section?
            for line, index in LensLines
            {
                if not Lens.match(results.query, line).matched do
                    continue
                if not section do
                    section = results.addSection("In this file")
                with let entry = section.addEntry(line)
                {
                    .lead      = Format.toString("%", index + 37)
                    .monoTitle = true
                }
            }

            if section do
                section.count = cast(u32, section.entries.count)
        })
    }

    return lens
}

func lensFooterActionPosition(lens: *Lens.View)->Math.Point
{
    let metrics = lens.themeMetrics()
    let bounds  = lens.clientRect()
    let top     = lens.input.position.y
    let width   = Math.min(metrics.lens_Width, bounds.width - 2 * metrics.floating_Inset)
    let last    = lens.rows.back()
    let content = last.top + last.height + metrics.lens_RowInset
    let fixed   = metrics.lens_InputHeight + metrics.lens_FooterHeight + 2 * metrics.separator_HairlineSize
    let room    = Math.max(Math.min(bounds.height * metrics.lens_MaxHeightRatio, bounds.height - metrics.floating_Inset - top), fixed)
    let height  = Math.min(fixed + content, room)
    return {bounds.horzCenter() + width * 0.5 - metrics.lens_TextInset - metrics.keycap_Padding,
            top + height - metrics.lens_FooterHeight * 0.5}
}

// A whole occurrence answers better than characters found in order, and better again at the
// start of a word; the runs it matched are reported in bytes.

// The first character of a query selects the sources that answer it.

// Opening the lens shows every source and the commands grouped by family; a hidden command is
// left out and a disabled one cannot be chosen. Typing narrows the rows and marks what matched.

// A prefix keeps one kind of source: `>` the commands alone, `:` the lines alone.

// The footer opens the complete command catalogue without typing, and preserves a query when
// narrowing it to actions.

// French source links remain legible beside a checkable result in a narrow lens.
#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    host.setup(480, 560)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    expect host.app.setLanguage("fr")
    let lens = lensSetup(&host)
    lens.addSource(.File, func(_) {})
    lens.open("center")
    Swag.assert(lens.chosenEntry()!.checked)
    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, light ? "lens.narrow.fr.paper" : "lens.narrow.fr.ink")
    host.click(lensFooterActionPosition(lens))
    Swag.assert(lens.results.prefix == .Action and lens.results.query == "center")
}

// Enter closes the lens and posts the chosen command; Escape closes it and gives the keyboard back.

// Search accepts task words in either order, omitted accents, and bounded command misspellings.

// A click outside the lens closes it without running anything; a row with an action runs it.

// The lens over a document, with lines, a command family and the keys at its foot, in Papier.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    with let document = Label.create(&host.root, "impl ViewerActionBar\n{\n    func create(parent: *Wnd)->*ViewerActionBar\n    {\n        with let result = Wnd.create'ViewerActionBar(parent)\n    }\n}", {120, 60, 600, 400})
    {
        .style.setFont(host.theme.createDefaultFontFamilyFs(14))
        .setTextAlignment(.Left, .Top)
    }

    let lens = lensSetup(&host)
    lens.open("center")
    host.keyPress(.Down)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "lens.paper" : "lens.ink")
}

// The initials of the words answer between a whole occurrence and scattered letters.

// The families of commands rank by their best command, and a command matched only by scattered
// letters is left out when another answers better; sources retain their internal row order.

// At rest, a lens with a context offers it and the commands chosen last, not every command;
// Escape empties the query before it closes the lens.

// Adds to `results` the ways of viewing a file as one row of segments, the second in force and
// the third unavailable; choosing one writes its index in `chosen`.
func addViewAsSection(results: *Lens.Results, chosen: *u64)
{
    let views = results.addSection("View As")
    views.inline = true
    for title, index in ["Code", "Plain Text", "Hexadecimal", "Binary"]
    {
        with let entry = views.addEntry(title)
        {
            .checked  = index == 1
            .disabled = index == 2
            .run      = func|chosen, index|() { chosen[] = index }
        }
    }
}

// An exclusive choice is one row of segments: the keys reach it on the one in force, move along
// it with Left and Right past what cannot be chosen, and Enter runs the segment they chose. On
// another row, Left and Right belong to the query.

// A pointer click in the child ComboBox chooses and runs its segment.

// Refreshing from a populated inline section to none leaves its pooled child out of selection sync.

// The lens with a row of segments, the keys on a segment beside the one in force, in Encre and
// in Papier.
#[Swag.TestTag("golden")]
#test
{
    let light  = false
    var chosen = Swag.U64.Max
    var host: Testing.HeadlessHost
    host.setup(800, 680)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    with let document = Label.create(&host.root, "impl ViewerActionBar\n{\n    func create(parent: *Wnd)->*ViewerActionBar\n    {\n        with let result = Wnd.create'ViewerActionBar(parent)\n    }\n}", {120, 60, 600, 400})
    {
        .style.setFont(host.theme.createDefaultFontFamilyFs(14))
        .setTextAlignment(.Left, .Top)
    }

    let lens = lensSetup(&host)
    lens.addSource(.None, func|chosen = &chosen|(results) { addViewAsSection(results, chosen) })
    lens.open("center")
    for 3 do
        host.keyPress(.Down)
    host.keyPress(.Left)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "lens.inline.paper" : "lens.inline.ink")
}

// Ctrl Enter runs the chosen setting and keeps the lens open on it, its state asked for again,
// so several settings can be flipped in a row; Enter still runs and closes.

// The foot teaches Ctrl Enter on a setting, in Encre.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    host.setup(800, 480)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    let lens = lensSetup(&host)
    lens.open(">")
    for 2 do
        host.keyPress(.Down)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "lens.stay.paper" : "lens.stay.ink")
}

// One edit in a multiword task is recoverable; each other word must identify a distinct word.

// Aliases follow the language at query time, preserve command identity, and rank below title words.

// Overflow has visible pointer controls; the last page is reachable and filtering resets it.
#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    host.setup(480, 560, 1.25)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    let lens = lensSetup(&host)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    lens.addSource(.Action, func(results)
    {
        if results.query.count != 0 do
            return
        let section = results.addSection("Results")
        for index in 20 do
            section.addEntry(Format.toString("Result %", index + 1))
    })
    lens.open(">")
    Swag.assert(lens.input.name.raw == strings().lens_Placeholder)
    Swag.assert(lens.nextPage.isVisible() and lens.nextPage.isEnabled())
    Swag.assert(lens.previousPage.isVisible() and not lens.previousPage.isEnabled())
    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, light ? "lens.overflow.paper" : "lens.overflow.ink")
    for 10
    {
        if not lens.nextPage.isEnabled() do
            break
        host.clickWnd(lens.nextPage)
    }

    Swag.assert(lens.scroll > 0 and lens.previousPage.isEnabled() and not lens.nextPage.isEnabled())
    Swag.assert(host.app.keyboardFocusWnd == &lens.input.wnd)
    host.clickWnd(lens.previousPage)
    Swag.assert(lens.nextPage.isEnabled())
    host.root.resize(800, 2400)
    lens.itf.onLayout()
    Swag.assert(lens.scroll == 0 and not lens.nextPage.isVisible())
    host.root.resize(480, 560)
    lens.itf.onLayout()
    lens.setQuery(">save")
    Swag.assert(lens.scroll == 0 and not lens.nextPage.isVisible())

    // The reset sits immediately before the available source links and keeps the typed words.
    let metrics     = lens.themeMetrics()
    let font        = lens.theme().createDefaultFont(metrics.hintLine_FontSize)
    let action      = lensFooterActionPosition(lens)
    let right       = lens.clientRect().horzCenter() + Math.min(metrics.lens_Width, lens.clientRect().width - 2 * metrics.floating_Inset) * 0.5 - metrics.lens_TextInset
    let actionWidth = keycapWidth(lens, ">") + metrics.hintLine_KeyGap + Painter.measureString(strings().lens_Actions, font).width
    let lineWidth   = keycapWidth(lens, ":") + metrics.hintLine_KeyGap + Painter.measureString(strings().lens_Line, font).width
    let allWidth    = Painter.measureString(strings().lens_All, font).width
    var reset       = Math.Point{right - actionWidth - lineWidth - 2 * metrics.hintLine_GroupGap - allWidth * 0.5, action.y}
    lens.surface!.surfaceToScreen(&reset)
    host.click(reset)
    Swag.assert(lens.query() == "save" and lens.results.prefix == .None)
}

// A disabled exact match stays visible without suppressing the usable approximate alternative.
