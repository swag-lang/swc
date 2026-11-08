#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Open a film with a matching sidecar, seek to a caption, turn captions off and on.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = expect videoPreviewFileAt(Path.combine(journey.root, "lesson.y4m"), 20)
    let sidecar = Path.combine(journey.root, "lesson.en.srt")
    expect File.writeAllText(sidecar, "1\n00:00:00,000 --> 00:00:00,400\nOpening caption\n\n2\n00:00:00,500 --> 00:00:01,500\nSecond caption\n")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    let video = assume cast(*Film.Panel, window.currentView)
    journey.waitFor("sidecar found", func|video|()->bool => video.subtitleReady and
                                                          video.subtitleSource == .Sidecar and
                                                          video.subtitleOverlay.sidecars.count == 1)
    if video.playing do
        video.togglePlayback()
    video.seekSeconds(0.75)
    journey.waitFor("second caption shown", func|video|()->bool => video.hasFrame and
                                                                   video.subtitleOverlay.text == "Second caption")

    video.selectSubtitle(.Off)
    Swag.require(video.subtitleOverlay.text.isEmpty())
    video.selectSubtitle(.Sidecar, 0)
    journey.waitFor("caption restored", func|video|()->bool => video.subtitleOverlay.text == "Second caption")
}
