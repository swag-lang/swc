#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Play a local film, pause, seek from its timeline, resume, and stop at its first frame.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = expect videoPreviewFileAt(Path.combine(journey.root, "film.y4m"), 32)
    let window = journey.window
    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "video")

    let video = assume cast(*Film.Panel, window.currentView)
    journey.waitFor("first film frame", func|video|()->bool => video.hasFrame)
    if video.playing do
        video.togglePlayback()
    Swag.require(not video.playing)

    video.timeline.setValue(cast(f32, video.frameSeconds(8)))
    journey.waitFor("film seek", func|video|()->bool => video.hasFrame and video.frameIndex == 8)
    video.togglePlayback()
    journey.waitFor("film resumed", func|video|()->bool => video.playing and video.frameIndex >= 12)
    video.togglePlayback()
    Swag.require(not video.playing)

    video.stopPlayback()
    journey.waitFor("film stopped", func|video|()->bool => video.hasFrame and video.frameIndex == 0)
}
