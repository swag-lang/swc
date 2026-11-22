using Swag, Core, Core.Errors

#static if #command == Swag.CompilerCommand.Test
{
    var g_FailNextNoSoundPanForTest: bool
}

struct NoSoundVoice
{
    volume:         f32 = 1
    pan:            f32
    frequencyRatio: f32 = 1
    isPlaying:      bool
    busCount:       u32
    buses:          [16] (*Bus?)
    samplesPlayed:  u64
}

struct NoSoundBus
{
    volume:      f32 = 1
    numChannels: u32
    parent:      *Bus?
}

struct NoSoundDriverNative
{
    outputVolume: f32 = 1
}

impl NoSoundDriverNative
{
    mtd createNoSound() fail { .outputVolume = 1 }

    mtd destroyNoSound() { .outputVolume = 1 }

    mtd setOutputVolumeNoSound(volume: f32) fail { .outputVolume = volume }

    mtd outputVolumeNoSound()->f32 => .outputVolume
}

impl Voice
{
    func createNoSound(voice: *Voice, _ = VoiceCreateFlags.Default) fail
    {
        voice.handle = cast(*void?, Memory.new'NoSoundVoice(voice.allocationAllocator))
        let file = unwrap voice.file
        voice.requestedEncoding = file.encoding == .AacLc ? .Pcm16 : file.encoding
        if not voice.handle do
            fail BadParameterError{"cannot create no-sound voice"}
    }

    mtd destroyNoSound()
    {
        if not .handle do
            return
        let allocator = .allocationAllocator
        Memory.delete(cast(*NoSoundVoice, .handle), allocator)
        .handle = null
    }

    mtd updateNoSound()->bool fail
    {
        let handle = cast(*NoSoundVoice?, .handle)
        if not handle or not handle.isPlaying do
            return false

        if .playFlags.has(.Loop)
        {
            let {buffer: _, size: sizeBuffer} = try .readBuffer()
            handle.samplesPlayed += sizeBuffer / .decodedBytesPerFrame()
            return sizeBuffer != 0
        }

        for
        {
            let {buffer: _, size: sizeBuffer} = try .readBuffer()
            if not sizeBuffer do
                break
            handle.samplesPlayed += sizeBuffer / .decodedBytesPerFrame()
        }

        handle.isPlaying = false
        return false
    }

    mtd playNoSound(_: u32 = 0) fail
    {
        let handle = cast(*NoSoundVoice?, .handle)
        if handle do
            handle.isPlaying = true
    }

    mtd stopNoSound(_: u32 = 0) fail
    {
        let handle = cast(*NoSoundVoice?, .handle)
        if handle do
            handle.isPlaying = false
    }

    mtd resetNoSound() fail
    {
        let handle = cast(*NoSoundVoice?, .handle)
        if handle do
            handle.isPlaying = false
    }

    mtd playedFramesNoSound()->u64
    {
        let handle = cast(*NoSoundVoice?, .handle)
        return handle ? handle.samplesPlayed : 0
    }
}

internal impl Voice
{
    // Sets the linear gain recorded by the no-sound backend.
    mtd setVolumeNoSound(volume: f32, _: u32 = 0) fail
    {
        if not .handle do
            return
        let handle = cast(*NoSoundVoice, .handle)
        handle.volume = Math.clamp(volume, 0, 1)
    }

    // Returns the linear gain recorded by the no-sound backend.
    mtd volumeNoSound()->f32 fail
    {
        if not .handle do
            return 0
        let handle = cast(*NoSoundVoice, .handle)
        return handle.volume
    }

    // Sets the frequency ratio recorded by the no-sound backend.
    mtd setFrequencyRatioNoSound(ratio: f32, _: u32 = 0) fail
    {
        if not .handle do
            return
        let handle = cast(*NoSoundVoice, .handle)
        handle.frequencyRatio = ratio
    }

    // Returns the frequency ratio recorded by the no-sound backend.
    mtd frequencyRatioNoSound()->f32 fail
    {
        if not .handle do
            return 0
        let handle = cast(*NoSoundVoice, .handle)
        return handle.frequencyRatio
    }

    mtd setPanNoSound(pan: f32, _: u32 = 0) fail
    {
        if not .handle do
            return
        let file     = unwrap .file
        let channels = file.numChannels()
        if channels == 0 or channels > 2 do
            fail BadParameterError{"stereo pan supports mono and stereo sources"}
        let handle = cast(*NoSoundVoice, .handle)
        for i in handle.busCount
        {
            let bus = unwrap handle.buses[i]
            if bus.channelCount != 2 do
                fail BadParameterError{"stereo pan requires a stereo output route"}
        }

        #static if #command == Swag.CompilerCommand.Test
        {
            if g_FailNextNoSoundPanForTest
            {
                g_FailNextNoSoundPanForTest = false
                fail SystemError{"injected no-sound pan failure"}
            }
        }

        handle.pan = pan
    }

    // Validates and records no-sound bus routing without producing audio.
    mtd setRoutingNoSound(buses: const [..] *Bus) fail
    {
        if not .handle do
            return

        let handle = cast(*NoSoundVoice, .handle)
        let count  = buses.count
        if count > handle.buses.count do
            fail SystemError{"too many buses", errorID: count}

        for bus in buses
        {
            if not bus.handle do
                fail BadParameterError{"bus invalid"}
        }

        for i in handle.busCount
        {
            if i >= count do
                handle.buses[i] = null
        }

        handle.busCount = cast(u32, count)
        for i in count
        {
            handle.buses[i] = buses[i]
        }
    }
}

impl Bus
{
    func createNoSound(bus: *Bus, numChannels: u32, parent: *Bus? = null) fail
    {
        if parent and not parent.handle do
            fail BadParameterError{"parent bus invalid"}

        let handle = Memory.new'NoSoundBus(bus.allocationAllocator)
        bus.handle         = cast(*void?, handle)
        handle.numChannels = numChannels
        handle.parent      = parent
    }

    mtd destroyNoSound()
    {
        if not .handle do
            return
        let allocator = .allocationAllocator
        Memory.delete(cast(*NoSoundBus, .handle), allocator)
        .handle = null
    }
}

internal impl Bus
{
    // Sets the linear bus gain recorded by the no-sound backend.
    mtd setVolumeNoSound(volume: f32, _: u32 = 0) fail
    {
        if not .handle do
            return
        let handle = cast(*NoSoundBus, .handle)
        handle.volume = Math.clamp(volume, 0, 1)
    }

    // Returns the linear bus gain recorded by the no-sound backend.
    mtd volumeNoSound()->f32 fail
    {
        if not .handle do
            return 0
        let handle = cast(*NoSoundBus, .handle)
        return handle.volume
    }
}
