#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Open a raw file in hex, find two byte sequences, and jump to a typed offset.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "sample.bin")
    expect File.writeAllText(file, "01234567MARKabcdefghijMARKxyz")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    var hexIndex = Swag.U32.Max
    for choice, index in window.choices where choice.key == "hex" do
        hexIndex = cast(u32, index)
    Swag.require(hexIndex != Swag.U32.Max)
    window.selectViewer(hexIndex)
    journey.waitFor("hexadecimal view", func|window|()->bool => window.choices[window.activeChoiceIndex].key == "hex")
    let hex = assume cast(*Hex.Panel, window.currentView)

    window.sendCommandEvent(ViewerCommands.Find)
    window.searchBox.setText("text:MARK")
    journey.waitFor("two byte matches", func|window, hex|()->bool => window.searchComplete and
                                                                window.searchMatches.count == 2 and
                                                                hex.grid.matchStart == 8)
    window.sendCommandEvent(ViewerCommands.FindNext)
    journey.waitFor("second byte match", func|window, hex|()->bool => window.searchIndex == 1 and
                                                                  hex.grid.matchStart == 22)
    Swag.require(hex.grid.goToTypedOffset("0x10") and hex.grid.caret == 16)
    Swag.require(hex.grid.matchStart == 22)
}
