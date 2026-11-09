#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel, Video

private func paintVideoWindow(window: *Env.Window, pixel: u32)
{
    let drawable = expect window.xcbDrawable()
    let library = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    Swag.require(library != null)
    defer discard Linux.dlclose(unwrap library)
    let attributes = expect X11Capture.symbol'Linux.xcb_change_window_attributes_checked_fn(
        library, "xcb_change_window_attributes_checked")
    let clear = expect X11Capture.symbol'Linux.xcb_clear_area_checked_fn(
        library, "xcb_clear_area_checked")
    let check = expect X11Capture.symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let connection = unwrap drawable.connection
    let changed = check(connection, attributes(connection, drawable.window, 2, &pixel))
    defer Linux.free(changed)
    Swag.require(changed == null)
    let cleared = check(connection, clear(connection, 0, drawable.window, 0, 0, 0, 0))
    defer Linux.free(cleared)
    Swag.require(cleared == null)
}

// Real X11 pixels and synthetic PCM travel through the software MP4 path and reopen together.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    let started = Time.monotonicMicroseconds()
    var window = expect Env.createWindow({identifier: "capture-video-source",
                                          title: "Video capture fixture",
                                          width: 64, height: 48,
                                          stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintVideoWindow(&window, 0xFF0000)

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-video-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    var source = expect ScreenFrameSource.create(false, 10, 20, 64, 48)
    var recorder = expect Mp4.SoftwareRecording.create(path, 64, 48, 90_000, 48_000, 1)
    let openedAt = Time.monotonicMicroseconds()
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 1_000_000, 90_000)

    var picture: Image
    expect source.grabInto(&picture)
    var expectedRed: Nv12Frame
    expect expectedRed.convertFrom(&picture)
    expect recorder.addFrame(&picture, expect pacer.slotAt(0))

    paintVideoWindow(&window, 0x0000FF)
    expect source.grabInto(&picture)
    var expectedBlue: Nv12Frame
    expect expectedBlue.convertFrom(&picture)
    expect recorder.addFrame(&picture, expect pacer.slotAt(1))
    expect recorder.repeatLastFrame(expect pacer.slotAt(2))

    var signal: [1_024] s16
    for frame in signal.count do
        signal[frame] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                  1_000.0 * frame / 48_000.0)))
    expect recorder.addAudioFrames(Swag.makeSlice(&signal[0], signal.count))
    expect recorder.end()
    let encodedAt = Time.monotonicMicroseconds()
    Swag.require(recorder.videoFrameCount() == 3 and recorder.repeatedFrameCount() == 1)

    var reader = expect Reader.open(path)
    let readAt = Time.monotonicMicroseconds()
    Swag.require(reader.frameCount() == 3 and reader.audioTrackCount() == 1)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    Swag.require(Slice.equals(decoded.luma.toSlice(), expectedRed.luma()))
    expect reader.decodeFramePlanesInto(&decoded, 1)
    Swag.require(Slice.equals(decoded.luma.toSlice(), expectedBlue.luma()))
    expect reader.decodeFramePlanesInto(&decoded, 2)
    Swag.require(Slice.equals(decoded.luma.toSlice(), expectedBlue.luma()))
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == signal.count)
    var pcm: Array's16
    expect sound.decodePcm16(func|pcm = &pcm|(part: const [..] s16)->bool
    {
        pcm.add(part)
        return true
    })
    Swag.require(pcm.count == signal.count)
    var power = 0.0'f64
    for sample in pcm do
        power += cast(f64, sample) * sample
    Swag.require(Math.sqrt(power / pcm.count) > 3_000)
    Console.printf("X11 software MP4 integration: setup % us, encode % us, open % us, decode % us\n",
                   openedAt - started, encodedAt - openedAt, readAt - encodedAt,
                   Time.monotonicMicroseconds() - readAt)
}

// The app session repeats missed slots and recovers from a failed screen read with AAC sound.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var window = expect Env.createWindow({identifier: "capture-video-session",
                                          title: "Video session fixture",
                                          width: 64, height: 48,
                                          stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintVideoWindow(&window, 0xFF0000)
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-session-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice}]
    var session = expect VideoCaptureSession.create(
        path, {10, 20, 64, 48}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    Swag.require(not session.hasCaptureOrigin() and session.frameCount() == 0)
    Swag.require(expect session.captureAt(1_000_000))
    Swag.require(session.hasCaptureOrigin() and session.captureOriginTick() == 1_000_000)
    Swag.require(not (expect session.captureAt(1_005_000)))
    paintVideoWindow(&window, 0x0000FF)
    Swag.require(expect session.captureAt(1_050_000))
    Swag.require(session.frameCount() == 4 and session.repeatedFrameCount() == 2)
    session.source.x = -1
    Swag.require(not (expect session.captureAt(1_066_667)))
    Swag.require(session.frameCount() == 5 and session.repeatedFrameCount() == 3)
    Swag.require(session.sourceFailureCount() == 1)
    session.source.x = 10
    Swag.require(expect session.captureAt(1_083_334))
    var signal: [1_024] s16
    for frame in signal.count do
        signal[frame] = cast(s16, Math.round(8_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                 700.0 * frame / 48_000.0)))
    expect session.addAudioFrames(Swag.makeSlice(&signal[0], signal.count))
    expect session.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 6 and reader.audioTrackCount() == 1)
    Swag.require((unwrap reader.audioTrack(0)).sampleFrameCount() == signal.count)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    let red = decoded.luma[0]
    expect reader.decodeFramePlanesInto(&decoded, 3)
    let blue = decoded.luma[0]
    Swag.require(red != blue)
    for frame in 1'u64 until 3
    {
        expect reader.decodeFramePlanesInto(&decoded, frame)
        Swag.require(decoded.luma[0] == red)
    }
    for frame in 4'u64 until 6
    {
        expect reader.decodeFramePlanesInto(&decoded, frame)
        Swag.require(decoded.luma[0] == blue)
    }
}

// A lost source before the first picture establishes a black frame and can still recover.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var window = expect Env.createWindow({identifier: "capture-video-first-loss",
                                          title: "First frame loss fixture",
                                          width: 64, height: 48,
                                          stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintVideoWindow(&window, 0xFF0000)
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-first-loss-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    var session = expect VideoCaptureSession.create(
        path, {10, 20, 64, 48}, expect FrameRate.create(60, 1), false)
    session.source.x = -1
    Swag.require(not (expect session.captureAt(100_000)))
    Swag.require(session.frameCount() == 1 and session.sourceFailureCount() == 1)
    session.source.x = 10
    Swag.require(expect session.captureAt(116_667))
    expect session.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 2 and reader.audioTrackCount() == 0)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    let black = decoded.luma[0]
    expect reader.decodeFramePlanesInto(&decoded, 1)
    Swag.require(decoded.luma[0] != black)
}
