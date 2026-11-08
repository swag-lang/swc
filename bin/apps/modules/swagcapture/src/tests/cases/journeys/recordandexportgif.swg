#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Select an area, stop a recording after frames have been written, and export the capture as a GIF.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()

    journey.recordAnimation(.Stop)
    let capture = unwrap journey.main.editWnd.getCapture()
    Swag.require(capture.media == .Animation and capture.sourceKind == .Screen)
    Swag.require(capture.timeline.frameCount >= 2)
    Swag.require(File.exists(capture.file) and File.exists(Capture.mediaPathOf(capture.file)))

    let path = Path.combine(journey.root, "recording.gif")
    expect capture.exportAnimation(path)
    let bytes = expect File.readAllBytes(path)
    var reader = expect ImageReader.decode("recording.gif", bytes.toSlice())
    // Identical desktop frames may be folded into one GIF frame by the exporter.
    Swag.require(reader.info.frames.count >= 1)
    Swag.require(reader.info.canvasWidth == capture.width and reader.info.canvasHeight == capture.height)
}
