#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel, Video

// Reaching the end of a short sound track must not freeze the remaining video pictures.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let document = testTempCapturePath()
    let source = Capture.mediaPathOf(document, .Video)
    defer
    {
        f.capture.closeMedia()
        discard catch Capture.deleteFiles(document)
    }

    let picture = Image.create(64, 48, .BGRA8)
    picture.fill(Argb.White)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice}]
    var recording = expect Mp4.SoftwareRecording.createWithAudioTracks(source, 64, 48, 1_000_000, configs)
    for frame in 10'u64 do
        expect recording.addFrame(&picture, FrameSlot{frame, frame * 100_000, 100_000, 0})
    var samples: Array's16
    samples.resize(4_800)
    expect recording.addAudioFrames(samples.toSlice())
    expect recording.end()

    f.capture.file = document
    expect f.capture.adoptVideo()
    let timeline = TimelineBar.create(f.main, &f.gui.root)
    f.main.timeline = timeline
    timeline.togglePlay()
    defer timeline.stop()
    var event = TimerEvent{timer: unwrap timeline.playTimer}
    let readyBy = Time.monotonicMicroseconds() + 2_000_000
    while not timeline.videoBuffered() and not timeline.videoDecodeFailed()
    {
        Swag.require(Time.monotonicMicroseconds() < readyBy, "video prefetch did not finish")
        Threading.Thread.sleep(1'ms)
    }
    timeline.IWnd.onTimerEvent(&event)
    Swag.require(timeline.audioReader != null and timeline.audioVoices[0] != null)
    let sound = unwrap timeline.audioReader.audioTrack(0)
    let voice = unwrap timeline.audioVoices[0]
    expect voice.pause()
    expect voice.seekSampleFrame(sound.sampleFrameCount())

    timeline.playFrom = 0
    timeline.playStart = Time.monotonicMicroseconds() - 700_000
    let frameBy = Time.monotonicMicroseconds() + 2_000_000
    while f.capture.playhead < 7
    {
        Swag.require(Time.monotonicMicroseconds() < frameBy, "video prefetch did not reach frame seven")
        timeline.IWnd.onTimerEvent(&event)
        Threading.Thread.sleep(1'ms)
    }
    Swag.require(f.capture.playhead >= 7 and timeline.isPlaying())
    Swag.require(f.capture.playbackPlanar)
    let rendered = f.capture.toImage()
    Swag.require(f.capture.backTexturePlanar and rendered.pixelColor(8, 8).argb == Argb.White)

    expect voice.pause()
    expect voice.seekSampleFrame(2_400)
    timeline.audioClockLast = sound.timelineStartSeconds() + voice.playbackPositionSeconds()
    timeline.playFrom = 0
    timeline.playStart = Time.monotonicMicroseconds() - 800_000
    let nextBy = Time.monotonicMicroseconds() + 2_000_000
    while f.capture.playhead < 8
    {
        Swag.require(Time.monotonicMicroseconds() < nextBy, "video prefetch did not reach frame eight")
        timeline.IWnd.onTimerEvent(&event)
        Threading.Thread.sleep(1'ms)
    }
    Swag.require(f.capture.playhead >= 8)

    timeline.togglePlay()
    Swag.require(not timeline.isPlaying() and f.capture.playbackPlanar)

    timeline.stop()
    Swag.require(not f.capture.playbackPlanar)
    Swag.require(f.capture.backImg.pixelColor(8, 8).argb == Argb.White)

    timeline.setPosition({0, 0, 600, TimelineHeight})
    let frames = unwrap f.capture.frames
    timeline.seek(timeline.trackX(frames.timeOf(2) + 1_000))
    Swag.require(timeline.seekTimer != null and f.capture.playhead >= 8)
    var seekEvent = TimerEvent{timer: timeline.seekTimer}
    let seekBy = Time.monotonicMicroseconds() + 2_000_000
    while f.capture.playhead != 2
    {
        Swag.require(Time.monotonicMicroseconds() < seekBy, "paused video seek did not finish")
        timeline.IWnd.onTimerEvent(&seekEvent)
        Threading.Thread.sleep(1'ms)
    }
    Swag.require(not timeline.isPlaying() and timeline.seekTimer == null and f.capture.playbackPlanar)

    timeline.seek(timeline.trackX(frames.timeOf(4) + 1_000))
    timeline.togglePlay()
    Swag.require(timeline.seekTimer == null and timeline.isPlaying() and timeline.videoFrom == 4)
    let replayBy = Time.monotonicMicroseconds() + 2_000_000
    while not timeline.videoBuffered()
    {
        Swag.require(Time.monotonicMicroseconds() < replayBy, "video did not buffer after a pending seek")
        Threading.Thread.sleep(1'ms)
    }
    var replayEvent = TimerEvent{timer: timeline.playTimer}
    timeline.IWnd.onTimerEvent(&replayEvent)
    Swag.require(f.capture.playhead == 4)
    timeline.togglePlay()

    // The audio reader and decoder worker can still hold the MP4 after a pause. Deleting
    // the edited recent capture must close both before moving its files to the trash.
    f.capture.changed = true
    expect f.capture.save()
    g_Library.addFile(document)
    let trashed = Path.combine(Library.getTrashFolder(), Path.fileName(document) orelse "")
    defer discard catch Capture.deleteFiles(trashed)
    timeline.togglePlay()
    Swag.require(g_Library.removeFile(document))
    Swag.require(not File.exists(document) and not File.exists(source))
    Swag.require(File.exists(trashed) and File.exists(Capture.mediaPathOf(trashed, .Video)))
    Swag.require(timeline.audioReader == null and not timeline.isPlaying())
}
