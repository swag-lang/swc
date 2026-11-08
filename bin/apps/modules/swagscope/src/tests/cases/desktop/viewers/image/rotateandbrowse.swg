#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Focus the picture with a native click, rotate by key, and browse its neighboring file.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let first  = journey.copyData("sample.svg", "A-drawing.svg")
    let second = journey.copyData("appicon.png", "B-picture.png")
    let window = journey.window

    window.openFile(first)
    journey.waitForFile(first)
    Swag.require(window.choices[window.activeChoiceIndex].key == "image")
    let picture = assume cast(*Picture.Panel, window.currentView)
    var input = Testing.DesktopInput.create(&journey.app, journey.surface)
    input.click(&picture.imageView.wnd)
    input.shortcut(.R, .None)
    journey.waitFor("native rotation shortcut", func|picture|()->bool =>
        picture.imageView.rotationQuarterTurns == 1)
    input.shortcut(.H, .None)
    journey.waitFor("native mirror shortcut", func|picture|()->bool => picture.imageView.isMirrored)
    input.shortcut(.R, .Control)
    journey.waitFor("native transform reset", func|picture|()->bool =>
        picture.imageView.rotationQuarterTurns == 0 and not picture.imageView.isMirrored)

    input.shortcut(.Right, .None)
    journey.waitForFile(second)
    Swag.require(window.choices[window.activeChoiceIndex].key == "image")
}
