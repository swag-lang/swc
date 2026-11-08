#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Choose the hex view of a text file, carry that choice to its neighbor, then return to text.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let first = journey.copyData("comprehensive.txt", "A-first.txt")
    let second = journey.copyData("comprehensive.txt", "B-second.txt")
    let window = journey.window

    window.openFile(first)
    journey.waitForFile(first)
    Swag.require(window.choices[window.activeChoiceIndex].key == "text")

    var hexIndex = Swag.U32.Max
    for choice, index in window.choices where choice.key == "hex" do
        hexIndex = cast(u32, index)
    Swag.require(hexIndex != Swag.U32.Max)
    window.selectViewer(hexIndex)
    journey.waitFor("hex viewer", func|window|()->bool => window.choices[window.activeChoiceIndex].key == "hex")

    window.sendCommandEvent(ViewerCommands.NextFile)
    journey.waitForFile(second)
    Swag.require(window.choices[window.activeChoiceIndex].key == "hex")

    window.selectViewer(0)
    journey.waitFor("text viewer restored", func|window|()->bool => window.choices[window.activeChoiceIndex].key == "text")
    Swag.require(window.preferences.isEmpty())
}
