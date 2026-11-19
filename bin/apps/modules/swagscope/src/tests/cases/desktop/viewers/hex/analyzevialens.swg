#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Find the hexadecimal analysis command in the lens with native keys, then close the panel.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "bytes.bin")
    expect File.writeAllText(file, "A short binary sample for analysis")
    let window = journey.window
    window.openFile(file)
    journey.waitForFile(file)

    var hexIndex = Swag.U32.Max
    for choice, index in window.choices where choice.key == "hex" do
        hexIndex = cast(u32, index)
    Swag.require(hexIndex != Swag.U32.Max)
    window.selectViewer(hexIndex)
    journey.waitFor("hexadecimal viewer", func|window|()->bool =>
                    window.choices[window.activeChoiceIndex].key == "hex")
    let hex = assume cast(*Hex.Panel, window.currentView)
    journey.waitFor("hexadecimal analysis ready", func|hex|()->bool => hex.analysisButton.isEnabled())
    Swag.require(not hex.analysisView.isVisible())

    var input = Testing.DesktopInput.create(&journey.app, journey.surface)
    // "Analyze the" identifies the toggle even after the checksum commands appear.
    let analysisQuery = [Input.Key.A, .N, .A, .L, .Y, .Z, .E, .Space, .T, .H, .E]
    input.shortcut(.Space, .Control)
    journey.waitFor("native command lens", func|window|()->bool => window.lens.isOpen())
    for key in analysisQuery do
        input.shortcut(key, .None)
    journey.waitFor("analysis command found", func|window, hex|()->bool =>
                    window.lens.chosenEntry() != null and window.lens.chosenEntry()!.title == hex.analysisButton.toolTip)
    input.shortcut(.Return, .None)
    journey.waitFor("native analysis toggle", func|hex|()->bool =>
                    hex.analysisButton.isChecked and hex.analysisView.isVisible())
    journey.waitFor("hexadecimal analysis complete", func|hex|()->bool => hex.analysisView.result.hasDigests)
    input.shortcut(.Space, .Control)
    journey.waitFor("native command lens reopened", func|window|()->bool => window.lens.isOpen())
    for key in analysisQuery do
        input.shortcut(key, .None)
    journey.waitFor("analysis command found again", func|window, hex|()->bool =>
                    window.lens.chosenEntry() != null and window.lens.chosenEntry()!.title == hex.analysisButton.toolTip)
    input.shortcut(.Return, .None)
    journey.waitFor("native analysis close", func|hex|()->bool =>
                    not hex.analysisButton.isChecked and not hex.analysisView.isVisible())
}
