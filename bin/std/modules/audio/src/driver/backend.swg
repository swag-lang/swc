using Swag, Core, Core.Errors

// Selects the engine backend.
public enum DriverKind
{
    Default // Selects XAudio2 on Windows and the no-sound backend elsewhere.
    NoSound // Preserves audio state and validation without producing sound.
    XAudio2 // Uses the Windows XAudio2 backend and fails where it is unavailable.
}

// Stores an opaque backend handle for a voice.
public alias VoiceHandle = #null *void

// Stores an opaque backend handle for a bus.
public alias BusHandle = #null *void

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
        .kind = resolveKind(kind)

        switch .kind
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

    mtd getOutputVolumeNative()->f32
    {
        switch .kind
        {
        case .NoSound:
            return .noSound.getOutputVolumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .xAudio2.getOutputVolumeXAudio2()
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

    mtd playNative(batchID: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .playNoSound(batchID)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .playXAudio2(batchID)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd stopNative(batchID: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .stopNoSound(batchID)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .stopXAudio2(batchID)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }
}

public impl Voice
{
    // Sets this voice's linear gain.
    //
    // `volume` is clamped to the range `0` through `1`. `batchID` is forwarded
    // to backends that support deferred operation sets.
    mtd setVolume(volume: f32, batchID: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .setVolumeNoSound(volume, batchID)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setVolumeXAudio2(volume, batchID)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    // Returns this voice's current linear gain.
    mtd getVolume()->f32 fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            return .getVolumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .getVolumeXAudio2()
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
    // [[Audio.VoiceCreateFlags.AcceptPitch]] before changing this value.
    mtd setFrequencyRatio(ratio: f32, batchID: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .setFrequencyRatioNoSound(ratio, batchID)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setFrequencyRatioXAudio2(ratio, batchID)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    // Replaces the buses that receive this voice.
    //
    // An empty slice routes directly to the mastering output. Every bus must be
    // valid and must outlive this routing relationship.
    mtd setRooting(buses: const [..] *Bus) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .setRootingNoSound(buses)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setRootingXAudio2(buses)
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
    // `volume` is clamped to the range `0` through `1`. `batchID` is forwarded
    // to backends that support deferred operation sets.
    mtd setVolume(volume: f32, batchID: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            .setVolumeNoSound(volume, batchID)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                .setVolumeXAudio2(volume, batchID)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    // Returns this bus's current linear gain.
    mtd getVolume()->f32 fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            return .getVolumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return .getVolumeXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}
        }

        return 0
    }
}
