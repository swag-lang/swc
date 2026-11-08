#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// A Windows program on the binary viewer's report page, as its picture shows it: the name over the
// identity line, the figures, the sections as one bar, the imports by library.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, picturedFixture("viewer.console.exe"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "binary")
    let view = assume cast(*Viewers.Binary.Panel, window.currentView)

    with let overview = &view.doc.report.overview
    {
        Swag.require(.identity.count >= 3 and .identity[0] == "PE32+" and .identity[1] == "x64")
        Swag.require(.sections.count != 0 and .sections[0].name == ".text")
        Swag.require(.strings != 0)
        Swag.require(.libraries.count != 0)
        Swag.require(.imports != 0)
    }

    Swag.require(view.page.isLocallyVisible() and not view.list.isLocallyVisible())
    photographViewer(&host, window, "pictured.binary.page")

    view.showPage(false)
    Swag.require(view.list.isLocallyVisible() and not view.page.isLocallyVisible())
}
