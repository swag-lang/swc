#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Rotate and mirror a vector picture, reset it, then move to a raster neighbor.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let vector = journey.copyData("sample.svg", "A-drawing.svg")
    let raster = journey.copyData("appicon.png", "B-picture.png")
    let window = journey.window

    window.openFile(vector)
    journey.waitForFile(vector)
    Swag.require(window.choices[window.activeChoiceIndex].key == "image")
    let picture = assume cast(*Picture.Panel, window.currentView)
    Swag.require(picture.facts.vector)
    picture.rotateClockwise()
    picture.mirrorHorizontally()
    Swag.require(picture.imageView.isMirrored and picture.imageView.rotationQuarterTurns != 0)
    picture.imageView.zoomIn()
    Swag.require(picture.zoomLabel.text().count > 0)
    picture.resetTransform()
    Swag.require(not picture.imageView.isMirrored and picture.imageView.rotationQuarterTurns == 0)

    window.sendCommandEvent(ViewerCommands.NextFile)
    journey.waitForFile(raster)
    let next = assume cast(*Picture.Panel, window.currentView)
    Swag.require(not next.facts.vector and next.imageView.rotationQuarterTurns == 0 and
                 not next.imageView.isMirrored)
    next.rotateCounterClockwise()
    Swag.require(next.imageView.rotationQuarterTurns == 3)
    next.resetTransform()
    next.imageView.zoomToFit()
    Swag.require(next.imageView.rotationQuarterTurns == 0)
}
