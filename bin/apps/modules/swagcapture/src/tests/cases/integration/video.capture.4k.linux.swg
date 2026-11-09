#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel, Video

private func checkedDynamicX11(connection: *void, check: Linux.xcb_request_check_fn,
                               request: Linux.xcb_void_cookie_t)
{
    let error = check(connection, request)
    defer Linux.free(error)
    Swag.require(error == null)
}

private func has4KDesktop()->bool fail
{
    var capture = try X11Capture.create()
    return capture.screen.width_in_pixels >= 3840 and capture.screen.height_in_pixels >= 2160
}

// Measures one second of real 4K X11 acquisition, conversion, H.264 and fragmented MP4.
// Run this opt-in test on an X11 server with a 3840x2160 root, such as DISPLAY=:92.
#[Swag.TestTag("stress.capture.x11.4k")]
#test
{
    if not expect has4KDesktop() do
        return
    const Width = 3840
    const Height = 2160
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-4k60-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    var session = expect VideoCaptureSession.create(
        path, {0, 0, Width, Height}, expect FrameRate.create(60, 1), false)
    var watch: Time.Stopwatch
    watch.start()
    for frame in 60'u64 do
        Swag.require(expect session.captureAt(frame * 16_667))
    expect session.end()
    watch.stop()
    Console.printf("Real X11 software MP4 4K60: % us for 60 frames, % bytes\n",
                   watch.elapsedMicroseconds(), (expect File.info(path)).size)
    let encodedAt = Time.monotonicMicroseconds()
    Swag.require(session.frameCount() == 60 and session.repeatedFrameCount() == 0)
    var reader = expect Reader.open(path)
    let openedAt = Time.monotonicMicroseconds()
    Swag.require(reader.frameCount() == 60 and reader.audioTrackCount() == 0)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 59)
    let decodedAt = Time.monotonicMicroseconds()
    var expected: Nv12Frame
    expect expected.convertFrom(&session.picture)
    Swag.require(Slice.equals(decoded.luma.toSlice(), expected.luma()))
    Console.printf("Real X11 4K60 validation: open % us, last-frame decode % us, compare % us\n",
                   openedAt - encodedAt, decodedAt - openedAt,
                   Time.monotonicMicroseconds() - decodedAt)
}

// Measures the same 4K screen acquisition while encoding a live stereo AAC track.
#[Swag.TestTag("stress.capture.x11.4k.av")]
#test
{
    if not expect has4KDesktop() do
        return
    const Width = 3840
    const Height = 2160
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-4k60-av-%.mp4", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 2, .Full}]
    var session = expect VideoCaptureSession.create(
        path, {0, 0, Width, Height}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    var samples: [2 * 1_024] s16
    for frame in 1_024'u64
    {
        samples[frame * 2] = cast(s16, Math.round(8_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                      1_000.0 * frame / 48_000.0)))
        samples[frame * 2 + 1] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                          1_500.0 * frame / 48_000.0)))
    }
    var watch: Time.Stopwatch
    watch.start()
    var audioBlocks = 0'u64
    for frame in 60'u64
    {
        Swag.require(expect session.captureAt(frame * 16_667))
        while audioBlocks < 47 and audioBlocks * 1_024 < (frame + 1) * 800
        {
            expect session.addAudioFrames(Swag.makeSlice(&samples[0], samples.count))
            audioBlocks += 1
        }
    }
    expect session.end()
    watch.stop()
    Console.printf("Real X11 software MP4 4K60 with AAC: % us for 60 frames and 48 sound packets\n",
                   watch.elapsedMicroseconds())
    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 60 and summary.audioTracks.count == 1)
    Swag.require(summary.audioTracks[0].packetCount == 48 and not summary.hasIncompleteTail)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 60 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == 47 * 1_024)
    var pcm: Array's16
    expect sound.decodePcm16(func|pcm = &pcm|(part: const [..] s16)->bool
    {
        pcm.add(part)
        return true
    })
    Swag.require(pcm.count == 47 * 1_024 * 2)
    var power = 0.0'f64
    for sample in pcm do
        power += cast(f64, sample) * sample
    Swag.require(Math.sqrt(power / pcm.count) > 2_000)
}

// An opt-in 4K60 desktop scene changes everywhere while four textured tiles move
// across its quadrants. Painting is timed separately from capture/encode/MP4.
// Set SWAG_CAPTURE_4K_OUTPUT to a path inside the test workspace corpus to
// retain the MP4 for an external FFmpeg probe.
#[Swag.TestTag("stress.capture.x11.4k.dynamic")]
#test
{
    const Width = 3840
    const Height = 2160
    const Tile = 512'u64
    var x11 = expect X11Capture.create()
    if x11.screen.width_in_pixels < Width or x11.screen.height_in_pixels < Height do
        return
    let library = unwrap x11.library
    let connection = unwrap x11.connection
    let generate = expect X11Capture.symbol'Linux.xcb_generate_id_fn(library, "xcb_generate_id")
    let createGc = expect X11Capture.symbol'Linux.xcb_create_gc_checked_fn(library, "xcb_create_gc_checked")
    let freeGc = expect X11Capture.symbol'Linux.xcb_free_gc_checked_fn(library, "xcb_free_gc_checked")
    let put = expect X11Capture.symbol'Linux.xcb_put_image_checked_fn(library, "xcb_put_image_checked")
    let change = expect X11Capture.symbol'Linux.xcb_change_window_attributes_checked_fn(
        library, "xcb_change_window_attributes_checked")
    let clear = expect X11Capture.symbol'Linux.xcb_clear_area_checked_fn(library, "xcb_clear_area_checked")
    let check = expect X11Capture.symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let gc = generate(connection)
    checkedDynamicX11(connection, check, createGc(connection, gc, x11.screen.root, 0, null))
    defer
    {
        var black: u32
        Linux.free(check(connection, change(connection, x11.screen.root, 2, &black)))
        Linux.free(check(connection, clear(connection, 0, x11.screen.root, 0, 0, 0, 0)))
        Linux.free(check(connection, freeGc(connection, gc)))
    }

    var tile: Array'u8
    tile.resize(Tile * Tile * 4)
    for row in Tile
    {
        for column in Tile
        {
            let pixel = (row * Tile + column) * 4
            let cell = (row / 16 + column / 16) % 2
            tile[pixel]     = cast(u8, (column * 3 + row * 5) % 256)
            tile[pixel + 1] = cast(u8, (column * 7 + row * 2) % 256)
            tile[pixel + 2] = cell ? 224'u8 : 32'u8
            tile[pixel + 3] = 0
        }
    }

    let externalPath = Env.variable("SWAG_CAPTURE_4K_OUTPUT")
    let retained = not externalPath.isEmpty()
    let path = retained ? externalPath :
               Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("swag-capture-4k60-dynamic-%.mp4", Guid64.random()).toString())
    defer
    {
        if not retained do
            discard catch File.delete(path)
    }
    let configs: [1] Mp4.SoftwareAudioConfig = [{48_000, 2, .Full}]
    var session = expect VideoCaptureSession.create(
        path, {0, 0, Width, Height}, expect FrameRate.create(60, 1), false,
        Swag.makeSlice(&configs[0], configs.count))
    var samples: [2 * 1_024] s16
    for frame in 1_024'u64
    {
        samples[frame * 2] = cast(s16, Math.round(8_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                      1_000.0 * frame / 48_000.0)))
        samples[frame * 2 + 1] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                          1_500.0 * frame / 48_000.0)))
    }

    var paintMicros = 0'u64
    var videoMicros = 0'u64
    var soundMicros = 0'u64
    var audioBlocks = 0'u64
    for frame in 60'u64
    {
        let paintStart = Time.monotonicMicroseconds()
        let red = cast(u32, (frame * 5) % 64)
        let green = cast(u32, (frame * 3) % 64)
        let blue = cast(u32, (frame * 7) % 64)
        let background = red << 16 | green << 8 | blue
        checkedDynamicX11(connection, check, change(connection, x11.screen.root, 2, &background))
        checkedDynamicX11(connection, check, clear(connection, 0, x11.screen.root, 0, 0, 0, 0))
        for quadrant in 4'u64
        {
            let destinationX = cast(s16, (quadrant % 2) * 1_920 + 32 + frame * 16)
            let destinationY = cast(s16, (quadrant / 2) * 1_080 + 32 + frame * 8)
            checkedDynamicX11(connection, check,
                              put(connection, 2, x11.screen.root, gc,
                                  cast(u16, Tile), cast(u16, Tile), destinationX, destinationY,
                                  0, x11.screen.root_depth, cast(u32, tile.count), tile.storage()))
        }
        paintMicros += Time.monotonicMicroseconds() - paintStart

        let videoStart = Time.monotonicMicroseconds()
        Swag.require(expect session.captureAt(frame * 16_667))
        videoMicros += Time.monotonicMicroseconds() - videoStart
        let soundStart = Time.monotonicMicroseconds()
        while audioBlocks < 47 and audioBlocks * 1_024 < (frame + 1) * 800
        {
            expect session.addAudioFrames(Swag.makeSlice(&samples[0], samples.count))
            audioBlocks += 1
        }
        soundMicros += Time.monotonicMicroseconds() - soundStart
    }
    let finalizeStart = Time.monotonicMicroseconds()
    expect session.end()
    let finalizeMicros = Time.monotonicMicroseconds() - finalizeStart

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 60 and summary.audioTracks.count == 1 and
                 summary.audioTracks[0].packetCount == 48 and not summary.hasIncompleteTail)
    Swag.require(session.frameCount() == 60 and session.repeatedFrameCount() == 0 and
                 session.sourceFailureCount() == 0)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 60 and reader.audioTrackCount() == 1)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    Swag.require(decoded.width == Width and decoded.height == Height and
                 decoded.luma.count == cast(u64, Width) * Height)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == 47 * 1_024)
    var pcm: Array's16
    expect sound.decodePcm16(func|pcm = &pcm|(part: const [..] s16)->bool
    {
        pcm.add(part)
        return true
    })
    Swag.require(pcm.count == 47 * 1_024 * 2)
    Console.printf("Dynamic X11 4K60: paint % us, video capture+encode+MP4 % us, AAC % us, finalize % us, file % bytes at %\n",
                   paintMicros, videoMicros, soundMicros, finalizeMicros,
                   (expect File.info(path)).size, path)
}
