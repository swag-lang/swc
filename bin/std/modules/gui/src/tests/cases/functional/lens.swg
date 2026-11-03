#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

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
    Swag.assert(theme.checked and not lens.results.sections[1]!.entries[1].checked)

    // A command that cannot run says why in its detail.
    let disabled = lens.results.sections[1]!.entries[1]
    Swag.assert(disabled.disabled and disabled.detail == "Nothing selected" and not disabled.monoDetail)

    // A more precise command precedes a source registered first. A scope keeps navigation local.
    Swag.assert(lens.chosenEntry()!.title == "Center Theme")
    lens.setQuery(":center")
    Swag.assert(lens.chosenEntry()!.title == "if not .centerGroup do")
    host.keyPress(.Down)
    Swag.assert(lens.chosenEntry()!.title == "let group = .centerGroup")
    host.keyPress(.Down)
    Swag.assert(lens.chosenEntry()!.title == "elif .fillCenterGroup do")
    host.keyPress(.Up)
    Swag.assert(lens.chosenEntry()!.title == "let group = .centerGroup")

    let nothing = "zzz"
    lens.setQuery(nothing)
    Swag.assert(lens.rows.isEmpty() and lens.chosenEntry() == null)
}
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
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addRestSource(func(results) { results.addSection("Selection").addEntry("Duplicate") })
    lens.open()
    Swag.assert(lens.results.sections.count == 1)

    host.click(lensFooterActionPosition(lens))
    Swag.assert(lens.query() == ">" and lens.isOpen())
    Swag.assert(lens.results.sections.count == 2 and lens.chosenEntry()!.id == LensOpen)

    lens.setQuery("center")
    host.click(lensFooterActionPosition(lens))
    Swag.assert(lens.query() == ">center" and lens.chosenEntry()!.id == LensTheme)
    Swag.assert(host.app.keyboardFocusWnd == &lens.input.wnd)
}
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
#test
{
    let words = Lens.match("  image   save ", "Save as Image…")
    Swag.assert(words.matched and words.spans.count == 2)
    Swag.assert(words.spans[0].start == 0 and words.spans[1].start == 8)
    Swag.assert(not Lens.match("save save", "Save as Image…").matched)
    let accent = Lens.match("ete", "Été")
    Swag.assert(accent.matched and accent.spans[0].start == 0 and accent.spans[0].count == 5)
    let decomposed = Lens.match("ete", "E\u0301te\u0301")
    Swag.assert(decomposed.matched and decomposed.spans[0].count == 7)
    Swag.assert(Lens.match("  \t ", "Save").matched)
    for query in ["captuer", "capturre", "cature", "capxure"] do
        Swag.assert(Lens.match(query, "Capture Area", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("captuer", "Capture").matched)
    Swag.assert(not Lens.match("caxtuer", "Capture Area", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("svae", "Save", tolerateTypos: false).matched)
    Swag.assert(not Lens.match("cat", "Cut", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("2025", "2026", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("c:/svae", "c:/save", tolerateTypos: true).matched)
    Swag.assert(Lens.match("capture", "Capture Area").score > Lens.match("captuer", "Capture Area", tolerateTypos: true).score)

    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.open("svae")
    Swag.assert(lens.chosenEntry()!.id == LensSave)
    lens.setQuery("image save")
    Swag.assert(lens.chosenEntry()!.id == LensSave)
}
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
#test
{
    let initials = Lens.match("cla", "Capture Last Area")
    Swag.assert(initials.matched and initials.spans.count == 3)
    Swag.assert(initials.spans[1].start == 8 and initials.spans[2].start == 13)
    Swag.assert(initials.score < Lens.match("last", "Capture Last Area").score)
    Swag.assert(initials.score > Lens.match("cpa", "Capture Last Area").score)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addCommands("Capture", [LensCapture])
    lens.addCommands("Tools", [LensArrow])

    lens.open("arr")
    Swag.assert(lens.chosenEntry()!.title == "Arrow")
    for row in lens.rows do
        Swag.assert(row.entry == Swag.U64.Max or row.section.entries[row.entry].title != "Capture Area")

    lens.setQuery("center")
    Swag.assert(lens.rows[0].section.label == "View")
    Swag.assert(lens.chosenEntry()!.title == "Center Theme")
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addRestSource(func(results)
    {
        let section = results.addSection("Selection")
        section.addEntry("Duplicate")
    })

    lens.open()
    Swag.assert(lens.rows.count == 2 and lens.rows[0].section.label == "Selection")

    lens.setQuery("save")
    Swag.assert(lens.chosenEntry()!.title == "Save as Image…")
    lens.runChosen()
    Swag.assert(not lens.isOpen())

    lens.open()
    var labels: Array'String
    for row in lens.rows where row.entry == Swag.U64.Max do
        labels.add(row.section.label)
    Swag.assert(labels.count == 2 and labels[0] == "Selection" and labels[1] == strings().lens_Recent)

    lens.setQuery("x")
    host.keyPress(.Escape)
    Swag.assert(lens.isOpen() and lens.query().count == 0)
    host.keyPress(.Escape)
    Swag.assert(not lens.isOpen())
}
#test
{
    var chosen = Swag.U64.Max
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addRestSource(func(results)
    {
        results.addSection("Selection").addEntry("Duplicate")
    })
    lens.addRestSource(func|chosen = &chosen|(results) { addViewAsSection(results, chosen) })

    lens.open()
    Swag.assert(lens.inlineChoices.count == 1)
    Swag.assert(lens.inlineChoices[0].combo.isVisible())
    Swag.assert(lens.inlineChoices[0].combo.position.height > 0)
    Swag.assert(lens.rows.count == 4 and lens.rows[3].entry == Lens.InlineRow)
    Swag.assert(lens.chosenEntry()!.title == "Duplicate")
    host.keyPress(.Down)
    Swag.assert(lens.chosen == 3 and lens.chosenEntry()!.title == "Plain Text")
    host.keyPress(.Right)
    Swag.assert(lens.chosenEntry()!.title == "Binary")
    host.keyPress(.Right)
    Swag.assert(lens.chosenEntry()!.title == "Binary")
    host.keyPress(.Left)
    host.keyPress(.Left)
    Swag.assert(lens.chosenEntry()!.title == "Code")
    host.keyPress(.Up)
    Swag.assert(lens.chosenEntry()!.title == "Duplicate")

    lens.setQuery("ab")
    lens.input.setSelection(2, 2)
    host.keyPress(.Left)
    Swag.assert(lens.input.selEnd == 1)
    lens.setQuery("")

    // Reached again, the row starts on the choice in force.
    host.keyPress(.Down)
    host.keyPress(.Right)
    host.keyPress(.Return)
    Swag.assert(not lens.isOpen() and chosen == 3)

    // Typed into, the row starts on the segment the query answers best.
    lens.addSource(.None, func|chosen = &chosen|(results) { addViewAsSection(results, chosen) })
    lens.open()
    lens.setQuery("binary")
    Swag.assert(lens.chosenEntry()!.title == "Binary")
}
#test
{
    var chosen = Swag.U64.Max
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let lens = lensSetup(&host)
    lens.addRestSource(func(results) { results.addSection("Selection").addEntry("Duplicate") })
    lens.addRestSource(func|chosen = &chosen|(results) { addViewAsSection(results, chosen) })
    lens.open()

    let combo = lens.inlineChoices[0].combo
    var point = combo.localToSurface(Math.Point{combo.position.width - 20, combo.position.height * 0.5})
    combo.surface!.surfaceToScreen(&point)
    host.click(point)

    Swag.assert(not lens.isOpen() and chosen == 3)
}
#test
{
    var showChoices = true
    var chosen      = Swag.U64.Max
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let lens = lensSetup(&host)
    lens.addRestSource(func(results) { results.addSection("Selection").addEntry("Duplicate") })
    lens.addRestSource(func|showChoices = &showChoices, chosen = &chosen|(results)
    {
        if showChoices[] do
            addViewAsSection(results, chosen)
    })

    lens.open()
    Swag.assert(lens.inlineChoices.count == 1 and lens.inlineChoices[0].combo.isVisible())
    showChoices = false
    lens.refresh()
    Swag.assert(lens.inlineChoices[0].row == Swag.U64.Max and not lens.inlineChoices[0].combo.isVisible())
}
#test
{
    var posted: Array'String
    var on = true
    var host:   Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    host.root.hookOnEvent = func|posted = &posted, on = &on|(wnd, evt)->bool
    {
        if evt is CommandStateEvent as state where state.kind == .Compute and state.id == LensTheme
        {
            state.name    = "Center Theme"
            state.checked = on[]
            state.updatedFields.add(.Name | .Checked)
            state.accepted = true
            return true
        }

        if lensCommandState(wnd, evt) do
            return true
        if evt is CommandEvent as cmd
        {
            posted.add(cmd.id)
            if cmd.id == LensTheme do
                on[] = not on[]
            cmd.accepted = true
            return true
        }

        return false
    }

    lens.open(">center")
    let theme = unwrap lens.chosenEntry()
    Swag.assert(theme.title == "Center Theme" and theme.checkable and theme.checked)

    host.keyPress(.Return, .Control)
    Swag.assert(lens.isOpen() and posted.count == 1 and not on)
    Swag.assert(lens.chosenEntry()!.title == "Center Theme" and not lens.chosenEntry()!.checked)

    host.keyPress(.Return, .Control)
    Swag.assert(lens.isOpen() and posted.count == 2 and on and lens.chosenEntry()!.checked)

    // A command that is no setting is not checkable; Enter runs it and closes.
    lens.setQuery(">save")
    Swag.assert(not lens.chosenEntry()!.checkable)
    host.keyPress(.Return)
    Swag.assert(not lens.isOpen() and posted.count == 3 and posted[2] == LensSave)
}
#test
{
    for query in ["svae image", "image svae", "savve image", "saxe image"]
    {
        let found = Lens.match(query, "Save as Image…", tolerateTypos: true)
        Swag.assert(found.matched and found.spans.count == 2)
        Swag.assert(found.spans[0].start == 0 and found.spans[1].start == 8)
        Swag.assert(found.score < Lens.match("image save", "Save as Image…").score)
    }

    Swag.assert(Lens.match("captre area", "Capture Area", tolerateTypos: true).matched)
    Swag.assert(Lens.match("captuer région", "Capturer une région", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("svae iamge", "Save as Image…", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("svae svae", "Save as Image…", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("svae 2025", "Save 2026", tolerateTypos: true).matched)
    Swag.assert(not Lens.match("svae/image", "save/image", tolerateTypos: true).matched)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    lens.addCommand("Capture", LensCapture, func()->string => strings().lens_Files == "fichiers" ? "copie écran;image" : "screen grab;image")
    lens.open("screen grab")
    Swag.assert(lens.chosenEntry()!.id == LensCapture and lens.chosenEntry()!.spans.isEmpty())
    lens.setQuery("image")
    Swag.assert(lens.chosenEntry()!.id == LensSave)
    expect host.app.setLanguage("fr")
    lens.setQuery("copie ecran")
    Swag.assert(lens.chosenEntry()!.id == LensCapture and lens.chosenEntry()!.spans.isEmpty())
    lens.setQuery("screen grab")
    Swag.assert(lens.chosenEntry() == null)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addCommand("Capture", LensCapture, func()->string => "center disabld")
    lens.open("center disabled")
    Swag.assert(lens.chosenEntry()!.id == LensCapture)
    lens.setQuery("File")
    Swag.assert(lens.chosenEntry()!.id == LensOpen)
    lens.setQuery("Fil")
    for section in lens.results.sections
    {
        for entry in section!.entries do
            Swag.assert(entry.id != LensOpen and entry.id != LensSave)
    }
}
