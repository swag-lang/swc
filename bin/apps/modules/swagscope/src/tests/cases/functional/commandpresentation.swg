#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Inspect the live catalog in each built-in reader, including commands provided by its plugin.
#test
{
    defer Sound.releaseEngine()
    let files = ["comprehensive.txt", "sample.cpp", "viewer.page.html", "comprehensive.md",
                 "title.png", "segoeui.ttf", "viewer.groove.mid", "viewer.pdf", "viewer.srt",
                 "pacman_beginning.wav", "viewer.console.exe", "viewer.hex", "viewer.archive.zip", "viewer.csv"]
    for file in files
    {
        var host: Testing.HeadlessHost
        let window = framedViewerWindow(&host, scopeTestDataPath(file), false)
        Swag.require(window.currentView != null or window.isExploring(), file)
        window.lens.open(">")
        var commands: u32
        for section in window.lens.results.sections where section and not section.inline
        {
            for &entry in section.entries where (entry.id or entry.run) and entry.lead.isEmpty() and not entry.paint
            {
                Swag.require(entry.glyph.isValid(), entry.title)
                commands += 1
            }
        }

        Swag.require(commands > 10, file)
        window.lens.close()
    }
}

// Plugin rows retain their glyph through filtering, checked/disabled state and execution.
#test
{
    var ran:  bool
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Text", host.theme)
    entries.query = "unrelated"
    Swag.require(entries.add("Wrap", .Wrap, func() {}) == null)
    entries.query = ""
    let reset = unwrap entries.addZoom(.Reset, 100, func|ran = &ran|() { ran[] = true })
    let upper = unwrap entries.addZoom(.In, Viewer.MaxZoom, func() {})
    Swag.require(reset.glyph == host.theme.icon(.ActualSize, host.theme.metrics.menuPopup_IconSize))
    Swag.require(reset.checked and not reset.disabled and reset.detail.count != 0)
    Swag.require(upper.disabled and upper.glyph.isValid())
    reset.run!()
    Swag.require(ran)
}

// Removing history is critical in every command-based presentation, including the lens.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), true)
    for id in [ViewerCommands.Forget, ViewerCommands.ClearHistory]
    {
        let state = window.sendComputeCommandStateEvent(id)
        Swag.require(state.updatedFields.has(.Icon) and state.icon.isValid())
        Swag.require(state.updatedFields.has(.RenderingHint) and state.renderingHint.has(.Critical))
        let menu = MenuCtrl.createPopup(window, owner: window)
        let item = menu.addItem(id)
        menu.updateState()
        Swag.require(item.critical and item.icon.isValid())
        menu.destroy()
    }
}
