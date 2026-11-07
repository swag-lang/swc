#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A whole occurrence answers better than characters found in order, and better again at the
// start of a word; the runs it matched are reported in bytes.
#test
{
    let whole = Lens.match("center", "if not .centerGroup do")
    Swag.require(whole.matched and whole.spans.count == 1)
    Swag.require(whole.spans[0].start == 8 and whole.spans[0].count == 6)

    let hump = Lens.match("group", "centerGroup")
    Swag.require(hump.matched and hump.spans[0].start == 6)

    let inside = Lens.match("roup", "centerGroup")
    Swag.require(inside.matched and inside.score < hump.score)

    let scattered = Lens.match("cgr", "centerGroup")
    Swag.require(scattered.matched and scattered.spans.count == 2 and scattered.score < inside.score)
    Swag.require(scattered.spans[0].start == 0 and
                 scattered.spans[1].start == 6 and
                 scattered.spans[1].count == 2)

    Swag.require(not Lens.match("xyz", "centerGroup").matched)
    Swag.require(not Lens.match("centerGroupLonger", "centerGroup").matched)

    let empty = Lens.match("", "anything")
    Swag.require(empty.matched and empty.score == 0 and empty.spans.isEmpty())

    // Case is folded across the whole of Unicode, and the bytes of a wide character are counted.
    let accented = Lens.match("ÉTÉ", "un été chaud")
    Swag.require(accented.matched and accented.spans[0].start == 3 and accented.spans[0].count == 5)
}

// The first character of a query selects the sources that answer it.
#test
{
    let line = Lens.splitPrefix(":42")
    Swag.require(line.prefix == .Line and line.rest == "42")
    Swag.require(Lens.splitPrefix("/main").prefix == .File)
    Swag.require(Lens.splitPrefix(">save").prefix == .Action)
    let plain = Lens.splitPrefix("center")
    Swag.require(plain.prefix == .None and plain.rest == "center")
    Swag.require(Lens.prefixText(.Action) == ">")
}

// The optional application menu is derived from command registrations, including their
// visibility, placement and exclusions; the lens retains every registered command.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    host.root.hookOnEvent = &lensCommandState

    with let lens = Lens.View.create(&host.root)
    {
        .addCommand("File", LensOpen)
        .addCommand("File", LensSave, menuGroup: func()->string => "Export")
        .addCommand("File", LensHidden)
        .addCommand("View", LensTheme, inMenu: false)
        .addCommand("View", LensDisabled)
    }

    let menu = lens.createCommandMenu()
    Swag.require(menu.items.count == 3)
    Swag.require(menu.items[0]!.name.raw == "File")
    Swag.require(menu.items[1]!.separator)

    let file = menu.items[0]!.popup
    Swag.require(file.items.count == 3 and file.items[0]!.id == LensOpen)
    Swag.require(file.items[1]!.separator and file.items[2]!.name.raw == "Export")
    let export = file.items[2]!.popup
    Swag.require(export.items.count == 1 and export.items[0]!.id == LensSave)

    menu.updateState()
    Swag.require(menu.items[2]!.id == LensDisabled and menu.items[2]!.name.raw == "Center Disabled" and menu.items[2]!.disabled)

    lens.open(">")
    var foundExcluded: bool
    for section in lens.results.sections where section do
        for entry in section.entries where entry.id == LensTheme do
            foundExcluded = true
    Swag.require(foundExcluded)
    lens.close()
}

// A change of section between direct commands creates one separator without a menu-only entry.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    host.root.hookOnEvent = &lensCommandState

    with let lens = Lens.View.create(&host.root)
    {
        .addCommand("File", LensOpen)
        .addCommand("File", LensSave, menuSection: 1)
    }

    let menu = lens.createCommandMenu()
    Swag.require(menu.items.count == 1)
    let file = menu.items[0]!.popup
    Swag.require(file.items.count == 3)
    Swag.require(file.items[0]!.id == LensOpen and file.items[1]!.separator and file.items[2]!.id == LensSave)
}

// Opening the lens shows every source and the commands grouped by family; a hidden command is
// left out and a disabled one cannot be chosen. Typing narrows the rows and marks what matched.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)

    lens.open()
    Swag.require(lens.isOpen())
    Swag.require(lens.results.sections.count == 3)
    Swag.require(lens.results.sections[0]!.label == "In this file" and lens.results.sections[0]!.count == 5)
    Swag.require(lens.results.sections[1]!.label == "File" and lens.results.sections[1]!.entries.count == 2)
    Swag.require(lens.results.sections[1]!.entries[1].detail == "Ctrl S")

    lens.setQuery("center")
    Swag.require(lens.results.sections.count == 2)
    Swag.require(lens.results.sections[0]!.entries.count == 3)
    Swag.require(lens.results.sections[1]!.label == "View" and lens.results.sections[1]!.entries.count == 2)
    let theme = lens.results.sections[1]!.entries[0]
    Swag.require(theme.title == "Center Theme" and theme.spans.count == 1 and theme.spans[0].count == 6)
    Swag.require(theme.checked and not lens.results.sections[1]!.entries[1].checked)

    // A command that cannot run says why in its detail.
    let disabled = lens.results.sections[1]!.entries[1]
    Swag.require(disabled.disabled and disabled.detail == "Nothing selected" and not disabled.monoDetail)

    // A more precise command precedes a source registered first. A scope keeps navigation local.
    Swag.require(lens.chosenEntry()!.title == "Center Theme")
    lens.setQuery(":center")
    Swag.require(lens.chosenEntry()!.title == "if not .centerGroup do")
    host.keyPress(.Down)
    Swag.require(lens.chosenEntry()!.title == "let group = .centerGroup")
    host.keyPress(.Down)
    Swag.require(lens.chosenEntry()!.title == "elif .fillCenterGroup do")
    host.keyPress(.Up)
    Swag.require(lens.chosenEntry()!.title == "let group = .centerGroup")

    let nothing = "zzz"
    lens.setQuery(nothing)
    Swag.require(lens.rows.isEmpty() and lens.chosenEntry() == null)
}

// A prefix keeps one kind of source: `>` the commands alone, `:` the lines alone.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.open(">")
    Swag.require(lens.results.prefix == .Action)
    Swag.require(lens.results.sections.count == 2 and lens.results.sections[0]!.label == "File")

    lens.setQuery(":center")
    Swag.require(lens.results.prefix == .Line and lens.results.query == "center")
    Swag.require(lens.results.sections.count == 1 and lens.results.sections[0]!.label == "In this file")
}

// The footer opens the complete command catalogue without typing, and preserves a query when
// narrowing it to actions.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addRestSource(func(results) { results.addSection("Selection").addEntry("Duplicate") })
    lens.open()
    Swag.require(lens.results.sections.count == 1)

    host.click(lensFooterActionPosition(lens))
    Swag.require(lens.query() == ">" and lens.isOpen())
    Swag.require(lens.results.sections.count == 2 and lens.chosenEntry()!.id == LensOpen)

    lens.setQuery("center")
    host.click(lensFooterActionPosition(lens))
    Swag.require(lens.query() == ">center" and lens.chosenEntry()!.id == LensTheme)
    Swag.require(host.app.keyboardFocusWnd == &lens.input.wnd)
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
    Swag.require(lens.chosenEntry()!.id == LensSave)
    Swag.require(host.app.keyboardFocusWnd == &lens.input.wnd)
    host.keyPress(.Return)
    Swag.require(not lens.isOpen())
    Swag.require(posted.count == 1 and posted[0] == LensSave)
    Swag.require(host.app.keyboardFocusWnd == &field.wnd)

    lens.open()
    host.keyPress(.Escape)
    Swag.require(not lens.isOpen() and posted.count == 1)
    Swag.require(host.app.keyboardFocusWnd == &field.wnd)
}

// A lens opened from neutral ground closes back to neutral ground. Hiding its focused input must
// not seed the first keyboard control behind it and draw a focus ring the reader never requested.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    discard PushButton.create(&host.root, "First action", {20, 20, 120, 32})
    let lens = lensSetup(&host)

    host.surface.clearFocus()
    Swag.require(host.app.keyboardFocusWnd == null)
    lens.open()
    Swag.require(host.app.keyboardFocusWnd == &lens.input.wnd)
    host.keyPress(.Escape)
    Swag.require(not lens.isOpen())
    Swag.require(host.app.keyboardFocusWnd == null)
}

// Search accepts task words in either order, omitted accents, and bounded command misspellings.
#test
{
    let words = Lens.match("  image   save ", "Save as Image…")
    Swag.require(words.matched and words.spans.count == 2)
    Swag.require(words.spans[0].start == 0 and words.spans[1].start == 8)
    Swag.require(not Lens.match("save save", "Save as Image…").matched)
    let accent = Lens.match("ete", "Été")
    Swag.require(accent.matched and accent.spans[0].start == 0 and accent.spans[0].count == 5)
    let decomposed = Lens.match("ete", "E\u0301te\u0301")
    Swag.require(decomposed.matched and decomposed.spans[0].count == 7)
    Swag.require(Lens.match("  \t ", "Save").matched)
    for query in ["captuer", "capturre", "cature", "capxure"] do
        Swag.require(Lens.match(query, "Capture Area", tolerateTypos: true).matched)
    Swag.require(not Lens.match("captuer", "Capture").matched)
    Swag.require(not Lens.match("caxtuer", "Capture Area", tolerateTypos: true).matched)
    Swag.require(not Lens.match("svae", "Save", tolerateTypos: false).matched)
    Swag.require(not Lens.match("cat", "Cut", tolerateTypos: true).matched)
    Swag.require(not Lens.match("2025", "2026", tolerateTypos: true).matched)
    Swag.require(not Lens.match("c:/svae", "c:/save", tolerateTypos: true).matched)
    Swag.require(Lens.match("capture", "Capture Area").score > Lens.match("captuer", "Capture Area", tolerateTypos: true).score)

    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.open("svae")
    Swag.require(lens.chosenEntry()!.id == LensSave)
    lens.setQuery("image save")
    Swag.require(lens.chosenEntry()!.id == LensSave)
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
    Swag.require(lens.chosenEntry()!.title == "Panel capture")
    host.click({10, 590})
    Swag.require(not lens.isOpen() and ran == 0)

    lens.open("panel")
    lens.runChosen()
    Swag.require(not lens.isOpen() and ran == 1)
}

// The initials of the words answer between a whole occurrence and scattered letters.
#test
{
    let initials = Lens.match("cla", "Capture Last Area")
    Swag.require(initials.matched and initials.spans.count == 3)
    Swag.require(initials.spans[1].start == 8 and initials.spans[2].start == 13)
    Swag.require(initials.score < Lens.match("last", "Capture Last Area").score)
    Swag.require(initials.score > Lens.match("cpa", "Capture Last Area").score)
}

// The families of commands rank by their best command, and a command matched only by scattered
// letters is left out when another answers better; sources retain their internal row order.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addCommands("Capture", [LensCapture])
    lens.addCommands("Tools", [LensArrow])

    lens.open("arr")
    Swag.require(lens.chosenEntry()!.title == "Arrow")
    for row in lens.rows do
        Swag.require(row.entry == Swag.U64.Max or row.section.entries[row.entry].title != "Capture Area")

    lens.setQuery("center")
    Swag.require(lens.rows[0].section.label == "View")
    Swag.require(lens.chosenEntry()!.title == "Center Theme")
}

// At rest, a lens with a context offers it and the commands chosen last, not every command;
// Escape empties the query before it closes the lens.
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
    Swag.require(lens.rows.count == 2 and lens.rows[0].section.label == "Selection")

    lens.setQuery("save")
    Swag.require(lens.chosenEntry()!.title == "Save as Image…")
    lens.runChosen()
    Swag.require(not lens.isOpen())

    lens.open()
    var labels: Array'String
    for row in lens.rows where row.entry == Swag.U64.Max do
        labels.add(row.section.label)
    Swag.require(labels.count == 2 and labels[0] == "Selection" and labels[1] == strings().lens_Recent)

    lens.setQuery("x")
    host.keyPress(.Escape)
    Swag.require(lens.isOpen() and lens.query().count == 0)
    host.keyPress(.Escape)
    Swag.require(not lens.isOpen())
}

// An exclusive choice is one row of segments: the keys reach it on the one in force, move along
// it with Left and Right past what cannot be chosen, and Enter runs the segment they chose. On
// another row, Left and Right belong to the query.
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
    Swag.require(lens.inlineChoices.count == 1)
    Swag.require(lens.inlineChoices[0].combo.isVisible())
    Swag.require(lens.inlineChoices[0].combo.position.height > 0)
    Swag.require(lens.rows.count == 4 and lens.rows[3].entry == Lens.InlineRow)
    Swag.require(lens.chosenEntry()!.title == "Duplicate")
    host.keyPress(.Down)
    Swag.require(lens.chosen == 3 and lens.chosenEntry()!.title == "Plain Text")
    host.keyPress(.Right)
    Swag.require(lens.chosenEntry()!.title == "Binary")
    host.keyPress(.Right)
    Swag.require(lens.chosenEntry()!.title == "Binary")
    host.keyPress(.Left)
    host.keyPress(.Left)
    Swag.require(lens.chosenEntry()!.title == "Code")
    host.keyPress(.Up)
    Swag.require(lens.chosenEntry()!.title == "Duplicate")

    lens.setQuery("ab")
    lens.input.setSelection(2, 2)
    host.keyPress(.Left)
    Swag.require(lens.input.selEnd == 1)
    lens.setQuery("")

    // Reached again, the row starts on the choice in force.
    host.keyPress(.Down)
    host.keyPress(.Right)
    host.keyPress(.Return)
    Swag.require(not lens.isOpen() and chosen == 3)

    // Typed into, the row starts on the segment the query answers best.
    lens.addSource(.None, func|chosen = &chosen|(results) { addViewAsSection(results, chosen) })
    lens.open()
    lens.setQuery("binary")
    Swag.require(lens.chosenEntry()!.title == "Binary")
}

// A pointer click in the child ComboBox chooses and runs its segment.
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

    Swag.require(not lens.isOpen() and chosen == 3)
}

// A single matching segment still runs when it is already selected in the child control.
#test
{
    var chosen = Swag.U64.Max
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let lens = lensSetup(&host)
    lens.addSource(.None, func|chosen = &chosen|(results)
    {
        let section = results.addSection("View As")
        section.inline = true
        with let entry = section.addEntry("Binary")
        {
            .run = func|chosen|() { chosen[] = 3 }
        }
    })
    lens.open("binary")
    let combo = lens.inlineChoices[0].combo
    Swag.require(combo.items.count == 1 and combo.selectedIndex == 0)

    var point = combo.localToSurface(Math.Point{combo.position.width * 0.5, combo.position.height * 0.5})
    combo.surface!.surfaceToScreen(&point)
    host.click(point)

    Swag.require(not lens.isOpen() and chosen == 3)
}

// Refreshing from a populated inline section to none leaves its pooled child out of selection sync.
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
    Swag.require(lens.inlineChoices.count == 1 and lens.inlineChoices[0].combo.isVisible())
    showChoices = false
    lens.refresh()
    Swag.require(lens.inlineChoices[0].row == Swag.U64.Max and not lens.inlineChoices[0].combo.isVisible())
}

// Ctrl Enter runs the chosen setting and keeps the lens open on it, its state asked for again,
// so several settings can be flipped in a row; Enter still runs and closes.
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
    Swag.require(theme.title == "Center Theme" and theme.checkable and theme.checked)

    host.keyPress(.Return, .Control)
    Swag.require(lens.isOpen() and posted.count == 1 and not on)
    Swag.require(lens.chosenEntry()!.title == "Center Theme" and not lens.chosenEntry()!.checked)

    host.keyPress(.Return, .Control)
    Swag.require(lens.isOpen() and posted.count == 2 and on and lens.chosenEntry()!.checked)

    // A command that is no setting is not checkable; Enter runs it and closes.
    lens.setQuery(">save")
    Swag.require(not lens.chosenEntry()!.checkable)
    host.keyPress(.Return)
    Swag.require(not lens.isOpen() and posted.count == 3 and posted[2] == LensSave)
}

// One edit in a multiword task is recoverable; each other word must identify a distinct word.
#test
{
    for query in ["svae image", "image svae", "savve image", "saxe image"]
    {
        let found = Lens.match(query, "Save as Image…", tolerateTypos: true)
        Swag.require(found.matched and found.spans.count == 2)
        Swag.require(found.spans[0].start == 0 and found.spans[1].start == 8)
        Swag.require(found.score < Lens.match("image save", "Save as Image…").score)
    }

    Swag.require(Lens.match("captre area", "Capture Area", tolerateTypos: true).matched)
    Swag.require(Lens.match("captuer région", "Capturer une région", tolerateTypos: true).matched)
    Swag.require(not Lens.match("svae iamge", "Save as Image…", tolerateTypos: true).matched)
    Swag.require(not Lens.match("svae svae", "Save as Image…", tolerateTypos: true).matched)
    Swag.require(not Lens.match("svae 2025", "Save 2026", tolerateTypos: true).matched)
    Swag.require(not Lens.match("svae/image", "save/image", tolerateTypos: true).matched)
}

// Aliases follow the language at query time, preserve command identity, and rank below title words.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    lens.addCommand("Capture", LensCapture, func()->string => strings().lens_Files == "fichiers" ? "copie écran;image" : "screen grab;image")
    lens.open("screen grab")
    Swag.require(lens.chosenEntry()!.id == LensCapture and lens.chosenEntry()!.spans.isEmpty())
    lens.setQuery("image")
    Swag.require(lens.chosenEntry()!.id == LensSave)
    expect host.app.setLanguage("fr")
    lens.setQuery("copie ecran")
    Swag.require(lens.chosenEntry()!.id == LensCapture and lens.chosenEntry()!.spans.isEmpty())
    lens.setQuery("screen grab")
    Swag.require(lens.chosenEntry() == null)
}

// A disabled exact match stays visible without suppressing the usable approximate alternative.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let lens = lensSetup(&host)
    lens.addCommand("Capture", LensCapture, func()->string => "center disabld")
    lens.open("center disabled")
    Swag.require(lens.chosenEntry()!.id == LensCapture)
    lens.setQuery("File")
    Swag.require(lens.chosenEntry()!.id == LensOpen)
    lens.setQuery("Fil")
    for section in lens.results.sections
    {
        for entry in section!.entries do
            Swag.require(entry.id != LensOpen and entry.id != LensSave)
    }
}
