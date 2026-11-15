#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Calc's styled budget keeps its authored geometry beside the sheet outline in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.ods"), false, 1040, 720)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.ods.budget.encre")
}

// A producer-converted monthly budget with cached amounts reads on Papier.
#[Swag.TestTag("golden")]
#test
{
    picturedViewer(scopeTestDataPath("viewer.monthly-budget.ods"), true, "viewer.ods.monthly.paper", 1100, 740)
}

// Text reading and French sheet controls fit a narrow Papier window.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.ods"), true, 560, 400)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    let panel = assume cast(*Xlsx.Panel, window.currentView)
    panel.turn(1)
    panel.setTextMode(true)
    window.applyLayout()
    host.finishAnimations()
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.ods.reading.fr.paper")
}
