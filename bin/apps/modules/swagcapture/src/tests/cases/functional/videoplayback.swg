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
    timeline.togglePlay()
    defer timeline.stop()
    Swag.require(timeline.audioReader != null and timeline.audioVoices[0] != null)
    let sound = unwrap timeline.audioReader.audioTrack(0)
    let voice = unwrap timeline.audioVoices[0]
    expect voice.seekSampleFrame(sound.sampleFrameCount())

    timeline.playFrom = 0
    timeline.playStart = Time.monotonicMicroseconds() - 700_000
    var event = TimerEvent{timer: unwrap timeline.playTimer}
    timeline.IWnd.onTimerEvent(&event)
    Swag.require(f.capture.playhead >= 7 and timeline.isPlaying())

    expect voice.pause()
    expect voice.seekSampleFrame(2_400)
    timeline.audioClockLast = sound.timelineStartSeconds() + voice.playbackPositionSeconds()
    timeline.playFrom = 0
    timeline.playStart = Time.monotonicMicroseconds() - 800_000
    timeline.IWnd.onTimerEvent(&event)
    Swag.require(f.capture.playhead >= 8)
}
