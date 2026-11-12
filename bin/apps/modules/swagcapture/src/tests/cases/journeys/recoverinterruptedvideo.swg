#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Video

// A new library folder recovers a playable orphan MP4 and shows its document in the grid.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    journey.waitFor("initial recovery checked", func|main|()->bool => main.videoRecoveryJob == null)

    let folder = Path.combine(journey.root, "recordings")
    expect Directory.create(folder)
    var document = Path.combine(folder, "interrupted.scc")
    let media = Capture.mediaPathOf(document, .Video)
    var picture = Image.create(32, 16, .BGRA8)
    picture.fill(Argb.White)
    var writer = expect Mp4.SoftwareRecording.createVideoOnly(media, 32, 16, 1_000_000)
    for frame in 2'u64 do
        expect writer.addFrame(&picture, FrameSlot{frame, frame * 100_000, 100_000, 0})
    expect writer.end()

    expect g_Library.setFolder(folder)
    main.startVideoRecovery()
    journey.waitFor("video recovered", func|main, &document|()->bool =>
                    main.videoRecoveryJob == null and File.exists(document))
    journey.openLibrary(1)
    let capture = expect Capture.load(document)
    defer Memory.delete(capture)
    Swag.require(capture.media == .Video and capture.timeline.frameCount == 2)
    let preview = expect Capture.load(document, preview: true)
    defer Memory.delete(preview)
    Swag.require(preview.preview.isValid())
}
