#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

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
    Swag.require(view.structure.formatName == "PNG" and labels.count == 6)
    Swag.require(labels[0] == "Signature" and
                 labels[1] == "IHDR" and
                 labels[4] == "IDAT × 9" and
                 labels[5] == "IEND")

    view.grid.selectRange(0x10, 13)
    Swag.require(view.tabs.active == 1)
    with let inspector = view.inspectorView
    {
        Swag.require(.headline == "5 000" and .caption == "u32 BE at 0x00000010")
        Swag.require(.fields.count == 8 and .fields[0].label == "Width" and .fields[0].strong)
        Swag.require(.fields[3].value == "6 · RGBA")
    }

    Swag.require(view.details == "0x10 – 0x1C · 13 bytes selected")
    photographViewer(&host, window, "pictured.hex", picturedGoldenOptions(8))
}
