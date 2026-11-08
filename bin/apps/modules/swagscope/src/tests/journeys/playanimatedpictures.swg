#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Open three animated image formats, pause and scrub each, then move to the next picture.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let first = journey.copyData("imageset-animation.gif", "A-motion.gif")
    let second = journey.copyData("imageset-animation.apng", "B-motion.apng")
    let third = journey.copyData("imageset-animation.webp", "C-motion.webp")
    let window = journey.window

    window.openFile(first)
    for file in [first, second, third]
    {
        journey.waitForFile(file[])
        Swag.require(window.choices[window.activeChoiceIndex].key == "image")
        let panel = assume cast(*Picture.Panel, window.currentView)
        Swag.require(panel.imageView.movie.frameCount > 1)
        Swag.require(panel.playButton.isLocallyVisible() and panel.timeline.isLocallyVisible())
        panel.playButton.sigPressed.call(panel.playButton)
        Swag.require(panel.imageView.movie.isPaused)
        panel.timeline.setValue(1)
        journey.waitFor("second animation frame", func|panel|()->bool => panel.imageView.movie.frameIndex == 1)
        panel.rotateClockwise()
        Swag.require(panel.imageView.rotationQuarterTurns == 1)
        if file[] != third do
            window.sendCommandEvent(ViewerCommands.NextFile)
    }
}
