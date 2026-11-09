#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel, Video, Audio

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
    var noOrigin: Swag.Error
    discard catch session.captureOrigin100ns() as noOrigin
    Swag.require(noOrigin.value() is Errors.BadParameterError)
    Swag.require(expect session.captureAt(1_000_000))
    Swag.require(session.hasCaptureOrigin() and session.captureOriginTick() == 1_000_000)
    Swag.require(expect session.captureOrigin100ns() == 10_000_000)
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

// Two bounded capture queues retain microphone and system sound on independent MP4 tracks.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var window = expect Env.createWindow({identifier: "capture-video-audio-queues",
                                          title: "Two audio sources fixture",
                                          width: 32, height: 16,
                                          stopLoopOnClose: false})
    expect window.setPosition(10, 20)
    expect window.show()
    paintVideoWindow(&window, 0xFF0000)
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-two-sounds-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [2] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice},
                                                {48_000, 2, .Full}]
    var session = expect VideoCaptureSession.create(
        path, {10, 20, 32, 16}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    for frame in 7'u64 do
        Swag.require(expect session.captureAt(1_000_000 + frame * 16_667))
    let soundOrigin = expect session.captureOrigin100ns()
    var microphone = expect CaptureQueue.create(48_000, 1, soundOrigin, 10_000_000,
                                                blockFrames: 1_024, tolerance: 0)
    var system = expect CaptureQueue.create(48_000, 2, soundOrigin, 10_000_000,
                                            blockFrames: 1_024, tolerance: 0)
    var voice: [1_024] s16
    var desktop: [2 * 1_024] s16
    for frame in 1_024'u64
    {
        voice[frame] = cast(s16, Math.round(9_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                1_000.0 * frame / 48_000.0)))
        desktop[frame * 2] = voice[frame]
        desktop[frame * 2 + 1] = cast(s16, Math.round(7_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                         2_000.0 * frame / 48_000.0)))
    }
    discard expect microphone.push(Swag.makeSlice(&voice[0], voice.count), soundOrigin)
    expect microphone.markLost(soundOrigin + 213_333)
    expect microphone.markRestored(soundOrigin + 640_000)
    discard expect microphone.push(Swag.makeSlice(&voice[0], voice.count), soundOrigin + 640_000)
    discard expect system.push(Swag.makeSlice(&desktop[0], desktop.count), soundOrigin)
    Swag.require(expect system.markSilentUntil(soundOrigin + 640_000) == 2_048)
    discard expect system.push(Swag.makeSlice(&desktop[0], desktop.count), soundOrigin + 640_000)

    var micPump = expect VideoAudioPump.create(&session, &microphone, 0)
    var systemPump = expect VideoAudioPump.create(&session, &system, 1)
    for 10
    {
        let mic = expect micPump.pump(512)
        let output = expect systemPump.pump(512)
        if not mic and not output do
            break
    }
    Swag.require(micPump.inputFrameCount() == 4_096 and systemPump.inputFrameCount() == 4_096)
    Swag.require(micPump.syntheticFrameCount() == 2_048 and
                 systemPump.syntheticFrameCount() == 2_048)
    Swag.require(micPump.sourceInterruptionCount() == 1 and
                 systemPump.sourceInterruptionCount() == 0)
    expect session.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 7 and reader.audioTrackCount() == 2)
    let micSound = unwrap reader.audioTrack(0)
    let systemSound = unwrap reader.audioTrack(1)
    Swag.require(micSound.sampleFrameCount() == 4_096 and
                 systemSound.sampleFrameCount() == 4_096)
    var micPcm: Array's16
    expect micSound.decodePcm16(func|micPcm = &micPcm|(part: const [..] s16)->bool
    {
        micPcm.add(part)
        return true
    })
    var systemPcm: Array's16
    expect systemSound.decodePcm16(func|systemPcm = &systemPcm|(part: const [..] s16)->bool
    {
        systemPcm.add(part)
        return true
    })
    Swag.require(micPcm.count == 4_096 and systemPcm.count == 8_192)
    var micBefore = 0.0'f64
    var micGap = 0.0'f64
    var micAfter = 0.0'f64
    var systemBefore = 0.0'f64
    var systemGap = 0.0'f64
    var systemAfter = 0.0'f64
    for frame in 1_024'u64
    {
        micBefore += cast(f64, micPcm[frame]) * micPcm[frame]
        micGap += cast(f64, micPcm[1_024 + frame]) * micPcm[1_024 + frame]
        micAfter += cast(f64, micPcm[3_072 + frame]) * micPcm[3_072 + frame]
        systemBefore += cast(f64, systemPcm[frame * 2]) * systemPcm[frame * 2]
        systemGap += cast(f64, systemPcm[(1_024 + frame) * 2]) * systemPcm[(1_024 + frame) * 2]
        systemAfter += cast(f64, systemPcm[(3_072 + frame) * 2]) * systemPcm[(3_072 + frame) * 2]
    }
    Swag.require(Math.sqrt(micBefore / 1_024) > 3_000 and
                 Math.sqrt(micGap / 1_024) < 500 and
                 Math.sqrt(micAfter / 1_024) > 3_000)
    Swag.require(Math.sqrt(systemBefore / 1_024) > 3_000 and
                 Math.sqrt(systemGap / 1_024) < 500 and
                 Math.sqrt(systemAfter / 1_024) > 3_000)
}

// A four-hour source outage advances in bounded PCM chunks instead of one blocking call.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-long-sound-gap-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice}]
    var session = expect VideoCaptureSession.create(
        path, {0, 0, 16, 16}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    Swag.require(expect session.captureAt(0))
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000)
    var wrongChannels = expect CaptureQueue.create(48_000, 2, 0, 48_000)
    var rejected: Swag.Error
    discard catch VideoAudioPump.create(&session, &wrongChannels, 0) as rejected
    Swag.require(rejected.value() is Errors.BadParameterError)
    expect queue.markLost(4'u64 * 60 * 60 * 48_000)
    var pump = expect VideoAudioPump.create(&session, &queue, 0)
    var invalidBudget: Swag.Error
    discard catch pump.pump(0) as invalidBudget
    Swag.require(invalidBudget.value() is Errors.BadParameterError)
    discard catch pump.pump(65_537) as invalidBudget
    Swag.require(invalidBudget.value() is Errors.BadParameterError)
    Swag.require(expect pump.pump(512) == 512)
    Swag.require(pump.inputFrameCount() == 512 and pump.syntheticFrameCount() == 512)
    Swag.require(queue.pendingBlocks() == 0)
    expect session.end()
}

// Queue overflow drops old captured blocks while the MP4 timeline retains their silence.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-overflow-sound-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice}]
    var session = expect VideoCaptureSession.create(
        path, {0, 0, 16, 16}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    Swag.require(expect session.captureAt(0))
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 4, slots: 1, tolerance: 0)
    let samples: [4] s16 = [1_000, -1_000, 1_000, -1_000]
    discard expect queue.push(Swag.makeSlice(&samples[0], samples.count), 0)
    discard expect queue.push(Swag.makeSlice(&samples[0], samples.count), 4)
    discard expect queue.push(Swag.makeSlice(&samples[0], samples.count), 8)
    Swag.require(queue.droppedBlockCount() == 2 and queue.droppedFrameCount() == 8)
    var pump = expect VideoAudioPump.create(&session, &queue, 0)
    for 4 do
        Swag.require(expect pump.pump(3) == 3)
    Swag.require(expect pump.pump(3) == 0)
    Swag.require(pump.inputFrameCount() == 12 and pump.syntheticFrameCount() == 8)
    expect session.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.audioTrackCount() == 1)
    Swag.require((unwrap reader.audioTrack(0)).sampleFrameCount() == 12)
}

// A 96 kHz float device packet stream reaches the MP4 track at 48 kHz through bounded queues.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-resampled-sound-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 2, .Full}]
    var session = expect VideoCaptureSession.create(
        path, {0, 0, 16, 16}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    Swag.require(expect session.captureAt(2_000_000))
    let origin = expect session.captureOrigin100ns()
    var queue = expect CaptureQueue.create(48_000, 2, origin, 10_000_000)
    var feeder = expect CaptureResampledFeeder.create(&queue, 96_000)
    var pump = expect VideoAudioPump.create(&session, &queue, 0)
    var packet: [2 * 512] f32
    var sourceFrame = 0'u64
    while sourceFrame < 9_600
    {
        let count = Math.min(512'u64, 9_600 - sourceFrame)
        for frame in count
        {
            let phase = Math.ConstF64.TwoPi * 440.0 * (sourceFrame + frame) / 96_000.0
            packet[frame * 2] = cast(f32, 0.35 * Math.sin(phase))
            packet[frame * 2 + 1] = cast(f32, 0.25 * Math.cos(phase))
        }
        let tick = origin + (sourceFrame * 10_000_000 + 48_000) / 96_000
        expect feeder.pushFloat32(Swag.makeSlice(&packet[0], count * 2), tick, sourceFrame)
        discard expect pump.pump(512)
        sourceFrame += count
    }
    expect feeder.finish()
    for 16
    {
        if not (expect pump.pump(512)) do
            break
    }
    Swag.require(pump.inputFrameCount() == 4_800 and pump.syntheticFrameCount() == 0 and
                 queue.droppedFrameCount() == 0)
    expect session.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleRateHz() == 48_000 and sound.numChannels() == 2 and
                 sound.sampleFrameCount() == 4_800)
}

// A low-space decision closes the last complete picture into a readable MP4 before reporting it.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-space-stop-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 1, .Voice}]
    var insufficient: Swag.Error
    discard catch VideoCaptureSession.create(
        path, {0, 0, 16, 16}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count), minimumFreeSpace: Swag.U64.Max) as insufficient
    Swag.require(insufficient.value() is Swag.SystemError and not File.exists(path))
    var session = expect VideoCaptureSession.create(
        path, {0, 0, 16, 16}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count), minimumFreeSpace: 0)
    Swag.require(expect session.captureAt(0))
    Swag.require(session.frameCount() == 1)
    var sound: [512] s16
    for frame in sound.count do
        sound[frame] = cast(s16, frame % 2 ? 4_000 : -4_000)
    expect session.addAudioFrames(Swag.makeSlice(&sound[0], sound.count))
    session.minimumFreeSpace = Swag.U64.Max
    session.nextSpaceCheckTick = 0
    var stopped: Swag.Error
    discard catch session.captureAt(16_667) as stopped
    Swag.require(stopped.value() is Swag.SystemError)
    Swag.require(session.stoppedForLowStorage() and session.frameCount() == 1)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 1 and reader.audioTrackCount() == 1 and
                 (unwrap reader.audioTrack(0)).sampleFrameCount() == 512)
    expect session.end()
    discard catch session.captureAt(33_334) as stopped
    Swag.require(stopped.value() is Swag.SystemError and session.frameCount() == 1)
}

// A long interruption is represented by one held picture instead of encoding 864000 repeats.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-long-video-gap-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    var session = expect VideoCaptureSession.create(
        path, {0, 0, 16, 16}, expect FrameRate.create(60, 1), false)
    Swag.require(expect session.captureAt(0))
    Swag.require(expect session.captureAt(4'u64 * 60 * 60 * 1_000_000))
    Swag.require(session.missedFrameSlotCount() == 864_000 - 1 and
                 session.repeatedFrameCount() == 1 and session.frameCount() == 3)
    expect session.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3 and reader.audioTrackCount() == 0)
    Swag.require(reader.frameTimestamp(2) >= 14_400.0 and
                 reader.frameAtTime(7_200.0) == 1 and reader.durationInSeconds() > 14_400.0)
}
