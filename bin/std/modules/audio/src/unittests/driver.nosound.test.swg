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
    discard catch createEngine(.NoSound) as err2
    @assert(err2 == null)
    @assert(g_Driver.kind == .NoSound)
    defer destroyEngine()

    audioAssertFloat(getOutputVolume(), 1)

    discard catch setOutputVolume(0.25) as err3
    @assert(err3 == null)
    audioAssertFloat(getOutputVolume(), 0.25)

    discard catch setOutputVolume(2) as err4
    @assert(err4 == null)
    audioAssertFloat(getOutputVolume(), 2)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    let root = notnull catch Bus.create(2) as err5
    @assert(err5 == null)
    let child = notnull catch Bus.create(1, root) as err6
    @assert(err6 == null)

    let rootHandle  = cast(*NoSoundBus) notnull root.handle
    let childHandle = cast(*NoSoundBus) notnull child.handle
    @assert(rootHandle.numChannels == 2)
    @assert(rootHandle.parent == null)
    @assert(childHandle.numChannels == 1)
    @assert(childHandle.parent == root)
    @assert(g_Driver.buses.count == 2)

    discard catch child.setVolume(1.5) as err7
    @assert(err7 == null)
    audioAssertFloat(catch child.getVolume() as err8, 1)
    @assert(err8 == null)

    discard catch child.setVolumeDB(-6.0206) as err9
    @assert(err9 == null)
    audioAssertFloat(catch child.getVolume() as err10, 0.5, 0.0002)
    @assert(err10 == null)
    audioAssertFloat(catch child.getVolumeDB() as err11, -6.0206, 0.0002)
    @assert(err11 == null)

    var invalidParent: Bus
    discard catch Bus.create(1, &invalidParent) as err12
    @assert(err12 is Errors.BadParameterError)

    discard catch child.destroy() as err13
    @assert(err13 == null)
    discard catch root.destroy() as err14
    @assert(err14 == null)
    @assert(g_Driver.buses.count == 0)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav")) as err15
    @assert(err15 == null)

    let voice = notnull catch Voice.create(&file) as err16
    @assert(err16 == null)
    let handle = cast(*NoSoundVoice) notnull voice.handle
    @assert(voice.requestedEncoding == .Pcm16)
    @assert(!voice.isPlaying())

    discard catch voice.setVolume(1.5) as err17
    @assert(err17 == null)
    audioAssertFloat(catch voice.getVolume() as err18, 1)
    @assert(err18 == null)

    discard catch voice.setVolume(-0.25) as err19
    @assert(err19 == null)
    audioAssertFloat(catch voice.getVolume() as err20, 0)
    @assert(err20 == null)

    discard catch voice.setVolumeDB(-6.0206) as err21
    @assert(err21 == null)
    audioAssertFloat(catch voice.getVolume() as err22, 0.5, 0.0002)
    @assert(err22 == null)
    audioAssertFloat(catch voice.getVolumeDB() as err23, -6.0206, 0.0002)
    @assert(err23 == null)

    discard catch voice.setFrequencyRatio(1.75) as err24
    @assert(err24 == null)
    audioAssertFloat(handle.frequencyRatio, 1.75)

    let bus0 = catch Bus.create(2) as err25
    @assert(err25 == null)
    let safeBus0 = notnull bus0
    let bus1     = catch Bus.create(2, safeBus0) as err26
    @assert(err26 == null)
    let safeBus1 = notnull bus1
    discard catch voice.setRooting([safeBus0, safeBus1]) as err27
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

    voice.destroy()
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav")) as err33
    @assert(err33 == null)

    let voice = notnull catch Voice.create(&file) as err34
    @assert(err34 == null)
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
