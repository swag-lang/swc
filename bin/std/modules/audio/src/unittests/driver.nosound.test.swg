#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func audioStartNoSoundEngine()
{
    discard catch createNoSoundEngine() as err
    @assert(err == null)
    @assert(g_Driver.kind == .NoSound)
}

#test
{
    @assert(!isEngineCreated())
    discard catch outputVolume() as errNoEngine
    @assert(errNoEngine is Errors.BadParameterError)

    discard catch createEngine(.NoSound) as errCreate
    @assert(errCreate == null)
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
    discard catch createEngine(.NoSound) as err2
    @assert(err2 == null)
    @assert(g_Driver.kind == .NoSound)
    defer destroyEngine()

    audioAssertFloat(catch outputVolume() as err3, 1)
    @assert(err3 == null)

    discard catch setOutputVolume(0.25) as err4
    @assert(err4 == null)
    audioAssertFloat(catch outputVolume() as err5, 0.25)
    @assert(err5 == null)

    discard catch setOutputVolume(2) as err6
    @assert(err6 == null)
    audioAssertFloat(catch outputVolume() as err7, 2)
    @assert(err7 == null)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    let rootResult = catch Bus.create(2) as errRoot
    @assert(errRoot == null)
    let root = notnull rootResult

    let childResult = catch Bus.create(1, root) as errChild
    @assert(errChild == null)
    let child = notnull childResult

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

    discard catch child.setVolume(1.5) as err7
    @assert(err7 == null)
    audioAssertFloat(catch child.volume() as err8, 1)
    @assert(err8 == null)

    discard catch child.setVolumeDb(-6.0206) as err9
    @assert(err9 == null)
    audioAssertFloat(catch child.volume() as err10, 0.5, 0.0002)
    @assert(err10 == null)
    audioAssertFloat(catch child.volumeDb() as err11, -6.0206, 0.0002)
    @assert(err11 == null)

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

    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav")) as err15
    @assert(err15 == null)

    let voiceResult = catch Voice.create(&file) as errVoice
    @assert(errVoice == null)
    let voice  = notnull voiceResult
    let handle = cast(*NoSoundVoice) notnull voice.handle
    @assert(voice.requestedEncoding == .Pcm16)
    @assert(!voice.isPlaying())

    discard catch voice.setVolume(1.5) as err17
    @assert(err17 == null)
    audioAssertFloat(catch voice.volume() as err18, 1)
    @assert(err18 == null)

    discard catch voice.setVolume(-0.25) as err19
    @assert(err19 == null)
    audioAssertFloat(catch voice.volume() as err20, 0)
    @assert(err20 == null)

    discard catch voice.setVolumeDb(-6.0206) as err21
    @assert(err21 == null)
    audioAssertFloat(catch voice.volume() as err22, 0.5, 0.0002)
    @assert(err22 == null)
    audioAssertFloat(catch voice.volumeDb() as err23, -6.0206, 0.0002)
    @assert(err23 == null)

    discard catch voice.setFrequencyRatio(1.75) as err24
    @assert(err24 == null)
    audioAssertFloat(handle.frequencyRatio, 1.75)
    audioAssertFloat(catch voice.frequencyRatio() as errFrequency, 1.75)
    @assert(errFrequency == null)
    discard catch voice.setFrequencyRatio(0) as errInvalidRatio
    @assert(errInvalidRatio is Errors.BadParameterError)

    let bus0Result = catch Bus.create(2) as errBus0
    @assert(errBus0 == null)
    let safeBus0 = notnull bus0Result

    let bus1Result = catch Bus.create(2, safeBus0) as errBus1
    @assert(errBus1 == null)
    let safeBus1 = notnull bus1Result
    discard catch voice.setRouting([safeBus0, safeBus1]) as err27
    @assert(err27 == null)
    @assert(handle.busCount == 2)
    @assert(handle.buses[0] == safeBus0)
    @assert(handle.buses[1] == safeBus1)

    discard catch voice.play() as err28
    @assert(err28 == null)
    @assert(voice.isPlaying())
    @assert(handle.isPlaying)

    discard catch voice.pause() as err29
    @assert(err29 == null)
    @assert(!voice.isPlaying())
    @assert(!handle.isPlaying)

    discard catch voice.play(.Loop) as err30
    @assert(err30 == null)
    let shouldKeepUpdating = catch voice.updateNoSound() as err31
    @assert(err31 == null)
    @assert(shouldKeepUpdating)
    @assert(handle.isPlaying)

    discard catch voice.stop() as err32
    @assert(err32 == null)
    @assert(!voice.isPlaying())
    @assert(!handle.isPlaying)
    @assert(voice.streamCurSeek == 0)

    voice.destroy()
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav")) as err33
    @assert(err33 == null)

    let voiceResult = catch Voice.create(&file) as errVoice
    @assert(errVoice == null)
    let voice  = notnull voiceResult
    let handle = cast(*NoSoundVoice) notnull voice.handle

    discard catch voice.play() as err35
    @assert(err35 == null)
    let shouldKeepUpdating = catch voice.updateNoSound() as err36
    @assert(err36 == null)
    @assert(!shouldKeepUpdating)
    @assert(!handle.isPlaying)
    @assert(voice.streamCurSeek == file.dataSize)

    voice.destroy()
}
