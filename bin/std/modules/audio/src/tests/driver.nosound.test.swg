#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func audioStartNoSoundEngine()
{
    discard expect createNoSoundEngine()
    Swag.assert(g_Driver.kind == .NoSound)
}

#test
{
    Swag.assert(!isEngineCreated())
    discard catch outputVolume() as errNoEngine
    Swag.assert(errNoEngine is Errors.BadParameterError)

    discard expect createEngine(.NoSound)
    Swag.assert(isEngineCreated())
    Swag.assert(activeDriverKind() == .NoSound)

    discard catch createEngine(.NoSound) as errDuplicate
    Swag.assert(errDuplicate is Errors.BadParameterError)

    discard catch Bus.create(0) as errChannels
    Swag.assert(errChannels is Errors.BadParameterError)

    var emptyFile: SoundFile
    discard catch Voice.create(&emptyFile) as errFile
    Swag.assert(errFile is Errors.BadParameterError)

    destroyEngine()
    Swag.assert(!isEngineCreated())
    Swag.assert(activeDriverKind() == .Default)
    destroyEngine()     // Repeated shutdown is a no-op.
}

#test
{
    discard expect createEngine(.NoSound)
    Swag.assert(g_Driver.kind == .NoSound)
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
    let root       = rootResult!

    let childResult = expect Bus.create(1, root)
    let child       = childResult!

    let rootHandle  = cast(*NoSoundBus) root.handle!
    let childHandle = cast(*NoSoundBus) child.handle!
    Swag.assert(rootHandle.numChannels == 2)
    Swag.assert(rootHandle.parent == null)
    Swag.assert(childHandle.numChannels == 1)
    Swag.assert(childHandle.parent == root)
    Swag.assert(root.channelCount == 2)
    Swag.assert(root.parent == null)
    Swag.assert(child.channelCount == 1)
    Swag.assert(child.parent == root)
    Swag.assert(g_Driver.buses.count == 2)

    discard expect child.setVolume(1.5)
    audioAssertFloat(expect child.volume(), 1)
    discard expect child.setVolumeDb(-6.0206)
    audioAssertFloat(expect child.volume(), 0.5, 0.0002)
    audioAssertFloat(expect child.volumeDb(), -6.0206, 0.0002)
    var invalidParent: Bus
    discard catch Bus.create(1, &invalidParent) as err12
    Swag.assert(err12 is Errors.BadParameterError)

    child.destroy()
    root.destroy()
    Swag.assert(g_Driver.buses.count == 0)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file        = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voiceResult = expect Voice.create(&file)
    let voice       = voiceResult!
    let handle      = cast(*NoSoundVoice) voice.handle!
    Swag.assert(voice.requestedEncoding == .Pcm16)
    Swag.assert(!voice.isPlaying())

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
    Swag.assert(errInvalidRatio is Errors.BadParameterError)

    let bus0Result = expect Bus.create(2)
    let safeBus0   = bus0Result!

    let bus1Result = expect Bus.create(2, safeBus0)
    let safeBus1   = bus1Result!
    discard expect voice.setRouting([safeBus0, safeBus1])
    Swag.assert(handle.busCount == 2)
    Swag.assert(handle.buses[0] == safeBus0)
    Swag.assert(handle.buses[1] == safeBus1)

    discard expect voice.play()
    Swag.assert(voice.isPlaying())
    Swag.assert(handle.isPlaying)

    discard expect voice.pause()
    Swag.assert(!voice.isPlaying())
    Swag.assert(!handle.isPlaying)

    discard expect voice.play(.Loop)
    for 4
    {
        discard expect voice.pause()
        Swag.assert(!voice.isPlaying() and !handle.isPlaying)
        discard expect voice.play(.Loop)
        Swag.assert(voice.isPlaying() and handle.isPlaying)
    }

    let shouldKeepUpdating = expect voice.updateNoSound()
    Swag.assert(shouldKeepUpdating)
    Swag.assert(handle.isPlaying)

    discard expect voice.stop()
    Swag.assert(!voice.isPlaying())
    Swag.assert(!handle.isPlaying)
    Swag.assert(voice.streamCurSeek == 0)

    voice.destroy()
}

// Audio resources retain the engine allocator even when callers temporarily
// install a different allocator before constructing them.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file              = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), preloadData: false)
    let context           = Swag.getContext()
    let originalAllocator = context.allocator!
    var scratch: ScratchAllocator
    scratch.setCapacity(1024 * 1024, originalAllocator)
    defer scratch.release()
    defer context.allocator = originalAllocator

    let scratchAllocator: IAllocator = &scratch
    context.allocator = scratchAllocator

    let busResult   = catch Bus.create(2) as errBus
    let voiceResult = catch Voice.create(&file) as errVoice
    Swag.assert(errBus == null)
    Swag.assert(errVoice == null)
    Swag.assert(busResult != null)
    Swag.assert(voiceResult != null)

    context.allocator = originalAllocator
    destroyEngine()
    Swag.assert(!isEngineCreated())
}

// A full stop closes a lazily opened streaming file and rewinds the source.
#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file  = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), preloadData: false)
    let voice = (expect Voice.create(&file))!
    discard expect voice.play()
    discard expect voice.updateNoSound()
    Swag.assert(voice.stream.isOpen())

    discard expect voice.stop()
    Swag.assert(!voice.stream.isOpen())
    Swag.assert(voice.streamCurSeek == 0)
    voice.destroy()
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file        = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    let voiceResult = expect Voice.create(&file)
    let voice       = voiceResult!
    let handle      = cast(*NoSoundVoice) voice.handle!

    discard expect voice.play()
    let shouldKeepUpdating = expect voice.updateNoSound()
    Swag.assert(!shouldKeepUpdating)
    Swag.assert(!handle.isPlaying)
    Swag.assert(voice.streamCurSeek == file.dataSize)

    voice.destroy()
}
