#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

const LensOpen     = "test.lens.open"
const LensSave     = "test.lens.save"
const LensTheme    = "test.lens.theme"
const LensHidden   = "test.lens.hidden"
const LensDisabled = "test.lens.disabled"

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
        default:           return false
        }

        state.updatedFields.add(.Name)
        if state.id == LensSave
        {
            state.updatedFields.add(.Shortcut)
            state.shortcut = "Ctrl S"
        }

        if state.id == LensHidden
        {
            state.updatedFields.add(.Hidden)
            state.hidden = true
        }

        if state.id == LensDisabled
        {
            state.updatedFields.add(.Disabled)
            state.disabled = true
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

// A whole occurrence answers better than characters found in order, and better again at the
// start of a word; the runs it matched are reported in bytes.
#test
{
    let whole = Lens.match("center", "if not .centerGroup do")
    Swag.assert(whole.matched and whole.spans.count == 1)
    Swag.assert(whole.spans[0].start == 8 and whole.spans[0].count == 6)

    let hump = Lens.match("group", "centerGroup")
    Swag.assert(hump.matched and hump.spans[0].start == 6)

    let inside = Lens.match("roup", "centerGroup")
    Swag.assert(inside.matched and inside.score < hump.score)

    let scattered = Lens.match("cgr", "centerGroup")
    Swag.assert(scattered.matched and scattered.spans.count == 2 and scattered.score < inside.score)
    Swag.assert(scattered.spans[0].start == 0 and
                scattered.spans[1].start == 6 and
                scattered.spans[1].count == 2)

    Swag.assert(not Lens.match("xyz", "centerGroup").matched)
    Swag.assert(not Lens.match("centerGroupLonger", "centerGroup").matched)

    let empty = Lens.match("", "anything")
    Swag.assert(empty.matched and empty.score == 0 and empty.spans.isEmpty())

    // Case is folded across the whole of Unicode, and the bytes of a wide character are counted.
    let accented = Lens.match("ÉTÉ", "un été chaud")
    Swag.assert(accented.matched and accented.spans[0].start == 3 and accented.spans[0].count == 5)
}

// The first character of a query selects the sources that answer it.
#test
{
    let line = Lens.splitPrefix(":42")
    Swag.assert(line.prefix == .Line and line.rest == "42")
    Swag.assert(Lens.splitPrefix("/main").prefix == .File)
    Swag.assert(Lens.splitPrefix(">save").prefix == .Action)
    let plain = Lens.splitPrefix("center")
    Swag.assert(plain.prefix == .None and plain.rest == "center")
    Swag.assert(Lens.prefixText(.Action) == ">")
}

// Opening the lens shows every source and the commands grouped by family; a hidden command is
// left out and a disabled one cannot be chosen. Typing narrows the rows and marks what matched.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)

    lens.open()
    Swag.assert(lens.isOpen())
    Swag.assert(lens.results.sections.count == 3)
    Swag.assert(lens.results.sections[0]!.label == "In this file" and lens.results.sections[0]!.count == 5)
    Swag.assert(lens.results.sections[1]!.label == "File" and lens.results.sections[1]!.entries.count == 2)
    Swag.assert(lens.results.sections[1]!.entries[1].detail == "Ctrl S")

    lens.setQuery("center")
    Swag.assert(lens.results.sections.count == 2)
    Swag.assert(lens.results.sections[0]!.entries.count == 3)
    Swag.assert(lens.results.sections[1]!.label == "View" and lens.results.sections[1]!.entries.count == 2)
    let theme = lens.results.sections[1]!.entries[0]
    Swag.assert(theme.title == "Center Theme" and theme.spans.count == 1 and theme.spans[0].count == 6)

    // The first row is chosen, the keys move the choice over the section labels, and the
    // disabled command is never chosen.
    Swag.assert(lens.chosenEntry()!.title == "if not .centerGroup do")
    host.keyPress(.Down)
    Swag.assert(lens.chosenEntry()!.title == "let group = .centerGroup")
    for 5 do
        host.keyPress(.Down)
    Swag.assert(lens.chosenEntry()!.title == "Center Theme")
    host.keyPress(.Up)
    Swag.assert(lens.chosenEntry()!.title == "elif .fillCenterGroup do")

    let nothing = "zzz"
    lens.setQuery(nothing)
    Swag.assert(lens.rows.isEmpty() and lens.chosenEntry() == null)
}

// A prefix keeps one kind of source: `>` the commands alone, `:` the lines alone.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.open(">")
    Swag.assert(lens.results.prefix == .Action)
    Swag.assert(lens.results.sections.count == 2 and lens.results.sections[0]!.label == "File")

    lens.setQuery(":center")
    Swag.assert(lens.results.prefix == .Line and lens.results.query == "center")
    Swag.assert(lens.results.sections.count == 1 and lens.results.sections[0]!.label == "In this file")
}

// Enter closes the lens and posts the chosen command; Escape closes it and gives the keyboard back.
#test
{
    var posted: Array'String
    var host:   Testing.HeadlessHost
    host.setup(800, 600)
    let lens       = lensSetup(&host)
    with let field = EditBox.create(&host.root, "", {20, 20, 200, 32})
    {
        .setFocus()
    }

    host.root.hookOnEvent = func|posted = &posted|(wnd, evt)->bool
    {
        if lensCommandState(wnd, evt) do
            return true
        if evt is CommandEvent as cmd
        {
            posted.add(cmd.id)
            cmd.accepted = true
            return true
        }

        return false
    }

    lens.open(">save")
    Swag.assert(lens.chosenEntry()!.id == LensSave)
    Swag.assert(host.app.keyboardFocusWnd == &lens.input.wnd)
    host.keyPress(.Return)
    Swag.assert(not lens.isOpen())
    Swag.assert(posted.count == 1 and posted[0] == LensSave)
    Swag.assert(host.app.keyboardFocusWnd == &field.wnd)

    lens.open()
    host.keyPress(.Escape)
    Swag.assert(not lens.isOpen() and posted.count == 1)
    Swag.assert(host.app.keyboardFocusWnd == &field.wnd)
}

// A click outside the lens closes it without running anything; a row with an action runs it.
#test
{
    var ran = 0
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addSource(.None, func|ran = &ran|(results)
    {
        with let entry = results.addSection("Recent").addEntry("Panel capture")
        {
            .run = func|ran|() { ran[] += 1 }
        }
    })

    lens.open("panel")
    Swag.assert(lens.chosenEntry()!.title == "Panel capture")
    host.click({10, 590})
    Swag.assert(not lens.isOpen() and ran == 0)

    lens.open("panel")
    lens.runChosen()
    Swag.assert(not lens.isOpen() and ran == 1)
}

// The lens over a document, with lines, a command family and the keys at its foot, in Encre and
// in Papier.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
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
}
