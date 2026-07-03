#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

func audioStartNoSoundEngine()
{
    discard catch createNoSoundEngine()
    @assert(@err == null)
    @assert(g_Driver.kind == .NoSound)
}

#test
{
    discard catch createEngine(.NoSound)
    @assert(@err == null)
    @assert(g_Driver.kind == .NoSound)
    defer destroyEngine()

    audioAssertFloat(getOutputVolume(), 1)

    discard catch setOutputVolume(0.25)
    @assert(@err == null)
    audioAssertFloat(getOutputVolume(), 0.25)

    discard catch setOutputVolume(2)
    @assert(@err == null)
    audioAssertFloat(getOutputVolume(), 2)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    let root = catch Bus.create(2)
    @assert(@err == null)
    let child = catch Bus.create(1, root)
    @assert(@err == null)

    let rootHandle = cast(*NoSoundBus) root.handle
    let childHandle = cast(*NoSoundBus) child.handle
    @assert(rootHandle.numChannels == 2)
    @assert(rootHandle.parent == null)
    @assert(childHandle.numChannels == 1)
    @assert(childHandle.parent == root)
    @assert(g_Driver.buses.count == 2)

    discard catch child.setVolume(1.5)
    @assert(@err == null)
    audioAssertFloat(catch child.getVolume(), 1)
    @assert(@err == null)

    discard catch child.setVolumeDB(-6.0206)
    @assert(@err == null)
    audioAssertFloat(catch child.getVolume(), 0.5, 0.0002)
    @assert(@err == null)
    audioAssertFloat(catch child.getVolumeDB(), -6.0206, 0.0002)
    @assert(@err == null)

    var invalidParent: Bus
    discard catch Bus.create(1, &invalidParent)
    @assert(@err is Errors.BadParameterError)

    discard catch child.destroy()
    @assert(@err == null)
    discard catch root.destroy()
    @assert(@err == null)
    @assert(g_Driver.buses.count == 0)
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    @assert(@err == null)

    let voice = catch Voice.create(&file)
    @assert(@err == null)
    let handle = cast(*NoSoundVoice) voice.handle
    @assert(handle != null)
    @assert(voice.requestedEncoding == .Pcm16)
    @assert(!voice.isPlaying())

    discard catch voice.setVolume(1.5)
    @assert(@err == null)
    audioAssertFloat(catch voice.getVolume(), 1)
    @assert(@err == null)

    discard catch voice.setVolume(-0.25)
    @assert(@err == null)
    audioAssertFloat(catch voice.getVolume(), 0)
    @assert(@err == null)

    discard catch voice.setVolumeDB(-6.0206)
    @assert(@err == null)
    audioAssertFloat(catch voice.getVolume(), 0.5, 0.0002)
    @assert(@err == null)
    audioAssertFloat(catch voice.getVolumeDB(), -6.0206, 0.0002)
    @assert(@err == null)

    discard catch voice.setFrequencyRatio(1.75)
    @assert(@err == null)
    audioAssertFloat(handle.frequencyRatio, 1.75)

    let bus0 = catch Bus.create(2)
    @assert(@err == null)
    let bus1 = catch Bus.create(2, bus0)
    @assert(@err == null)
    discard catch voice.setRooting([bus0, bus1])
    @assert(@err == null)
    @assert(handle.busCount == 2)
    @assert(handle.buses[0] == bus0)
    @assert(handle.buses[1] == bus1)

    discard catch voice.play()
    @assert(@err == null)
    @assert(voice.isPlaying())
    @assert(handle.isPlaying)

    discard catch voice.pause()
    @assert(@err == null)
    @assert(!voice.isPlaying())
    @assert(!handle.isPlaying)

    discard catch voice.play(.Loop)
    @assert(@err == null)
    let shouldKeepUpdating = catch voice.updateNoSound()
    @assert(@err == null)
    @assert(shouldKeepUpdating)
    @assert(handle.isPlaying)

    discard catch voice.stop()
    @assert(@err == null)
    @assert(!voice.isPlaying())
    @assert(!handle.isPlaying)

    voice.destroy()
}

#test
{
    audioStartNoSoundEngine()
    defer destroyEngine()

    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    @assert(@err == null)

    let voice = catch Voice.create(&file)
    @assert(@err == null)
    let handle = cast(*NoSoundVoice) voice.handle

    discard catch voice.play()
    @assert(@err == null)
    let shouldKeepUpdating = catch voice.updateNoSound()
    @assert(@err == null)
    @assert(!shouldKeepUpdating)
    @assert(!handle.isPlaying)
    @assert(voice.streamCurSeek == file.dataSize)

    voice.destroy()
}
