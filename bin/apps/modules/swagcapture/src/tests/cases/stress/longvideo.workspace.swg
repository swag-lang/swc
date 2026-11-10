#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Video

// Open and play near two hours, then trim almost the whole recording through editor commands.
// The copied interior packets prove the application chose its fast path, not a full transcode.
#[Swag.TestTag("stress"), Swag.TestTag("integration.application.journey")]
#test
{
    var workspace: LongVideoWorkspace
    workspace.setup(Path.combine(testSourceRoot(), "datas", "video.twohours.scc"))
    let main      = workspace.main
    let capture   = workspace.capture
    let frames    = unwrap capture.frames
    let timeline  = workspace.timeline
    let source    = Capture.mediaPathOf(workspace.document, .Video)
    let before    = expect File.info(source)
    let wholeCopy = Path.combine(Env.sandboxRoot(), "twohours-copy.mp4")
    let copyStart = Time.monotonicMicroseconds()
    expect capture.exportVideo(wholeCopy)
    let copyUs = Time.monotonicMicroseconds() - copyStart
    Swag.require((expect File.info(wholeCopy)).size == before.size)
    let nearEndUs = workspace.showFrame(215_700)
    timeline.zoomAt(timeline.trackX(capture.playheadTime()), 512)
    timeline.playButton.sigPressed.call(timeline.playButton)
    let initialFrame = capture.playhead
    workspace.waitFor("two-hour tail plays", func|capture, initialFrame|()->bool
                      => capture.playhead >= initialFrame + 30)
    timeline.playButton.sigPressed.call(timeline.playButton)
    Swag.require(not timeline.isPlaying())
    workspace.saveScreenshot("twohours-editor.png")

    discard workspace.showFrame(31)
    main.sendCommandEvent(ActionTimeline.TrimStart)
    discard workspace.showFrame(215_969)
    main.sendCommandEvent(ActionTimeline.TrimEnd)
    Swag.require(capture.trimStart() == frames.timeOf(31))
    Swag.require(capture.trimEnd() == frames.timeOf(215_969))
    main.saveCapture(capture)
    scope
    {
        let reopened = expect Capture.load(workspace.document)
        defer Memory.delete(reopened)
        Swag.require(reopened.trimStart() == capture.trimStart() and reopened.trimEnd() == capture.trimEnd())
        Swag.require(reopened.timeline.frameCount == 216_000)
    }

    let target  = Path.combine(Env.sandboxRoot(), "twohours-trim.mp4")
    let started = Time.monotonicMicroseconds()
    expect capture.exportVideo(target)
    let exportUs = Time.monotonicMicroseconds() - started
    var cut      = expect Reader.open(target)
    Swag.require(cut.frameCount() == 215_938 and cut.audioTrackCount() == 1)
    Swag.require(cut.audioTrack(0)!.sampleFrameCount() == 215_938'u64 * 1_600)
    for index in [0'u64, 29, 60_000, 215_937] do
        discard expect cut.decodeFrame(index)

    discard workspace.showFrame(900)
    workspace.drawForm(ActionToolMode.Arrow, .Arrow, {10, 20}, {120, 65})
    capture.forms.back().timeEnd = frames.timeOf(930)
    let annotated    = Path.combine(Env.sandboxRoot(), "twohours-timed-overlay.mp4")
    let overlayStart = Time.monotonicMicroseconds()
    expect capture.exportVideo(annotated)
    let overlayUs       = Time.monotonicMicroseconds() - overlayStart
    var originalPackets = expect Mp4.FragmentedPacketReader.open(source)
    var cutPackets      = expect Mp4.FragmentedPacketReader.open(annotated)
    var left, right: Array'u8
    for index in [60'u64, 60_000, 215_968]
    {
        let original = expect originalPackets.readPacket(index, &left)
        let copied   = expect cutPackets.readPacket(index - 31, &right)
        Swag.require(Slice.equals(original.bytes, copied.bytes), "long export must copy its compressed interior")
    }

    let after = expect File.info(source)
    Swag.require(before.size == after.size and before.lastWriteTime == after.lastWriteTime)
    let metrics = Format.toString("open_us=%\nseek_near_end_us=%\ncopy_export_us=%\ntrim_export_us=%\ntimed_overlay_export_us=%\noutput_bytes=%\nframes=%\n",
                                  workspace.openUs,
                                  nearEndUs,
                                  copyUs,
                                  exportUs,
                                  overlayUs,
                                  (expect File.info(target)).size,
                                  cut.frameCount())
    Console.println("Two-hour tools: ", metrics)
    discard expect File.writeAllText(Path.combine(Env.sandboxRoot(), "twohours-tools.txt"), metrics)
}

// A short annotated tail must decode only that sound range, then export and reopen exactly.
#[Swag.TestTag("stress"), Swag.TestTag("integration.application.journey")]
#test
{
    var workspace: LongVideoWorkspace
    workspace.setup(Path.combine(testSourceRoot(), "datas", "video.twohours.scc"))
    let main    = workspace.main
    let capture = workspace.capture
    discard workspace.showFrame(215_910)
    main.sendCommandEvent(ActionTimeline.TrimStart)
    discard workspace.showFrame(215_999)
    main.sendCommandEvent(ActionTimeline.TrimEnd)
    let finish = capture.trimEnd()
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.trimEnd() == capture.timeline.duration)
    main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.trimEnd() == finish)
    discard workspace.showFrame(215_920)
    workspace.drawForm(ActionToolMode.Arrow, .Arrow, {10, 20}, {120, 65})
    let shape = capture.forms.back()
    Swag.require(shape.timeStart == capture.playheadTime())
    let target  = Path.combine(Env.sandboxRoot(), "twohours-annotated-tail.mp4")
    let started = Time.monotonicMicroseconds()
    expect capture.exportVideo(target)
    let elapsedUs = Time.monotonicMicroseconds() - started
    var result    = expect Reader.open(target)
    Swag.require(result.frameCount() == 89 and result.audioTrackCount() == 1)
    Swag.require(Math.abs(result.durationInSeconds() - 89.0 / 30) < 0.00001)
    Swag.require(Math.abs(cast(s64, result.audioTrack(0)!.sampleFrameCount()) - 89 * 1_600) <= 1)
    for index in result.frameCount() do
        discard expect result.decodeFrame(index)
    Console.println("Annotated two-hour tail export_us=", elapsedUs, " frames=", result.frameCount())
    discard expect File.writeAllText(Path.combine(Env.sandboxRoot(), "twohours-tail.txt"),
                                     Format.toString("export_us=%\nframes=%\n", elapsedUs, result.frameCount()))

    // A dimension change explicitly selects conversion and must also seek directly to tail audio.
    workspace.changeImageSize(ActionImage.ExpandCapture, 162, 96)
    Swag.require(capture.width == 162)
    let converted       = Path.combine(Env.sandboxRoot(), "twohours-converted-tail.mp4")
    let conversionStart = Time.monotonicMicroseconds()
    expect capture.exportVideo(converted)
    var conversion = expect Reader.open(converted)
    Swag.require(conversion.width() == 162 and conversion.frameCount() == 89)
    Swag.require(Math.abs(cast(s64, conversion.audioTrack(0)!.sampleFrameCount()) - 89 * 1_600) <= 1)
    Console.println("Converted two-hour tail export_us=", Time.monotonicMicroseconds() - conversionStart)
}
