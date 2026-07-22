using Swag, Core, Core.Errors

public enum DriverKind
{
    Default
    NoSound
    XAudio2
}

public alias VoiceHandle = #null *void
public alias BusHandle = #null *void

struct DriverNative
{
    kind:       DriverKind
    noSound:    NoSoundDriverNative

    #if #os == Swag.TargetOs.Windows
    {
        xAudio2: XAudio2DriverNative
    }
}

impl DriverNative
{
    mtd createNative(kind: DriverKind = .Default) throw
    {
        .kind = resolveKind(kind)

        switch .kind
        {
        case NoSound:
            .noSound.createNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .xAudio2.createXAudio2()
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}

        default:
            throw UnsupportedFormatError{"audio driver is not available"}
        }
    }

    mtd destroyNative()
    {
        switch .kind
        {
        case NoSound:
            .noSound.destroyNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
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
        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .xAudio2.stopEngineXAudio2()
            }
        }
    }

    mtd setOutputVolumeNative(volume: f32) throw
    {
        switch .kind
        {
        case NoSound:
            .noSound.setOutputVolumeNoSound(volume)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .xAudio2.setOutputVolumeXAudio2(volume)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd getOutputVolumeNative()->f32
    {
        switch .kind
        {
        case NoSound:
            return .noSound.getOutputVolumeNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
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

        #if #os == Swag.TargetOs.Windows
        {
            return .XAudio2
        }
        #else
        {
            return .NoSound
        }
    }
}

impl Voice
{
    func createNative(voice: *Voice, createFlags = VoiceCreateFlags.Default) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            voice.createNoSound(createFlags)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                voice.createXAudio2(createFlags)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}

        default:
            throw UnsupportedFormatError{"audio driver is not available"}
        }
    }

    mtd destroyNative()
    {
        switch g_Driver.kind
        {
        case NoSound:
            .destroyNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .destroyXAudio2()
            }
        }
    }

    mtd updateNative()->bool throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            return .updateNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                return .updateXAudio2()
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }

        return false
    }

    mtd playNative(batchID: u32 = 0) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            .playNoSound(batchID)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .playXAudio2(batchID)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd stopNative(batchID: u32 = 0) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            .stopNoSound(batchID)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .stopXAudio2(batchID)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }
    }
}

public impl Voice
{
    mtd setVolume(volume: f32, batchID: u32 = 0) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            .setVolumeNoSound(volume, batchID)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .setVolumeXAudio2(volume, batchID)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd getVolume()->f32 throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            return .getVolumeNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                return .getVolumeXAudio2()
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }

        return 0
    }

    mtd setFrequencyRatio(ratio: f32, batchID: u32 = 0) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            .setFrequencyRatioNoSound(ratio, batchID)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .setFrequencyRatioXAudio2(ratio, batchID)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd setRooting(buses: const [..] *Bus) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            .setRootingNoSound(buses)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .setRootingXAudio2(buses)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }
    }
}

impl Bus
{
    func createNative(bus: *Bus, numChannels: u32, parent: #null *Bus = null) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            bus.createNoSound(numChannels, parent)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                bus.createXAudio2(numChannels, parent)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}

        default:
            throw UnsupportedFormatError{"audio driver is not available"}
        }
    }

    mtd destroyNative()
    {
        switch g_Driver.kind
        {
        case NoSound:
            .destroyNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .destroyXAudio2()
            }
        }
    }
}

public impl Bus
{
    mtd setVolume(volume: f32, batchID: u32 = 0) throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            .setVolumeNoSound(volume, batchID)

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                .setVolumeXAudio2(volume, batchID)
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }
    }

    mtd getVolume()->f32 throw
    {
        switch g_Driver.kind
        {
        case NoSound:
            return .getVolumeNoSound()

        case XAudio2:
            #if #os == Swag.TargetOs.Windows
            {
                return .getVolumeXAudio2()
            }
            #else do
                throw UnsupportedFormatError{"XAudio2 is not available"}
        }

        return 0
    }
}
