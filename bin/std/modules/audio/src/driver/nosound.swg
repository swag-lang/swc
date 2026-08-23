using Swag, Core, Core.Errors

struct NoSoundVoice
{
    volume:         f32 = 1
    frequencyRatio: f32 = 1
    isPlaying:      bool
    busCount:       u32
    buses:          [16] #null *Bus
}

struct NoSoundBus
{
    volume:      f32 = 1
    numChannels: u32
    parent:      #null *Bus
}

struct NoSoundDriverNative
{
    outputVolume: f32 = 1
}

impl NoSoundDriverNative
{
    mtd createNoSound() fail
    {
        .outputVolume = 1
    }

    mtd destroyNoSound()
    {
        .outputVolume = 1
    }

    mtd setOutputVolumeNoSound(volume: f32) fail
    {
        .outputVolume = volume
    }

    mtd outputVolumeNoSound()->f32
    {
        return .outputVolume
    }
}

impl Voice
{
    func createNoSound(voice: *Voice, createFlags = VoiceCreateFlags.Default) fail
    {
        voice.handle = cast(#null *void) Memory.new'NoSoundVoice(voice.allocationAllocator)
        let file = voice.file!
        voice.requestedEncoding = file.encoding
        if !voice.handle do
            fail BadParameterError{"cannot create no-sound voice"}
    }

    mtd destroyNoSound()
    {
        if !.handle do
            return
        let allocator = .allocationAllocator
        Memory.delete(cast(*NoSoundVoice) .handle, allocator)
        .handle = null
    }

    mtd updateNoSound()->bool fail
    {
        let handle = cast(#null *NoSoundVoice) .handle
        if !handle or !handle.isPlaying do
            return false

        if .playFlags.has(.Loop)
        {
            let {_, sizeBuffer} = .readBuffer()
            return sizeBuffer != 0
        }

        for
        {
            let {_, sizeBuffer} = .readBuffer()
            if !sizeBuffer do
                break
        }

        handle.isPlaying = false
        return false
    }

    mtd playNoSound(batchId: u32 = 0) fail
    {
        let handle = cast(#null *NoSoundVoice) .handle
        if handle do
            handle.isPlaying = true
    }

    mtd stopNoSound(batchId: u32 = 0) fail
    {
        let handle = cast(#null *NoSoundVoice) .handle
        if handle do
            handle.isPlaying = false
    }

    mtd resetNoSound() fail
    {
        let handle = cast(#null *NoSoundVoice) .handle
        if handle do
            handle.isPlaying = false
    }
}

internal impl Voice
{
    // Sets the linear gain recorded by the no-sound backend.
    mtd setVolumeNoSound(volume: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let handle = cast(*NoSoundVoice) .handle
        handle.volume = Math.clamp(volume, 0, 1)
    }

    // Returns the linear gain recorded by the no-sound backend.
    mtd volumeNoSound()->f32 fail
    {
        if !.handle do
            return 0
        let handle = cast(*NoSoundVoice) .handle
        return handle.volume
    }

    // Sets the frequency ratio recorded by the no-sound backend.
    mtd setFrequencyRatioNoSound(ratio: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let handle = cast(*NoSoundVoice) .handle
        handle.frequencyRatio = ratio
    }

    // Returns the frequency ratio recorded by the no-sound backend.
    mtd frequencyRatioNoSound()->f32 fail
    {
        if !.handle do
            return 0
        let handle = cast(*NoSoundVoice) .handle
        return handle.frequencyRatio
    }

    // Validates and records no-sound bus routing without producing audio.
    mtd setRoutingNoSound(buses: const [..] *Bus) fail
    {
        if !.handle do
            return

        let handle = cast(*NoSoundVoice) .handle
        let count  = @countof(buses)
        if count > @countof(handle.buses) do
            fail SystemError{"too many buses", errorID: count}

        handle.busCount = cast(u32) count
        for i in count
        {
            let bus = buses[i]
            if !bus.handle do
                fail BadParameterError{"bus invalid"}
            handle.buses[i] = bus
        }
    }
}

impl Bus
{
    func createNoSound(bus: *Bus, numChannels: u32, parent: #null *Bus = null) fail
    {
        if parent and !parent.handle do
            fail BadParameterError{"parent bus invalid"}

        let handle = Memory.new'NoSoundBus(bus.allocationAllocator)
        bus.handle         = cast(#null *void) handle
        handle.numChannels = numChannels
        handle.parent      = parent
    }

    mtd destroyNoSound()
    {
        if !.handle do
            return
        let allocator = .allocationAllocator
        Memory.delete(cast(*NoSoundBus) .handle, allocator)
        .handle = null
    }
}

internal impl Bus
{
    // Sets the linear bus gain recorded by the no-sound backend.
    mtd setVolumeNoSound(volume: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            return
        let handle = cast(*NoSoundBus) .handle
        handle.volume = Math.clamp(volume, 0, 1)
    }

    // Returns the linear bus gain recorded by the no-sound backend.
    mtd volumeNoSound()->f32 fail
    {
        if !.handle do
            return 0
        let handle = cast(*NoSoundBus) .handle
        return handle.volume
    }
}
