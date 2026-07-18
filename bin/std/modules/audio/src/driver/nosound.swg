#global #[Swag.ExplicitNullability]
using Swag, Core, Core.Errors

struct NoSoundVoice
{
    volume:             f32 = 1
    frequencyRatio:     f32 = 1
    isPlaying:          bool
    busCount:           u32
    buses:              [16] #null *Bus
}

struct NoSoundBus
{
    volume:         f32 = 1
    numChannels:    u32
    parent:         #null *Bus
}

struct NoSoundDriverNative
{
    outputVolume: f32 = 1
}

impl NoSoundDriverNative
{
    mtd createNoSound() throw
    {
        .outputVolume = 1
    }

    mtd destroyNoSound()
    {
        .outputVolume = 1
    }

    mtd setOutputVolumeNoSound(volume: f32) throw
    {
        .outputVolume = volume
    }

    mtd getOutputVolumeNoSound()->f32
    {
        return .outputVolume
    }
}

impl Voice
{
    func createNoSound(voice: #nonull *Voice, createFlags = VoiceCreateFlags.Default) throw
    {
        voice.handle = cast(VoiceHandle) Memory.new'NoSoundVoice()
        voice.requestedEncoding = voice.file.encoding
        if !voice.handle do
            throw BadParameterError{"cannot create no-sound voice"}
    }

    mtd destroyNoSound()
    {
        if !.handle do
            return
        Memory.delete(cast(#null *NoSoundVoice) .handle)
        .handle = null
    }

    mtd updateNoSound()->bool throw
    {
        let handle = cast(#null *NoSoundVoice) .handle
        if !handle or !handle.isPlaying do
            return false

        if .playFlags.has(.Loop)
        {
            let (_, sizeBuffer) = .readBuffer()
            return sizeBuffer != 0
        }

        for
        {
            let (_, sizeBuffer) = .readBuffer()
            if !sizeBuffer do
                break
        }

        handle.isPlaying = false
        return false
    }

    mtd playNoSound(batchID: u32 = 0) throw
    {
        let handle = cast(#null *NoSoundVoice) .handle
        if handle do
            handle.isPlaying = true
    }

    mtd stopNoSound(batchID: u32 = 0) throw
    {
        let handle = cast(#null *NoSoundVoice) .handle
        if handle do
            handle.isPlaying = false
    }
}

public impl Voice
{
    mtd setVolumeNoSound(volume: f32, batchID: u32 = 0) throw
    {
        if !.handle do
            return
        let handle = cast(#null *NoSoundVoice) .handle
        handle.volume = Math.clamp(volume, 0, 1)
    }

    mtd getVolumeNoSound()->f32 throw
    {
        if !.handle do
            return 0
        let handle = cast(#null *NoSoundVoice) .handle
        return handle.volume
    }

    mtd setFrequencyRatioNoSound(ratio: f32, batchID: u32 = 0) throw
    {
        if !.handle do
            return
        let handle = cast(#null *NoSoundVoice) .handle
        handle.frequencyRatio = ratio
    }

    mtd setRootingNoSound(buses: #null const [..] #null *Bus) throw
    {
        if !.handle do
            return

        let handle = cast(#null *NoSoundVoice) .handle
        let count = @countof(buses)
        if count >= @countof(handle.buses) do
            throw SystemError{"too many buses", errorID: count}

        handle.busCount = cast(u32) count
        for i in count
        {
            let bus = buses[i]
            if !bus or !bus.handle do
                throw BadParameterError{"bus invalid"}
            handle.buses[i] = bus
        }
    }
}

impl Bus
{
    func createNoSound(bus: #nonull *Bus, numChannels: u32, parent: #null *Bus = null) throw
    {
        if parent and !parent.handle do
            throw BadParameterError{"parent bus invalid"}

        let handle = Memory.new'NoSoundBus()
        bus.handle = cast(BusHandle) handle
        handle.numChannels = numChannels
        handle.parent      = parent
    }

    mtd destroyNoSound()
    {
        if !.handle do
            return
        Memory.delete(cast(#null *NoSoundBus) .handle)
        .handle = null
    }
}

public impl Bus
{
    mtd setVolumeNoSound(volume: f32, batchID: u32 = 0) throw
    {
        if !.handle do
            return
        let handle = cast(#null *NoSoundBus) .handle
        handle.volume = Math.clamp(volume, 0, 1)
    }

    mtd getVolumeNoSound()->f32 throw
    {
        if !.handle do
            return 0
        let handle = cast(#null *NoSoundBus) .handle
        return handle.volume
    }
}
