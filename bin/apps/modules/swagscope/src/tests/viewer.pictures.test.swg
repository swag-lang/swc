#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// Each viewer in the window the application ships, at the size of its picture, so its golden is
// judged whole against the picture of the charter.
func picturedViewer(fileName: string, light: bool, golden: string)
{
    var host: Testing.HeadlessHost
    photographViewer(&host, framedViewerWindow(&host, fileName, light), golden)
}

// Opens `fileName` in the viewer named `key` rather than the one it opens in.
func picturedWindowAs(host: *Testing.HeadlessHost, fileName, key: string, light: bool)->*ViewerWindow
{
    let window = framedViewerWindow(host, fileName, light)
    for choice, index in window.choices where choice.key == key
    {
        window.selectViewer(cast(u32, index))
        break
    }

    completeQueuedViewerFile(host, window)
    Swag.assert(window.choices[window.activeChoiceIndex].key == key)
    return window
}

// Photographs `window` at rest.
func photographViewer(host: *Testing.HeadlessHost, window: *ViewerWindow, golden: string)
{
    window.applyLayout()
    host.settleAnimations(window, 8)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, golden)
}

func picturedFixture(name: string)->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", name)

#[Swag.TestTag("golden")]
#test
{
    picturedViewer(picturedFixture("imageset-real-review.webp"), false, "pictured.image")
    picturedViewer(picturedFixture("viewer.csv"), true, "pictured.table.paper")
    picturedViewer(picturedFixture("viewer.page.html"), true, "pictured.html.paper")
    picturedViewer(picturedFixture("segoeui.ttf"), true, "pictured.font.paper")

    var binaryHost: Testing.HeadlessHost
    photographViewer(&binaryHost, picturedWindowAs(&binaryHost, picturedFixture("segoeui.ttf"), "binary", false), "pictured.binary")
}

// The byte view of a PNG, as its picture shows it: the chunks as tabs over the grid, the data of
// the image header selected, and the inspector reading the width the caret stands on.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = picturedWindowAs(&host, picturedFixture("title.png"), "hex", false)
    let view   = assume cast(*Viewers.Hex.Panel, window.currentView)

    var labels: Array'String
    for tab in view.structure.tabs do
        labels.add(tab.label)
    Swag.assert(view.structure.formatName == "PNG" and labels.count == 6)
    Swag.assert(labels[0] == "Signature" and
                labels[1] == "IHDR" and
                labels[4] == "IDAT × 9" and
                labels[5] == "IEND")

    view.grid.selectRange(0x10, 13)
    Swag.assert(view.tabs.active == 1)
    with let inspector = view.inspectorView
    {
        Swag.assert(.headline == "5 000" and .caption == "u32 BE at 0x00000010")
        Swag.assert(.fields.count == 8 and .fields[0].label == "Width" and .fields[0].strong)
        Swag.assert(.fields[3].value == "6 · RGBA")
    }

    Swag.assert(view.details == "0x10 – 0x1C · 13 bytes selected")
    photographViewer(&host, window, "pictured.hex")
}

// A Windows program on the binary viewer's report page, as its picture shows it: the name over the
// identity line, the figures, the sections as one bar, the imports by library.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, picturedFixture("viewer.console.exe"), false)
    Swag.assert(window.choices[window.activeChoiceIndex].key == "binary")
    let view = assume cast(*Viewers.Binary.Panel, window.currentView)

    with let overview = &view.doc.report.overview
    {
        Swag.assert(.identity.count >= 3 and .identity[0] == "PE32+" and .identity[1] == "x64")
        Swag.assert(.sections.count != 0 and .sections[0].name == ".text")
        Swag.assert(.strings != 0)
        Swag.assert(.libraries.count != 0)
        Swag.assert(.imports != 0)
    }

    Swag.assert(view.page.isLocallyVisible() and not view.list.isLocallyVisible())
    photographViewer(&host, window, "pictured.binary.page")

    view.showPage(false)
    Swag.assert(view.list.isLocallyVisible() and not view.page.isLocallyVisible())
}
