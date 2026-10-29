#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Opens the window on the dot product, both builds on their instructions, without compiling.
func testSetupInspectionWindow(host: *Testing.HeadlessHost, width = cast(f32, MainWindow.WindowWidth), height = cast(f32, MainWindow.WindowHeight))->*MainWindow
{
    let window = testSetupMainWindow(host, width, height)
    window.setLiveEdit(false)
    window.selectedExample = .Dot
    window.editor.setText(exampleSource(.Dot))
    window.panels[0].selectViewer(.Microcode)
    window.retranslate()
    return window
}

func microcode(window: *MainWindow, panel: u64)->*MicrocodeViewer => assume cast(*MicrocodeViewer, window.panels[panel].viewer!.window())

// Gives the builds the dot product as the compiler printed it: the main build at O2, the reference
// at O0.
func showDotFixtures(window: *MainWindow)
{
    showOutput(microcode(window, 0), fixture("micro.dot.o2.txt"))
    showOutput(microcode(window, 1), fixture("micro.dot.o0.txt"))
    window.refreshStatus()
}

// Reports whether the lens of `window` shows an entry titled `title`.
func lensHasEntry(window: *MainWindow, title: string)->bool
{
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where entry.title == title do
            return true
    }

    return false
}

// The window opens beside the source: one result, the reference build hidden, nothing on screen
// but the work, the menus above the columns and the hint line.
#test
{
    var host: Testing.HeadlessHost
    let window    = testSetupInspectionWindow(&host)
    let main      = microcode(window, 0)
    let reference = microcode(window, 1)
    Swag.assert(window.view == .Columns and window.editor.isVisible() and not window.panels[1].isVisible())
    Swag.assert(main != reference and not window.appearanceButton.isVisible())
    Swag.assert(main.stage == Pipeline.DefaultStage and reference.stage == Pipeline.DefaultStage)
    Swag.assert(window.panels[0].level == .O2 and window.panels[1].level == .O0)
    Swag.assert(window.panels[0].stageMenu.isVisible() and window.panels[0].stageMenu.name == appStrings().ui_StageFinal)
    Swag.assert(window.panels[0].optimMenu.name == "O2" and window.panels[0].viewMenu.name == appStrings().ui_Microcode)
    Swag.assert(main.listing.hint and not main.listing.isListing())
    Swag.assert(window.hintLine.hints.count == 2 and window.readingLine.reading.isEmpty())
    Swag.assert(window.exampleMenu.position.right() <= window.panels[0].position.x)
}

// The editor opens on the starter snippet, and that snippet is one the probe can inspect.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)

    let text = window.editor.text()
    Swag.assert(text.contains("\n{\n    var total = 0'f32\n    for i in a.count do\n        total += a[i] * b[i]\n    return total\n}"))
    let inspected = Pipeline.inspectedSource(text, Pipeline.Stages)
    Swag.assert(inspected.contains("#[Swag.PrintMicro"))
}

// A level change submits only that build and queues its next request independently.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    let main   = microcode(window, 0)
    let other  = microcode(window, 1)
    window.panels[0].setLevel(.O1)
    Swag.assert(main.job.running and main.job.request.inspect)
    Swag.assert(main.job.request.settings.optimization == .O1)
    Swag.assert(not other.job.running)
    window.panels[0].setLevel(.O0)
    Swag.assert(main.job.queued and main.job.request.settings.optimization == .O1)
    window.shutdown()
    Swag.assert(not main.job.running)
}

// One compilation prints every stage: choosing a stage or stepping through them compiles nothing,
// and each step reads what it changed.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    showDotFixtures(window)
    let main = microcode(window, 0)
    Swag.assert(main.shown()!.instructions == 16 and window.panels[0].listedInstructions() == 16)
    Swag.assert(main.listing.isListing() and window.readingLine.reading == Format.toString(appStrings().ui_Done, 38))

    main.setStage(2)
    Swag.assert(not main.job.running and main.shown()!.stage == 2)
    Swag.assert(window.panels[0].stageMenu.name == appStrings().ui_StageConstFold)

    window.applyView(.Stages)
    Swag.assert(main.layout == .Stages and main.frieze.isVisible() and not window.editor.isVisible())
    Swag.assert(main.frieze.count == main.inspection.steps.count and main.frieze.current == main.step)
    Swag.assert(window.hintLine.hints.count == 1)

    main.setStep(1)
    Swag.assert(main.previous() != null and main.listing.difference.removed + main.listing.difference.added != 0)
    Swag.assert(window.runCommand(PrismCommands.NextStage) and main.step == 2)
    main.listing.setFocus()
    host.keyPress(.Left)
    Swag.assert(main.step == 1)

    // Without the change, the listing is the step alone.
    Swag.assert(window.runCommand(PrismCommands.ShowChange) and not main.showChange.isChecked())
    for row in main.listing.rows do
        Swag.assert(row.mark == .Same)
    Swag.assert(not main.job.running)
}

// Beside another build, the reference stands at the left and the main build at the right, each
// headed by its count; the main build says what it gains, and its loop how it shrank.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    showDotFixtures(window)
    window.applyView(.Compare)
    window.refreshStatus()
    let main      = microcode(window, 0)
    let reference = microcode(window, 1)
    Swag.assert(window.panels[1].isVisible() and window.panels[1].position.right() <= window.panels[0].position.x)
    Swag.assert(not window.editor.isVisible() and main.layout == .Compare and reference.layout == .Compare)
    Swag.assert(window.panels[0].headerHeight() == ViewerPanel.CompareHeaderHeight and not window.panels[0].viewMenu.isVisible())
    Swag.assert(window.panels[0].optimMenu.position.right() == window.panels[0].clientRect().right())
    Swag.assert(main.listing.markLoop and main.listing.loopFirst != null and reference.listing.loopFirst != null)
    Swag.assert(window.panels[0].gain == "−56 %" and window.panels[1].gain.isEmpty())
    Swag.assert(not main.listing.note.isEmpty() and reference.listing.note.isEmpty())
    Swag.assert(window.surface!.wnd.name.raw.contains("func dot("))
}

// A shared compile feeds both visible builds the same snapshot and keeps their distinct levels.
#test
{
    var host: Testing.HeadlessHost
    let window    = testSetupInspectionWindow(&host)
    let main      = microcode(window, 0)
    let reference = microcode(window, 1)
    window.setView(.Compare)
    Swag.assert(main.job.request.source == reference.job.request.source)
    Swag.assert(main.job.request.settings.optimization == .O2 and reference.job.request.settings.optimization == .O0)
    var watch: Time.Stopwatch
    watch.start()
    while (main.job.running or reference.job.running) and watch.elapsedMilliseconds() < 30_000
    {
        Threading.Thread.sleep(10'ms)
        host.pump()
    }

    for viewer in [main, reference]
    {
        Swag.assert(not viewer.job.running and not viewer.job.result.failed)
        Swag.assert(not viewer.inspection.snapshots.isEmpty() and viewer.shown() != null)
        let expected = Format.toString("O%", cast(u8, viewer.job.request.settings.optimization))
        Swag.assert(Utf8.startsWith(viewer.shown()!.optimize, expected))
    }

    Swag.assert(window.readingLine.reading == main.statusReading())
}

// A compilation beside the source leaves the hidden reference idle; hiding a running build is safe.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    window.compile()
    Swag.assert(microcode(window, 0).job.running)
    Swag.assert(not microcode(window, 1).job.running)
    window.setView(.Compare)
    let reference = microcode(window, 1)
    Swag.assert(reference.job.running)
    window.applyView(.Columns)
    window.shutdown()
    Swag.assert(not reference.job.running)
}

// Every command of the window is an entry of the lens, and its choices answer their family.
#test
{
    var host: Testing.HeadlessHost
    let window  = testSetupInspectionWindow(&host)
    let strings = appStrings()
    showDotFixtures(window)

    window.lens.open(">")
    for name in [strings.cmd_Compile, strings.cmd_FormatSource, strings.cmd_LiveEdit, strings.cmd_ShowColumns,
                 strings.cmd_ShowStages, strings.cmd_ShowCompare, strings.cmd_Information, strings.cmd_ShowSourceLines,
                 strings.cmd_ShowOpcodes, strings.cmd_CopyListing, strings.cmd_BuildConfiguration, strings.cmd_RestoreBuild] do
        Swag.assert(lensHasEntry(window, name))
    Swag.assert(not lensHasEntry(window, strings.cmd_PreviousStage) and not lensHasEntry(window, strings.cmd_PausePreview))
    window.lens.close()
    Swag.assert(window.doorKnown == false)

    window.applyView(.Stages)
    window.lens.open(">")
    for name in [strings.cmd_PreviousStage, strings.cmd_NextStage, strings.cmd_ShowChange] do
        Swag.assert(lensHasEntry(window, name))

    // A step that cannot be taken says why.
    var reasons = 0
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where entry.disabled
        {
            if entry.title == strings.cmd_PreviousStage do
                Swag.assert(entry.detail == strings.ui_AtFirstStage)
            if entry.title == strings.cmd_NextStage do
                Swag.assert(entry.detail == strings.ui_AtLastStage)
            reasons += 1
        }
    }

    Swag.assert(reasons >= 1)
    window.lens.close()

    window.applyView(.Compare)
    for query in [strings.lens_Stage, strings.lens_Optimization, strings.lens_Preset, strings.lens_ViewAs]
    {
        window.lens.open(query)
        Swag.assert(lensHasEntry(window, strings.ui_StageConstFold) or
                    lensHasEntry(window, "O1") or
                    lensHasEntry(window, "devmode") or
                    lensHasEntry(window, strings.ui_Render2D))
        window.lens.close()
    }

    window.lens.open(strings.lens_ViewAs)
    var sides = 0'u64
    for section in window.lens.results.sections where section!.label == sectionLabel(strings.lens_ViewAs, strings.ui_LeftColumn) do
        sides += 1
    Swag.assert(sides == 1)
    window.lens.close()

    // At rest the lens offers the actions of the view in force, then the examples.
    window.lens.open()
    Swag.assert(window.lens.results.sections[0]!.label == strings.cmd_ShowCompare)
    Swag.assert(lensHasEntry(window, strings.cmd_Compile) and lensHasEntry(window, exampleName(.Plasma)))
    Swag.assert(not lensHasEntry(window, strings.cmd_ShowCompare) and not lensHasEntry(window, "O1"))
    window.lens.close()

    window.applyView(.Stages)
    window.lens.open()
    Swag.assert(window.lens.results.sections[0]!.label == strings.cmd_ShowStages)
    Swag.assert(lensHasEntry(window, strings.cmd_PreviousStage) or lensHasEntry(window, strings.cmd_NextStage))
    Swag.assert(lensHasEntry(window, strings.cmd_ShowChange) and lensHasEntry(window, strings.cmd_ShowCompare))
    Swag.assert(not lensHasEntry(window, strings.cmd_FormatSource))
    window.lens.close()

    window.applyView(.Columns)
    window.lens.open()
    Swag.assert(window.lens.results.sections[0]!.label == strings.cmd_ShowColumns)
    Swag.assert(lensHasEntry(window, strings.cmd_FormatSource) and not lensHasEntry(window, strings.cmd_NextStage))
    window.lens.close()

    // The door opens on its chord, and the hint line stops teaching it.
    Swag.assert(window.runCommand(PrismCommands.Lens) and window.lens.isOpen() and window.doorKnown)
    window.lens.close()
}

// Once the door is known, the foot of the source follows the caret; a view without the source
// says nothing of it.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    Swag.assert(window.hintLine.reading.isEmpty())
    Swag.assert(window.runCommand(PrismCommands.Lens) and window.doorKnown)
    window.lens.close()
    Swag.assert(window.hintLine.hints.isEmpty())

    window.editor.setCursorPos(window.editor.cursorFromLogicalPosition(1, 0))
    Swag.assert(window.hintLine.reading == Format.toString(appStrings().ui_CaretPlace, 2, 1))
    window.applyView(.Stages)
    Swag.assert(window.hintLine.reading.isEmpty())
}

// Space and I open the lens and the sheet where nothing types, and are text in the editor.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    window.editor.setFocus()
    Swag.assert(window.typing() and not window.runCommand(PrismCommands.LensKey) and not window.lens.isOpen())
    Swag.assert(not window.runCommand(PrismCommands.InformationKey) and not window.infoSheet.isLocallyVisible())

    showDotFixtures(window)
    microcode(window, 0).listing.setFocus()
    Swag.assert(not window.typing() and window.runCommand(PrismCommands.InformationKey))
    Swag.assert(window.infoSheet.isLocallyVisible() and window.infoSheet.title == "dot")
    Swag.assert(window.infoSheet.text().contains(appStrings().ui_Compiler))
}

// The listing writes the backend's spelling or the reader's, with or without the source lines,
// and copies what it shows.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    showDotFixtures(window)
    let listing  = microcode(window, 0).listing
    let readable = listing.copyText()
    Swag.assert(window.runCommand(PrismCommands.Opcodes) and listing.form == .Opcodes)
    let opcodes = listing.copyText()
    Swag.assert(readable != opcodes and opcodes.contains("load_reg_mem"))
    let rows = listing.rows.count
    Swag.assert(window.runCommand(PrismCommands.SourceLines) and
                listing.showSource and
                listing.rows.count > rows)
    Swag.assert(listing.copyText().contains("return total"))
}

// The window in each view, at the size of the charter's pictures, in Encre and in Papier.
func assertInspectionSurface(view: PrismView, light: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    showDotFixtures(window)
    window.applyView(view)
    if view == .Stages do
        microcode(window, 0).setStep(3)
    window.refreshStatus()
    window.applyLayout()
    host.settleAnimations(window, 6)

    var image = host.render(&host.surfaceWnd)
    var name: String
    switch #complete view
    {
    case .Columns: name = "surface.columns"
    case .Stages:  name = "surface.stages"
    case .Compare: name = "surface.compare"
    }

    if light do
        name.append(".paper")
    Pixel.Testing.assertImageGolden(&image, name)
}

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Columns, false) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Columns, true) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Stages, false) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Stages, true) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Compare, false) }

#[Swag.TestTag("golden")]
#test { assertInspectionSurface(.Compare, true) }

// Every view fits every language at the minimum window size, in both palettes.
#test
{
    Gui.registerLanguage("fr", "Français")
    for light in [false, true]
    {
        for language in Gui.languages()
        {
            var host: Testing.HeadlessHost
            let window = testSetupInspectionWindow(&host, MainWindow.MinWidth, MainWindow.MinHeight)
            if light do
                host.theme.setLight()
            host.notify(.ThemeChanged)
            showDotFixtures(window)
            microcode(window, 0).setStage(3)
            discard expect applyLanguage(&host.app.resources, language.tag)
            host.notify(.LanguageChanged)
            for view in [PrismView.Columns, PrismView.Stages, PrismView.Compare, PrismView.Columns]
            {
                window.applyView(view)
                window.applyLayout()
                Testing.assertContentFits(window)
                Swag.assert(window.hintLine.position.right() <= window.readingLine.position.x)
                for panel, index in window.panels where window.isShown(index)
                {
                    Swag.assert(panel.position.x >= 0 and panel.position.right() <= window.clientRect().right())
                    if panel.stageMenu.isVisible() do
                        Swag.assert(panel.stageMenu.position.right() <= panel.optimMenu.position.x)
                }

                if view == .Compare do
                    Swag.assert(window.panels[1].position.right() <= window.panels[0].position.x)
            }

            Swag.assert(microcode(window, 0).stage == 3 and window.panels[0].level == .O2)
        }
    }
}

// The lens open over the window, its commands and choices in Encre and in Papier.
func assertLensSurface(light: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    showDotFixtures(window)
    window.openLens()
    host.settleAnimations(window, 6)
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, light ? "surface.lens.paper" : "surface.lens")
}

#[Swag.TestTag("golden")]
#test { assertLensSurface(false) }

#[Swag.TestTag("golden")]
#test { assertLensSurface(true) }
