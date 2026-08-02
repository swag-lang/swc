#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func audioStartNoSoundEngine()
{
    discard expect createNoSoundEngine()
    @assert(g_Driver.kind == .NoSound)
}

#test
{
    @assert(!isEngineCreated())
    discard catch outputVolume() as errNoEngine
    @assert(errNoEngine is Errors.BadParameterError)

    discard expect createEngine(.NoSound)
    @assert(isEngineCreated())
    @assert(activeDriverKind() == .NoSound)

    discard catch createEngine(.NoSound) as errDuplicate
    @assert(errDuplicate is Errors.BadParameterError)

    discard catch Bus.create(0) as errChannels
    @assert(errChannels is Errors.BadParameterError)

    var emptyFile: SoundFile
    discard catch Voice.create(&emptyFile) as errFile
    @assert(errFile is Errors.BadParameterError)

    destroyEngine()
    @assert(!isEngineCreated())
    @assert(activeDriverKind() == .Default)
    destroyEngine()     // Repeated shutdown is a no-op.
}

#test
{
    discard expect createEngine(.NoSound)
    @assert(g_Driver.kind == .NoSound)
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

    let rootResult = expect Bus.create(2)
    let root       = notnull rootResult

    let childResult = expect Bus.create(1, root)
    let child       = notnull childResult

    let rootHandle  = cast(*NoSoundBus) notnull root.handle
    let childHandle = cast(*NoSoundBus) notnull child.handle
    @assert(rootHandle.numChannels == 2)
    @assert(rootHandle.parent == null)
    @assert(childHandle.numChannels == 1)
    @assert(childHandle.parent == root)
    @assert(root.channelCount == 2)
    @assert(root.parent == null)
    @assert(child.channelCount == 1)
    @assert(child.parent == root)
    @assert(g_Driver.buses.count == 2)

    discard expect child.setVolume(1.5)
    audioAssertFloat(expect child.volume(), 1)
    discard expect child.setVolumeDb(-6.0206)
    audioAssertFloat(expect child.volume(), 0.5, 0.0002)
    audioAssertFloat(expect child.volumeDb(), -6.0206, 0.0002)
    var invalidParent: Bus
    discard catch Bus.create(1, &invalidParent) as err12
    @assert(err12 is Errors.BadParameterError)

    child.destroy()
    root.destroy()
    @assert(g_Driver.buses.count == 0)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file        = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voiceResult = expect Voice.create(&file)
    let voice       = notnull voiceResult
    let handle      = cast(*NoSoundVoice) notnull voice.handle
    @assert(voice.requestedEncoding == .Pcm16)
    @assert(!voice.isPlaying())

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
    discard catch voice.setFrequencyRatio(0) as errInvalidRatio
    @assert(errInvalidRatio is Errors.BadParameterError)

    let bus0Result = expect Bus.create(2)
    let safeBus0   = notnull bus0Result

    let bus1Result = expect Bus.create(2, safeBus0)
    let safeBus1   = notnull bus1Result
    discard expect voice.setRouting([safeBus0, safeBus1])
    @assert(handle.busCount == 2)
    @assert(handle.buses[0] == safeBus0)
    @assert(handle.buses[1] == safeBus1)

    discard expect voice.play()
    @assert(voice.isPlaying())
    @assert(handle.isPlaying)

    discard expect voice.pause()
    @assert(!voice.isPlaying())
    @assert(!handle.isPlaying)

    discard expect voice.play(.Loop)
    let shouldKeepUpdating = expect voice.updateNoSound()
    @assert(shouldKeepUpdating)
    @assert(handle.isPlaying)

    discard expect voice.stop()
    @assert(!voice.isPlaying())
    @assert(!handle.isPlaying)
    @assert(voice.streamCurSeek == 0)

    voice.destroy()
}

// Audio resources retain the engine allocator even when callers temporarily
// install a different allocator before constructing them.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file              = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), preloadData: false)
    let context           = @getcontext()
    let originalAllocator = notnull context.allocator
    var scratch: ScratchAllocator
    scratch.setCapacity(1024 * 1024, originalAllocator)
    defer scratch.release()
    defer context.allocator = originalAllocator

    let scratchAllocator: IAllocator = &scratch
    context.allocator = scratchAllocator

    let busResult   = catch Bus.create(2) as errBus
    let voiceResult = catch Voice.create(&file) as errVoice
    @assert(errBus == null)
    @assert(errVoice == null)
    @assert(busResult != null)
    @assert(voiceResult != null)

    context.allocator = originalAllocator
    destroyEngine()
    @assert(!isEngineCreated())
}

// A full stop closes a lazily opened streaming file and rewinds the source.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file  = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), preloadData: false)
    let voice = notnull (expect Voice.create(&file))
    discard expect voice.play()
    discard expect voice.updateNoSound()
    @assert(voice.stream.isOpen())

    discard expect voice.stop()
    @assert(!voice.stream.isOpen())
    @assert(voice.streamCurSeek == 0)
    voice.destroy()
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file        = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voiceResult = expect Voice.create(&file)
    let voice       = notnull voiceResult
    let handle      = cast(*NoSoundVoice) notnull voice.handle

    discard expect voice.play()
    let shouldKeepUpdating = expect voice.updateNoSound()
    @assert(!shouldKeepUpdating)
    @assert(!handle.isPlaying)
    @assert(voice.streamCurSeek == file.dataSize)

    voice.destroy()
}
