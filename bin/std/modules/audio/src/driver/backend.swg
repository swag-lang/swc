using Swag, Core, Core.Errors

// Selects the engine backend.
public enum DriverKind
{
    Default     // Selects XAudio2 on Windows, FAudio on Linux, and no-sound elsewhere.
    NoSound     // Preserves audio state and validation without producing sound.
    XAudio2     // Uses the Windows XAudio2 backend and fails where it is unavailable.
    FAudio      // Uses the Linux FAudio/SDL audio backend and fails where it is unavailable.
}

struct DriverNative
{
    kind:    DriverKind
    noSound: NoSoundDriverNative

    #static if #os == Swag.TargetOs.Windows
    {
        xAudio2: XAudio2DriverNative
    }

    #static if #os == Swag.TargetOs.Linux
    {
        fAudio: FAudioDriverNative
    }
}

// Orders each child bus before its parent in backends that process submix stages.
func audioBusProcessingStage(parent: *Bus?)->u32
{
    var stage    = Swag.U32.Max
    var ancestor = parent
    while ancestor
    {
        stage    -= 1
        ancestor = ancestor.parent
    }

    return stage
}

impl DriverNative
{
    mtd createNative(kind: DriverKind = .Default) fail
    {
        let resolved = resolveKind(kind)

        switch resolved
        {
        case .NoSound:
            try .noSound.createNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .xAudio2.createXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .fAudio.createFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

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

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                .fAudio.destroyFAudio()
            }

        case .Default:
            break
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

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                .fAudio.stopEngineFAudio()
            }

        case .Default, .NoSound:
            break
        }
    }

    mtd setOutputVolumeNative(volume: f32) fail
    {
        switch .kind
        {
        case .NoSound:
            try .noSound.setOutputVolumeNoSound(volume)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .xAudio2.setOutputVolumeXAudio2(volume)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .fAudio.setOutputVolumeFAudio(volume)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
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

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                return .fAudio.outputVolumeFAudio()
            }

        case .Default:
            break
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
        elif #os == Swag.TargetOs.Linux
        {
            return .FAudio
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
            try voice.createNoSound(createFlags)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try voice.createXAudio2(createFlags)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try voice.createFAudio(createFlags)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

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

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                .destroyFAudio()
            }

        case .Default:
            break
        }
    }

    mtd updateNative()->bool fail
    {
        .dataMutex.lock()
        defer .dataMutex.unlock()
        switch g_Driver.kind
        {
        case .NoSound:
            return try .updateNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return try .updateXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                return try .updateFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }

        return false
    }

    mtd playNative(batchId: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            try .playNoSound(batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .playXAudio2(batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .playFAudio(batchId)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }

    mtd stopNative(batchId: u32 = 0) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            try .stopNoSound(batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .stopXAudio2(batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .stopFAudio(batchId)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }

    // Discards backend buffers after a full stop. Pause deliberately does not call this.
    mtd resetNative() fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            try .resetNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .resetXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .resetFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
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

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux do
                return .playedFramesFAudio()

        case .Default:
            break
        }

        return 0
    }

    mtd setPanNative(pan: f32, batchId: u32 = 0) fail
    {
        if pan == 0 and .panValue == 0 do
            return
        switch g_Driver.kind
        {
        case .NoSound:
            try .setPanNoSound(pan, batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .setPanXAudio2(pan, batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .setPanFAudio(pan, batchId)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }

    mtd validatePanRouteNative(buses: const [..] *Bus) fail
    {
        if .panValue == 0 do
            return
        let file = unwrap .file
        let sourceChannels = file.numChannels()
        if sourceChannels == 0 or sourceChannels > 2 do
            fail BadParameterError{"stereo pan supports mono and stereo sources"}
        if buses.count
        {
            for bus in buses
            {
                if bus.channelCount != 2 do
                    fail BadParameterError{"stereo pan requires a stereo output route"}
            }

            return
        }

        switch g_Driver.kind
        {
        case .NoSound:
            return

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .validatePanMasterXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .validatePanMasterFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }

    mtd validatePanCurrentRouteNative(pan: f32) fail
    {
        if pan == 0 do
            return
        let file = unwrap .file
        let sourceChannels = file.numChannels()
        if sourceChannels == 0 or sourceChannels > 2 do
            fail BadParameterError{"stereo pan supports mono and stereo sources"}
        if .routingBusCount
        {
            for i in .routingBusCount
            {
                let bus = unwrap .routingBuses[i]
                if bus.channelCount != 2 do
                    fail BadParameterError{"stereo pan requires a stereo output route"}
            }

            return
        }

        switch g_Driver.kind
        {
        case .NoSound:
            return

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .validatePanMasterXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .validatePanMasterFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }
}

public impl Voice
{
    // Sets this voice's linear gain.
    //
    // Finite `volume` values are clamped to the range `0` through `1`; non-finite values fail
    // with [[Core.Errors.BadParameterError]]. `batchId` is forwarded to backends that support
    // deferred operation sets.
    mtd setVolume(volume: f32, batchId: u32 = 0) fail
    {
        if not .handle do
            fail BadParameterError{"voice is not valid"}
        if not Math.isFinite(volume) do
            fail BadParameterError{"voice volume must be finite"}
        switch g_Driver.kind
        {
        case .NoSound:
            try .setVolumeNoSound(volume, batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .setVolumeXAudio2(volume, batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .setVolumeFAudio(volume, batchId)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }

    // Returns this voice's current linear gain.
    mtd volume()->f32 fail
    {
        if not .handle do
            fail BadParameterError{"voice is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            return try .volumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return try .volumeXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                return try .volumeFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }

        return 0
    }

    // Sets the playback frequency ratio.
    //
    // `1` preserves the source pitch, values below `1` lower it, and values
    // above `1` raise it. Create the voice with
    // [[Audio.VoiceCreateFlags.PitchControl]] before changing this value.
    // The ratio must be finite and greater than zero.
    mtd setFrequencyRatio(ratio: f32, batchId: u32 = 0) fail
    {
        if not .handle do
            fail BadParameterError{"voice is not valid"}
        if not Math.isFinite(ratio) or ratio <= 0 do
            fail BadParameterError{"frequency ratio must be finite and greater than zero"}
        if not .createFlags.has(.PitchControl) do
            fail BadParameterError{"voice was created without pitch control"}
        switch g_Driver.kind
        {
        case .NoSound:
            try .setFrequencyRatioNoSound(ratio, batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .setFrequencyRatioXAudio2(ratio, batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .setFrequencyRatioFAudio(ratio, batchId)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }

    // Returns the current playback frequency ratio.
    mtd frequencyRatio()->f32 fail
    {
        if not .handle do
            fail BadParameterError{"voice is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            return try .frequencyRatioNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return try .frequencyRatioXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                return try .frequencyRatioFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }

        return 0
    }

    // Replaces the buses that receive this voice.
    //
    // An empty slice routes directly to the mastering output. Every bus must be
    // valid and must outlive this routing relationship.
    // If the backend installs the new route but fails while reapplying the current pan,
    // the route remains changed and some destinations may have received the new pan. Retry
    // [[Audio.Voice.setPan]] after handling the error to apply the current pan to every route.
    mtd setRouting(buses: const [..] *Bus) fail
    {
        if not .handle do
            fail BadParameterError{"voice is not valid"}
        for bus in buses
        {
            if not bus.handle do
                fail BadParameterError{"routing contains an invalid bus"}
        }

        if buses.count > .routingBuses.count do
            fail BadParameterError{"too many output buses"}
        try .validatePanRouteNative(buses)

        switch g_Driver.kind
        {
        case .NoSound:
            try .setRoutingNoSound(buses)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .setRoutingXAudio2(buses)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .setRoutingFAudio(buses)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }

        for i in .routingBusCount
        {
            if i >= buses.count do
                .routingBuses[i] = null
        }

        .routingBusCount = cast(u32, buses.count)
        for i in buses.count do
            .routingBuses[i] = buses[i]
        try .setPanNative(.panValue)
    }
}

impl Bus
{
    func createNative(bus: *Bus, numChannels: u32, parent: *Bus? = null) fail
    {
        switch g_Driver.kind
        {
        case .NoSound:
            try bus.createNoSound(numChannels, parent)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try bus.createXAudio2(numChannels, parent)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try bus.createFAudio(numChannels, parent)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

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

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                .destroyFAudio()
            }

        case .Default:
            break
        }
    }
}

public impl Bus
{
    // Sets this bus's linear gain.
    //
    // Finite `volume` values are clamped to the range `0` through `1`; non-finite values fail
    // with [[Core.Errors.BadParameterError]]. `batchId` is forwarded to backends that support
    // deferred operation sets.
    mtd setVolume(volume: f32, batchId: u32 = 0) fail
    {
        if not .handle do
            fail BadParameterError{"bus is not valid"}
        if not Math.isFinite(volume) do
            fail BadParameterError{"bus volume must be finite"}
        switch g_Driver.kind
        {
        case .NoSound:
            try .setVolumeNoSound(volume, batchId)

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                try .setVolumeXAudio2(volume, batchId)
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                try .setVolumeFAudio(volume, batchId)
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }
    }

    // Returns this bus's current linear gain.
    mtd volume()->f32 fail
    {
        if not .handle do
            fail BadParameterError{"bus is not valid"}
        switch g_Driver.kind
        {
        case .NoSound:
            return try .volumeNoSound()

        case .XAudio2:
            #static if #os == Swag.TargetOs.Windows
            {
                return try .volumeXAudio2()
            }
            else do
                fail UnsupportedFormatError{"XAudio2 is not available"}

        case .FAudio:
            #static if #os == Swag.TargetOs.Linux
            {
                return try .volumeFAudio()
            }
            else do
                fail UnsupportedFormatError{"FAudio is not available"}

        case .Default:
            break
        }

        return 0
    }
}
