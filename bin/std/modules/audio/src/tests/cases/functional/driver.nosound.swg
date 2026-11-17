#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func checkBusCreation(channelCount: u32, parent: *Bus? = null) fail { (try Bus.create(channelCount, parent)).destroy() }
func checkVoiceCreation(file: const *SoundFile) fail { (try Voice.create(file)).destroy() }

func audioStartNoSoundEngine()
{
    discard expect createNoSoundEngine()
    Swag.require(g_Driver.kind == .NoSound)
}

// Ordinary sandboxed applications stay silent even when asking for the default native driver.
#test
{
    Swag.require(Env.isSandboxed())
    Swag.require(not Env.hasArgument("swag.audio.native-output=true"))
    expect createEngine()
    defer destroyEngine()
    Swag.require(activeDriverKind() == .NoSound)
}

#test
{
    Swag.require(not isEngineCreated())
    var errNoEngineOutcome: Swag.Error
    discard catch outputVolume() as errNoEngineOutcome
    let errNoEngine = errNoEngineOutcome.value()
    Swag.require((errNoEngine is Errors.BadParameterError))

    discard expect createEngine(.NoSound)
    Swag.require(isEngineCreated())
    Swag.require(activeDriverKind() == .NoSound)

    var errDuplicateOutcome: Swag.Error
    discard catch createEngine(.NoSound) as errDuplicateOutcome
    let errDuplicate = errDuplicateOutcome.value()
    Swag.require((errDuplicate is Errors.BadParameterError))

    var errChannelsOutcome: Swag.Error
    catch checkBusCreation(0) as errChannelsOutcome
    let errChannels = errChannelsOutcome.value()
    Swag.require((errChannels is Errors.BadParameterError))

    var emptyFile:      SoundFile
    var errFileOutcome: Swag.Error
    catch checkVoiceCreation(&emptyFile) as errFileOutcome
    let errFile = errFileOutcome.value()
    Swag.require((errFile is Errors.BadParameterError))

    destroyEngine()
    Swag.require(not isEngineCreated())
    Swag.require(activeDriverKind() == .Default)
    destroyEngine()     // Repeated shutdown is a no-op.
}

#test
{
    discard expect createEngine(.NoSound)
    Swag.require(g_Driver.kind == .NoSound)
    defer destroyEngine()

    audioAssertFloat(expect outputVolume(), 1)
    discard expect setOutputVolume(0.25)
    audioAssertFloat(expect outputVolume(), 0.25)
    discard expect setOutputVolume(2)
    audioAssertFloat(expect outputVolume(), 1)
    discard expect setOutputVolumeDb(-6.0206)
    audioAssertFloat(expect outputVolume(), 0.5, 0.0002)
    audioAssertFloat(expect outputVolumeDb(), -6.0206, 0.0002)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    let root = expect Bus.create(2)
    #assert(#typeof(root) == *Bus)

    let child = expect Bus.create(1, root)

    let rootHandle  = cast(*NoSoundBus, unwrap root.handle)
    let childHandle = cast(*NoSoundBus, unwrap child.handle)
    Swag.require(rootHandle.numChannels == 2)
    Swag.require(rootHandle.parent == null)
    Swag.require(childHandle.numChannels == 1)
    Swag.require(childHandle.parent == root)
    Swag.require(root.channelCount == 2)
    Swag.require(root.parent == null)
    Swag.require(child.channelCount == 1)
    Swag.require(child.parent == root)
    Swag.require(g_Driver.buses.count == 2)

    discard expect child.setVolume(1.5)
    audioAssertFloat(expect child.volume(), 1)
    discard expect child.setVolumeDb(-6.0206)
    audioAssertFloat(expect child.volume(), 0.5, 0.0002)
    audioAssertFloat(expect child.volumeDb(), -6.0206, 0.0002)
    var invalidParent: Bus
    var err12Outcome:  Swag.Error
    catch checkBusCreation(1, &invalidParent) as err12Outcome
    let err12 = err12Outcome.value()
    Swag.require((err12 is Errors.BadParameterError))

    child.destroy()
    root.destroy()
    Swag.require(g_Driver.buses.isEmpty())
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file  = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voice = expect Voice.create(&file)
    #assert(#typeof(voice) == *Voice)
    let handle = cast(*NoSoundVoice, unwrap voice.handle)
    Swag.require(voice.requestedEncoding == .Pcm16)
    Swag.require(not voice.isPlaying())

    discard expect voice.setVolume(1.5)
    audioAssertFloat(expect voice.volume(), 1)
    discard expect voice.setVolume(-0.25)
    audioAssertFloat(expect voice.volume(), 0)
    discard expect voice.setVolumeDb(-6.0206)
    audioAssertFloat(expect voice.volume(), 0.5, 0.0002)
    audioAssertFloat(expect voice.volumeDb(), -6.0206, 0.0002)
    discard expect voice.setFrequencyRatio(1.75)
    audioAssertFloat(handle.frequencyRatio, 1.75)
    audioAssertFloat(expect voice.frequencyRatio(), 1.75)
    var errInvalidRatioOutcome: Swag.Error
    discard catch voice.setFrequencyRatio(0) as errInvalidRatioOutcome
    let errInvalidRatio = errInvalidRatioOutcome.value()
    Swag.require((errInvalidRatio is Errors.BadParameterError))
    discard catch voice.setFrequencyRatio(Swag.F32.NaN) as errInvalidRatioOutcome
    Swag.require(errInvalidRatioOutcome.value() is Errors.BadParameterError)
    let infiniteRatio = Swag.F32.Max * 2
    discard catch voice.setFrequencyRatio(infiniteRatio) as errInvalidRatioOutcome
    Swag.require(errInvalidRatioOutcome.value() is Errors.BadParameterError)
    audioAssertFloat(handle.frequencyRatio, 1.75)

    let fixedVoice = expect Voice.create(&file, .None)
    let fixedHandle = cast(*NoSoundVoice, unwrap fixedVoice.handle)
    var errPitchControlOutcome: Swag.Error
    discard catch fixedVoice.setFrequencyRatio(1.25) as errPitchControlOutcome
    Swag.require(errPitchControlOutcome.value() is Errors.BadParameterError)
    audioAssertFloat(fixedHandle.frequencyRatio, 1)
    fixedVoice.destroy()

    let safeBus0 = expect Bus.create(2)

    let safeBus1 = expect Bus.create(2, safeBus0)
    discard expect voice.setRouting([safeBus0, safeBus1])
    Swag.require(handle.busCount == 2)
    Swag.require(handle.buses[0] == safeBus0)
    Swag.require(handle.buses[1] == safeBus1)

    discard expect voice.play()
    Swag.require(voice.isPlaying())
    Swag.require(handle.isPlaying)

    discard expect voice.pause()
    Swag.require(not voice.isPlaying())
    Swag.require(not handle.isPlaying)

    discard expect voice.play(.Loop)
    for 4
    {
        discard expect voice.pause()
        Swag.require(not voice.isPlaying() and not handle.isPlaying)
        discard expect voice.play(.Loop)
        Swag.require(voice.isPlaying() and handle.isPlaying)
    }

    let shouldKeepUpdating = expect voice.updateNoSound()
    Swag.require(shouldKeepUpdating)
    Swag.require(handle.isPlaying)

    discard expect voice.stop()
    Swag.require(not voice.isPlaying())
    Swag.require(not handle.isPlaying)
    Swag.require(voice.streamCurSeek == 0)

    voice.destroy()
}

// The convenience overload creates, registers, and starts a voice in one operation.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file  = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voice = expect Voice.play(&file, .Default, .Loop)
    let handle = cast(*NoSoundVoice, unwrap voice.handle)
    Swag.require(voice.isPlaying() and handle.isPlaying)
    voice.destroy()
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    let monoCenter = expect voicePanMatrix(1, 0)
    audioAssertFloat(monoCenter[0], Math.sqrt(0.5'f32))
    audioAssertFloat(monoCenter[1], Math.sqrt(0.5'f32))
    let monoLeft = expect voicePanMatrix(1, -1)
    audioAssertFloat(monoLeft[0], 1)
    audioAssertFloat(monoLeft[1], 0)
    let monoRight = expect voicePanMatrix(1, 1)
    audioAssertFloat(monoRight[0], 0)
    audioAssertFloat(monoRight[1], 1)
    let stereoCenter = expect voicePanMatrix(2, 0)
    audioAssertFloat(stereoCenter[0], 1)
    audioAssertFloat(stereoCenter[1], 0)
    audioAssertFloat(stereoCenter[2], 0)
    audioAssertFloat(stereoCenter[3], 1)
    let stereoLeft = expect voicePanMatrix(2, -1)
    audioAssertFloat(stereoLeft[0], 1)
    audioAssertFloat(stereoLeft[3], 0)
    let stereoRight = expect voicePanMatrix(2, 1)
    audioAssertFloat(stereoRight[0], 0)
    audioAssertFloat(stereoRight[3], 1)

    var monoFile   = expect SoundFile.load(audioGetTestDataPath("pcm8_mono_odd.wav"))
    var stereoFile = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let monoVoice   = expect Voice.create(&monoFile)
    let stereoVoice = expect Voice.create(&stereoFile)
    let monoBus     = expect Bus.create(1)
    let stereoBus   = expect Bus.create(2)
    let monoHandle  = cast(*NoSoundVoice, unwrap monoVoice.handle)
    let stereoHandle = cast(*NoSoundVoice, unwrap stereoVoice.handle)

    expect monoVoice.setRouting([monoBus])
    var monoRouteOutcome: Swag.Error
    discard catch monoVoice.setPan(-0.5) as monoRouteOutcome
    Swag.require(monoRouteOutcome.value() is Errors.BadParameterError)
    Swag.require((expect monoVoice.pan()) == 0 and monoHandle.pan == 0)

    expect monoVoice.setRouting([stereoBus])
    expect monoVoice.setPan(-2)
    Swag.require((expect monoVoice.pan()) == -1 and monoHandle.pan == -1)
    expect monoVoice.setPan(2)
    Swag.require((expect monoVoice.pan()) == 1 and monoHandle.pan == 1)
    expect monoVoice.setPan(0)
    Swag.require((expect monoVoice.pan()) == 0 and monoHandle.pan == 0)

    expect stereoVoice.setRouting([stereoBus])
    expect stereoVoice.setPan(0.25)
    var stereoRouteOutcome: Swag.Error
    discard catch stereoVoice.setRouting([monoBus]) as stereoRouteOutcome
    Swag.require(stereoRouteOutcome.value() is Errors.BadParameterError)
    Swag.require(stereoHandle.busCount == 1 and stereoHandle.buses[0] == stereoBus)

    var nonFiniteOutcome: Swag.Error
    discard catch stereoVoice.setPan(Swag.F32.NaN) as nonFiniteOutcome
    Swag.require(nonFiniteOutcome.value() is Errors.BadParameterError)
    discard catch stereoVoice.setPan(Swag.F32.Max * 2) as nonFiniteOutcome
    Swag.require(nonFiniteOutcome.value() is Errors.BadParameterError)
    Swag.require((expect stereoVoice.pan()) == 0.25 and stereoHandle.pan == 0.25)

    expect monoVoice.setRouting([])
    expect stereoVoice.setRouting([])
    monoVoice.destroy()
    stereoVoice.destroy()
    monoBus.destroy()
    stereoBus.destroy()
}

// Routing accepts the full backend limit, rejects one extra bus without changing the route,
// and an empty route restores the mastering output.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voice = expect Voice.create(&file)
    let handle = cast(*NoSoundVoice, unwrap voice.handle)
    var buses: Array'*Bus
    for 17 do
        buses.add(expect Bus.create(2))
    defer
    {
        for index in buses.count do
            buses[buses.count - 1 - index].destroy()
    }

    expect voice.setRouting(buses.toSlice()[0 until 16])
    Swag.require(handle.busCount == 16)
    for index in 16 do
        Swag.require(handle.buses[index] == buses[index])

    var tooManyOutcome: Swag.Error
    discard catch voice.setRouting(buses.toSlice()) as tooManyOutcome
    Swag.require(tooManyOutcome.value() is Errors.BadParameterError)
    Swag.require(handle.busCount == 16)
    for index in 16 do
        Swag.require(handle.buses[index] == buses[index])

    var invalidBus: Bus
    var invalidRouteOutcome: Swag.Error
    discard catch voice.setRouting([buses[0], &invalidBus]) as invalidRouteOutcome
    Swag.require(invalidRouteOutcome.value() is Errors.BadParameterError)
    Swag.require(handle.busCount == 16)
    for index in 16 do
        Swag.require(handle.buses[index] == buses[index])

    expect voice.setRouting([buses[0]])
    Swag.require(handle.busCount == 1 and handle.buses[0] == buses[0])
    for index in 1 until 16 do
        Swag.require(handle.buses[index] == null)

    expect voice.setRouting([])
    Swag.require(handle.busCount == 0)
    for index in 16 do
        Swag.require(handle.buses[index] == null)
    voice.destroy()
}

// Audio resources retain the engine allocator even when callers temporarily
// install a different allocator before constructing them.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file    = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), preloadData: false)
    let context = Swag.getContext()
    let originalAllocator = unwrap context.allocator
    var scratch: ScratchAllocator
    scratch.setCapacity(1024 * 1024, originalAllocator)
    defer scratch.release()
    defer context.allocator = originalAllocator

    let scratchAllocator: IAllocator = &scratch
    context.allocator = scratchAllocator

    discard expect Bus.create(2)
    discard expect Voice.create(&file)

    context.allocator = originalAllocator
    destroyEngine()
    Swag.require(not isEngineCreated())
}

// A full stop closes a lazily opened streaming file and rewinds the source.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file  = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), preloadData: false)
    let voice = expect Voice.create(&file)
    discard expect voice.play()
    discard expect voice.updateNoSound()
    Swag.require(voice.stream.isOpen())

    discard expect voice.stop()
    Swag.require(not voice.stream.isOpen())
    Swag.require(voice.streamCurSeek == 0)
    voice.destroy()
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file   = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voice  = expect Voice.create(&file)
    let handle = cast(*NoSoundVoice, unwrap voice.handle)

    discard expect voice.play()
    let shouldKeepUpdating = expect voice.updateNoSound()
    Swag.require(not shouldKeepUpdating)
    Swag.require(not handle.isPlaying)
    Swag.require(voice.streamCurSeek == file.dataSize)

    voice.destroy()
}
