using Swag, Core, Core.Errors

// Selects the engine backend.
public enum DriverKind
{
    Default     // Selects XAudio2 on Windows and the no-sound backend elsewhere.
    NoSound     // Preserves audio state and validation without producing sound.
    XAudio2     // Uses the Windows XAudio2 backend and fails where it is unavailable.
}

struct DriverNative
{
    kind:    DriverKind
    noSound: NoSoundDriverNative

    #static if #os == Swag.TargetOs.Windows
    {
        xAudio2: XAudio2DriverNative
    }
}

impl DriverNative
{
    mtd createNative(kind: DriverKind = .Default) fail
    {
        let resolved = resolveKind(kind)

        switch resolved
        {
        case .NoSound:
            .noSound.createNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .xAudio2.createXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        default:
            fail UnsupportedFormatError{"audio driver is not available"}
        }

        // The driver names its backend only once it has one. A backend that gives up half way
        // otherwise leaves a driver that says XAudio2 while 'isCreated' is false, which is what
        // the next caller reads and believes.
        .kind = resolved
    }

    mtd destroyNative()
    {
        switch .kind
        {
        case .NoSound:
            .noSound.destroyNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .xAudio2.destroyXAudio2()
            }
        }

        .kind = .Default
    }

    // Synchronously halts the backend's audio processing thread. Called first
    // during driver teardown so no mixer pass or voice callback can run while the
    // voices are being destroyed and freed.
    mtd stopEngineNative()
    {
        switch .kind
        {
        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .xAudio2.stopEngineXAudio2()
            }
        }
    }

    mtd setOutputVolumeNative(volume: f32) fail
    {
        switch .kind
        {
        case .NoSound:
            .noSound.setOutputVolumeNoSound(volume)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .xAudio2.setOutputVolumeXAudio2(volume)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd outputVolumeNative()->f32
    {
        switch .kind
        {
        case .NoSound:
            return .noSound.outputVolumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .xAudio2.outputVolumeXAudio2()
            }
        }

        return 0
    }

    func resolveKind(kind: DriverKind)->DriverKind
    {
        if kind != .Default do
            return kind

        #static if #os == Swag.TargetOs.Windows
        {
            return .XAudio2
        }
        else
        {
            return .NoSound
        }
    }
}

impl Voice
{
    func createNative(voice: *Voice, createFlags = VoiceCreateFlags.Default) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            voice.createNoSound(createFlags)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                voice.createXAudio2(createFlags)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        default:
            fail UnsupportedFormatError{"audio driver is not available"}
        }
    }

    mtd destroyNative()
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .destroyNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .destroyXAudio2()
            }
        }
    }

    mtd updateNative()->bool fail
    {
        .dataMutex.lock()
        defer .dataMutex.unlock()
        switch g_Driver.kind
        {
        case .NoSound:
            return .updateNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .updateXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }

        return false
    }

    mtd playNative(batchId: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .playNoSound(batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .playXAudio2(batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd stopNative(batchId: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .stopNoSound(batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .stopXAudio2(batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    // Discards backend buffers after a full stop. Pause deliberately does not call this.
    mtd resetNative() fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .resetNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .resetXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd playedFramesNative()->u64
    {
        switch g_Driver.kind
        {
        case .NoSound:
            return .playedFramesNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows do
                return .playedFramesXAudio2()
        }

        return 0
    }
}

public impl Voice
{
    // Sets this voice's linear gain.
    //
    // `volume` is clamped to the range `0` through `1`. `batchId` is forwarded
    // to backends that support deferred operation sets.
    mtd setVolume(volume: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            fail BadParameterError{"voice is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            .setVolumeNoSound(volume, batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setVolumeXAudio2(volume, batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    // Returns this voice's current linear gain.
    mtd volume()->f32 fail
    {
        if !.handle do
            fail BadParameterError{"voice is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            return .volumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .volumeXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }

        return 0
    }

    // Sets the playback frequency ratio.
    //
    // `1` preserves the source pitch, values below `1` lower it, and values
    // above `1` raise it. Create the voice with
    // [[Audio.VoiceCreateFlags.PitchControl]] before changing this value.
    mtd setFrequencyRatio(ratio: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            fail BadParameterError{"voice is not valid"}
        if ratio <= 0 do
            fail BadParameterError{"frequency ratio must be greater than zero"}
        switch g_Driver.kind
        {
        case .NoSound:
            .setFrequencyRatioNoSound(ratio, batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setFrequencyRatioXAudio2(ratio, batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    // Returns the current playback frequency ratio.
    mtd frequencyRatio()->f32 fail
    {
        if !.handle do
            fail BadParameterError{"voice is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            return .frequencyRatioNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .frequencyRatioXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }

        return 0
    }

    // Replaces the buses that receive this voice.
    //
    // An empty slice routes directly to the mastering output. Every bus must be
    // valid and must outlive this routing relationship.
    mtd setRouting(buses: const [..] *Bus) fail
    {
        if !.handle do
            fail BadParameterError{"voice is not valid"}
        for bus in buses
        {
            if !bus.handle do
                fail BadParameterError{"routing contains an invalid bus"}
        }

        switch g_Driver.kind
        {
        case .NoSound:
            .setRoutingNoSound(buses)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setRoutingXAudio2(buses)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }
}

impl Bus
{
    func createNative(bus: *Bus, numChannels: u32, parent: #null *Bus = null) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            bus.createNoSound(numChannels, parent)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                bus.createXAudio2(numChannels, parent)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        default:
            fail UnsupportedFormatError{"audio driver is not available"}
        }
    }

    mtd destroyNative()
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .destroyNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .destroyXAudio2()
            }
        }
    }
}

public impl Bus
{
    // Sets this bus's linear gain.
    //
    // `volume` is clamped to the range `0` through `1`. `batchId` is forwarded
    // to backends that support deferred operation sets.
    mtd setVolume(volume: f32, batchId: u32 = 0) fail
    {
        if !.handle do
            fail BadParameterError{"bus is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            .setVolumeNoSound(volume, batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setVolumeXAudio2(volume, batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    // Returns this bus's current linear gain.
    mtd volume()->f32 fail
    {
        if !.handle do
            fail BadParameterError{"bus is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            return .volumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .volumeXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }

        return 0
    }
}
