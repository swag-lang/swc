#global if #os == Swag.TargetOs.Linux
#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The opt-in native test uses SDL's disk device. It never opens a physical audio device.
// The harness supplies a private SDL_DISKAUDIOFILE path and SDL_AUDIODRIVER=disk.
func audioStartDiskEngine()
{
    Swag.require(Env.variable("SDL_AUDIODRIVER") == "disk")
    Swag.require(Env.variable("SDL_DISKAUDIOFILE").count != 0)

    // The public entry point deliberately selects NoSound in a sandbox. Exercise the
    // same native driver beneath that policy, only after verifying the virtual sink.
    discard expect g_Driver.create(.Default)
    Swag.require(activeDriverKind() == .FAudio)
}

func audioMakeTestTone()->String
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("faudio-tone-%.wav", Guid64.random()))
    var bytes = expect File.readAllBytes(audioGetTestDataPath("pcm16_stereo.wav"))
    bytes.resize(44)
    var writer = ByteStream.openWrite(&bytes)
    writer.setPosition(4)
    writer.writeLittleEndian(36'u32 + 44100 * 4)
    writer.setPosition(40)
    writer.writeLittleEndian(44100'u32 * 4)

    // Two unequal channels make downmixing observable. A square wave also gives an
    // unambiguous frequency measurement without depending on the resampler's edges.
    for index in 44100
    {
        let sample = index % 100 < 50 ? 16384's16 : -16384's16
        writer.writeLittleEndian(sample)
        writer.writeLittleEndian(cast(s16, -sample / 2))
    }

    discard expect File.writeAllBytes(path, bytes.toSlice())
    return path
}

func audioWaitForFrame(voice: *Voice, frame: u64)
{
    for 3000
    {
        if voice.playbackSampleFrame() >= frame do
            return
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(false, "native audio cursor did not advance")
}

struct AudioDiskMeasurement
{
    peakLeft, peakRight:        f32
    transitions, audibleFrames: u64
}

func audioMeasureDisk()->AudioDiskMeasurement
{
    let data = expect File.readAllBytes(Env.variable("SDL_DISKAUDIOFILE"))
    Swag.require(data.count > 4096 and data.count % 8 == 0)
    let samples  = cast(const [*] f32, data.storage())
    var result: #returntype
    var previous = 0'f32
    for index in data.count / 8
    {
        let left  = samples[index * 2]
        let right = samples[index * 2 + 1]
        Swag.require(Math.isFinite(left) and Math.isFinite(right))
        result.peakLeft  = Math.max(result.peakLeft, Math.abs(left))
        result.peakRight = Math.max(result.peakRight, Math.abs(right))
        if Math.abs(left) > 0.0001
        {
            result.audibleFrames += 1
            if previous * left < 0 do
                result.transitions += 1
            previous = left
        }
    }

    Swag.require(result.audibleFrames > 4000)
    return result
}

func audioRenderDisk(path: string, routing: u32, pitch: f32)->AudioDiskMeasurement
{
    var file = expect SoundFile.load(path, preloadData: false)
    audioStartDiskEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&file)
    discard expect voice.setFrequencyRatio(pitch)
    if routing != 0
    {
        let root  = expect Bus.create(2)
        let child = expect Bus.create(1, root)
        discard expect root.setVolume(0.5)
        discard expect child.setVolume(0.5)
        discard expect voice.setVolume(0.8)
        discard expect setOutputVolume(0.5)
        if routing == 1 do
            discard expect voice.setRouting([child])
        else do
            discard expect voice.setRouting([root, child])
    }

    discard expect voice.play()
    audioWaitForFrame(voice, 16000)
    discard expect voice.stop()
    destroyEngine()     // Closes/flushed SDL's file before the measurement reads it.
    return audioMeasureDisk()
}

#[Swag.TestTag("integration.audio.faudio")]
#test
{
    let path = audioMakeTestTone()
    defer discard catch File.delete(path)
    let normal = audioRenderDisk(path, 0, 1)
    audioAssertFloat(normal.peakLeft, 0.5, 0.01)
    audioAssertFloat(normal.peakRight, 0.25, 0.01)
    let fast = audioRenderDisk(path, 0, 2)
    let frequencyRatio = cast(f64, fast.transitions) / cast(f64, fast.audibleFrames) /
                         (cast(f64, normal.transitions) / cast(f64, normal.audibleFrames))
    Swag.require(frequencyRatio > 1.9 and frequencyRatio < 2.1)

    let nested = audioRenderDisk(path, 1, 1)

    // Stereo -> mono averages 0.5 and -0.25, then child/root/voice/master gains apply.
    audioAssertFloat(nested.peakLeft, 0.0125, 0.001)
    audioAssertFloat(nested.peakRight, 0.0125, 0.001)
    let multiple = audioRenderDisk(path, 2, 1)
    audioAssertFloat(multiple.peakLeft, 0.1125, 0.002)
    audioAssertFloat(multiple.peakRight, 0.0375, 0.002)
}

#[Swag.TestTag("integration.audio.faudio")]
#test
{
    let path = audioMakeTestTone()
    defer discard catch File.delete(path)
    var file = expect SoundFile.load(path, preloadData: false)
    for 3
    {
        audioStartDiskEngine()
        let voice = expect Voice.create(&file)
        discard expect voice.play(.Loop)
        audioWaitForFrame(voice, 8000)
        discard expect voice.pause()
        let paused = voice.playbackSampleFrame()
        Threading.Thread.sleep(30'ms)
        Swag.require(voice.playbackSampleFrame() == paused)
        discard expect voice.seekSampleFrame(22050)
        Swag.require(voice.playbackSampleFrame() == 22050)
        discard expect voice.play(.Loop)
        audioWaitForFrame(voice, 25000)
        discard expect voice.stop()
        Swag.require(voice.playbackSampleFrame() == 0)
        discard expect voice.play(.Loop)
        audioWaitForFrame(voice, 44100)
        Threading.Thread.sleep(30'ms)
        Swag.require(voice.isPlaying())

        // Teardown must join callbacks before releasing the streaming buffers/context.
        destroyEngine()
        Swag.require(not isEngineCreated())
        destroyEngine()
    }
}

// Packet decoding, callback refills, and the native six-channel downmix run together.
#[Swag.TestTag("integration.audio.faudio")]
#test
{
    var file = expect SoundFile.load(audioGetTestDataPath("flac-5.1-48000.flac"))
    audioStartDiskEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&file)
    Swag.require(voice.requestedEncoding == .Pcm16)
    discard expect voice.play()
    audioWaitForFrame(voice, 18000)
    discard expect voice.stop()
    destroyEngine()
    let captured = audioMeasureDisk()
    Swag.require(captured.peakLeft > 0.01 and captured.peakRight > 0.01)
    Swag.require(captured.peakLeft <= 1 and captured.peakRight <= 1)
}

// Run separately with SDL_AUDIODRIVER=swag-unavailable. Failure must release all
// partially initialized native/context state and leave the engine reusable.
#[Swag.TestTag("integration.audio.faudio.unavailable")]
#test
{
    Swag.require(Env.variable("SDL_AUDIODRIVER") == "swag-unavailable")
    for 3
    {
        var error: Swag.Error
        catch g_Driver.create(.FAudio) as error
        Swag.require(error.value() is Swag.SystemError)
        Swag.require(not isEngineCreated())
        Swag.require(activeDriverKind() == .Default)
        discard expect createNoSoundEngine()
        destroyEngine()
    }
}
