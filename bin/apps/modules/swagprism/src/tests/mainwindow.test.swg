#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func testSetupInspectionWindow(host: *Testing.HeadlessHost, width = cast(f32) MainWindow.WindowWidth, height = cast(f32) MainWindow.WindowHeight)->*MainWindow
{
    let window = testSetupMainWindow(host, width, height)
    window.selectedExample = .Dot
    window.exampleCombo.setSelectedIndex(cast(u32) ExampleKind.Dot, notify: false)
    window.liveEdit.setState(.Unchecked)
    window.editor.setText(exampleSource(.Dot))
    window.panels[0].selectViewer(.Microcode)
    return window
}

func microcode(window: *MainWindow, panel: u64)->*MicrocodeViewer => cast(*MicrocodeViewer) window.panels[panel].viewer!.window()

// One viewer is visible by default; the optional comparison has independent defaults.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    defer host.shutdown()
    Swag.assert(!window.comparisonEnabled)
    Swag.assert(window.viewerSplit.isPaneVisible(0) and !window.viewerSplit.isPaneVisible(1))
    let left  = microcode(window, 0)
    let right = microcode(window, 1)
    Swag.assert(left != right)
    Swag.assert(left.stageCombo.items.count == Pipeline.Stages.count)
    Swag.assert(left.stageCombo.selectedIndex == Pipeline.DefaultStage)
    Swag.assert(right.stageCombo.selectedIndex == Pipeline.DefaultStage)
    Swag.assert(left.optimCombo.selectedIndex == 0)
    Swag.assert(right.optimCombo.selectedIndex == 2)
    Swag.assert(window.status.name == appStrings().ui_Ready)
    Swag.assert(window.panels[0].kindCombo.items.count == 3)
    Swag.assert(window.panels[0].kindCombo.selectedIndex == 0)
    Swag.assert(!window.layoutButton.isChecked and window.layoutButton.toolTip == appStrings().ui_TwoViewers)
}

// The editor opens on the starter snippet, and that snippet is one the probe can inspect.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    defer host.shutdown()

    let text = window.editor.text()
    Swag.assert(Utf8.indexOf(cast(const [..] u8) text.toString(), "\n{\n    var total = 0'f32\n    for i in a.count do\n        total += a[i] * b[i]\n    return total\n}") != Swag.U64.Max)
    let inspected = Pipeline.inspectedSource(text.toString(), "pre-emit")
    Swag.assert(Utf8.indexOf(cast(const [..] u8) inspected.toString(), "#[Swag.PrintMicro") != Swag.U64.Max)
}

// An option change submits only that viewer and queues its next request independently.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    defer host.shutdown()
    let left  = microcode(window, 0)
    let right = microcode(window, 1)
    left.optimCombo.setSelectedIndex(1)
    Swag.assert(left.job.running and left.job.timer != null)
    Swag.assert(left.job.optimLevel == .O1)
    Swag.assert(!right.job.running)
    left.optimCombo.setSelectedIndex(0)
    Swag.assert(left.job.queued and left.job.optimLevel == .O1)
    window.shutdown()
    Swag.assert(!left.job.running and left.job.timer == null)
}

// The global mode button changes only the layout and retains both viewers' state.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    defer host.shutdown()
    let first  = microcode(window, 0)
    let second = microcode(window, 1)
    host.click(window.layoutButton.localToSurface(Math.Point{18, 18}))
    Swag.assert(window.comparisonEnabled and window.viewerSplit.isPaneVisible(1))
    Swag.assert(window.layoutButton.isChecked and window.layoutButton.toolTip == appStrings().ui_OneViewer)
    second.optimCombo.setSelectedIndex(1, notify: false)
    second.stageCombo.setSelectedIndex(0, notify: false)
    second.outputText.parse("comparison result")
    second.outputText.show(second.output)
    second.outputIsHint = false
    let comparisonWidth = first.position.width
    host.click(window.layoutButton.localToSurface(Math.Point{18, 18}))
    Swag.assert(!window.comparisonEnabled and !window.viewerSplit.isPaneVisible(1))
    Swag.assert(!window.layoutButton.isChecked)
    Swag.assert(first.position.width > comparisonWidth)
    host.click(window.layoutButton.localToSurface(Math.Point{18, 18}))
    Swag.assert(second.optimCombo.selectedIndex == 1 and second.stageCombo.selectedIndex == 0)
    Swag.assert(second.output.text().toString() == "comparison result")
    window.panels[1].selectViewer(.Microcode)
    Swag.assert(microcode(window, 1) == second)
    Swag.assert(second.output.text().toString() == "comparison result")
}

// A shared compile feeds both visible viewers the same snapshot and retains their distinct levels.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    defer host.shutdown()
    let left  = microcode(window, 0)
    let right = microcode(window, 1)
    window.setComparisonEnabled(true)
    window.compile()
    Swag.assert(left.job.source.toString() == right.job.source.toString())
    Swag.assert(left.job.optimLevel == .O0 and right.job.optimLevel == .O2)
    var watch: Time.Stopwatch
    watch.start()
    while (left.job.running or right.job.running) and watch.elapsedMilliseconds() < 30_000
    {
        Threading.Thread.sleep(10'ms)
        if left.job.running do
            host.fireTimer(left.job.timer)
        if right.job.running do
            host.fireTimer(right.job.timer)
    }

    for viewer in [left, right]
    {
        Swag.assert(!viewer.job.running and viewer.job.timer == null)
        Swag.assert(!viewer.job.stopped and !viewer.job.result.failed)
        Swag.assert(!viewer.outputIsHint and viewer.outputText.colors.count != 0)
        let plain    = viewer.output.text()
        let expected = Format.toString("  optimize : O%", cast(u8) viewer.job.optimLevel)
        Swag.assert(Utf8.indexOf(cast(const [..] u8) plain.toString(), expected.toString()) != Swag.U64.Max)
        Swag.assert(Utf8.indexOf(cast(const [..] u8) plain.toString(), "\x1B") == Swag.U64.Max)
    }

    Swag.assert(window.status.name == appStrings().ui_Ready)
}

// Single-viewer compilation leaves the hidden comparison idle; hiding a running viewer is safe.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    defer host.shutdown()
    window.compile()
    Swag.assert(microcode(window, 0).job.running)
    Swag.assert(!microcode(window, 1).job.running)
    window.setComparisonEnabled(true)
    window.compile()
    let second = microcode(window, 1)
    Swag.assert(second.job.running)
    window.setComparisonEnabled(false)
    window.shutdown()
    Swag.assert(!second.job.running and second.job.timer == null)
}

// Both supported layouts use the same themed structural panels.
func assertSurface(comparison: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupInspectionWindow(&host)
    defer host.shutdown()

    host.theme.setSwagDark()

    // The chrome is not part of what this image pins: a headless surface has no desktop under it,
    // so its shadow falls on nothing and its rounded corner only punches holes in the captured
    // pixels. `HeadlessHost.setup` squares it for that reason, and applying a palette puts the
    // geometry of that palette back, so it is squared again here.
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    window.setComparisonEnabled(comparison)
    host.settleAnimations(window, 6)
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, comparison ? "surface.comparison" : "surface")
}

#[Swag.TestTag("golden")]
#test { assertSurface(false) }

#[Swag.TestTag("golden")]
#test { assertSurface(true) }

// Comparison panes and themed bars fit every language at the minimum window size.
#test
{
    Gui.registerLanguage("fr", "Français")
    for palette in 3
    {
        for language in Gui.languages()
        {
            var host: Testing.HeadlessHost
            let window = testSetupInspectionWindow(&host, MainWindow.MinWidth, MainWindow.MinHeight)
            defer host.shutdown()
            if palette == 0 do
                host.theme.setSwagDark()
            elif palette == 1 do
                host.theme.setDark()
            else do
                host.theme.setLight()
            host.notify(.ThemeChanged)
            let left = microcode(window, 0)
            left.stageCombo.setSelectedIndex(3, notify: false)
            discard expect applyLanguage(&host.app.resources, language.tag)
            host.notify(.LanguageChanged)
            window.applyLayout()
            Swag.assert(left.stageCombo.selectedIndex == 3 and left.optimCombo.selectedIndex == 0)
            Testing.assertContentFits(window)
            for message in [StatusMessage.NoOutput, StatusMessage.Stopped, StatusMessage.ProbeStopped]
            {
                left.setStatus(message)
                window.applyLayout()
                Testing.assertContentFits(window)
            }

            for comparison in [false, true, false]
            {
                window.setComparisonEnabled(comparison)
                Testing.assertContentFits(window)
                Swag.assert(window.viewerSplit.isPaneVisible(1) == comparison)
                Swag.assert(window.layoutButton.isChecked == comparison)
                if comparison do
                    Swag.assert(window.panels[0].position.right() <= window.panels[1].position.x)
            }

            Swag.assert(host.theme.colors.commandBar_Bk != host.theme.colors.richEdit_Bk)
            Swag.assert(host.theme.colors.informationBar_Bk != host.theme.colors.richEdit_Bk)
        }
    }
}
