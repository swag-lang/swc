using Core, Win32

// Selects optional backend capabilities for a new voice.
#[Swag.EnumFlags]
public enum VoiceCreateFlags
{
    Zero = 0                            // Requests no optional capability.
    AcceptPitch                         // Allows playback frequency changes.
    AcceptFilters                       // Reserves backend support for voice filters.
    Default = AcceptFilters | AcceptPitch // Enables all supported optional capabilities.
}

// Controls one playback run and its end-of-playback lifetime.
#[Swag.EnumFlags]
public enum VoicePlayFlags
{
    Zero = 0                // Plays once and leaves the voice allocated when it stops.
    Loop                    // Restarts at the beginning when the source reaches its end.
    DestroyOnStop           // Schedules the voice for destruction when playback stops.
    Default = DestroyOnStop // Uses fire-and-forget lifetime without looping.
}

// Reports internal playback and destruction state.
#[Swag.EnumFlags]
public enum VoiceState
{
    Zero = 0       // The voice has not started playback.
    PlayedOnce     // At least one playback run has initialized its source buffers.
    Playing        // The backend is currently advancing this voice.
    PendingDestroy // Destruction has been requested and will complete asynchronously.
}

// Controls one playback instance of a sound file.
//
// A voice borrows its source [[Audio.SoundFile]], which must remain alive until
// the voice is destroyed. Use [[Audio.Voice.play]] for fire-and-forget playback
// or [[Audio.Voice.create]] when the caller needs explicit control.
#[Swag.Opaque]
public struct Voice
{
    handle: VoiceHandle
    file:   #null *SoundFile

    requestedEncoding = SoundFileEncoding.Unknown
    codec: #null ICodec

    playFlags:        VoicePlayFlags
    state:            VoiceState
    idxInList:        u32
    const StreamBufferSize  = 16 * 1024'u64 // Number of encoded bytes read per streaming step.
    stream:           File.FileStream
    streamCurSeek:    u64
    streamBuffer:     Array'u8
    const NumDecodedBuffers = 3         // Number of decoded buffers rotated during streaming.
    const DecodedBufferSize = 65536'u64 // Capacity in bytes of each decoded streaming buffer.
    decodedBuffers:   [NumDecodedBuffers] Array'u8
    decodedBufferIdx: u32
}

private impl Voice
{
    mtd recycle()
    {
        .file              = null
        .playFlags         = .Zero
        .state             = .Zero
        .idxInList         = 0
        .streamCurSeek     = 0
        .decodedBufferIdx  = 0
        .requestedEncoding = .Unknown
        .destroyCodec()
    }

    mtd hasState(st: VoiceState)->bool
    {
        return Atomic.get(cast(*u32) &.state) & cast(u32) st ? true : false
    }

    mtd setState(st: VoiceState)
    {
        discard Atomic.logicOr(cast(*u32) &.state, cast(u32) st)
    }

    mtd resetState(st: VoiceState)
    {
        discard Atomic.logicAnd(cast(*u32) &.state, ~cast(u32) st)
    }
}

public impl Voice
{
    // Releases codec and streaming resources owned by this value.
    mtd opDrop()
    {
        .destroyCodec()
    }

    // Creates a controllable playback instance for a sound file.
    //
    // Multiple voices may borrow the same [[Audio.SoundFile]]. `file` must
    // outlive the returned voice. The caller owns the voice and must call
    // [[Audio.Voice.destroy]] unless a later playback uses
    // [[Audio.VoicePlayFlags.DestroyOnStop]].
    func create(file: *SoundFile, createFlags = VoiceCreateFlags.Default)->#null *Voice fail
    {
        let voice = g_Driver.createVoice()
        voice.file = file

        voice.createNative(createFlags)
        g_Driver.updateVoice(voice, .Register)

        return voice
    }

    // Creates and immediately starts a voice.
    //
    // The default play flags provide fire-and-forget lifetime by scheduling the
    // voice for destruction when playback finishes. The returned pointer can be
    // retained to adjust playback while it remains valid.
    #[Swag.Discardable]
    func play(file: *SoundFile, createFlags = VoiceCreateFlags.Default, playFlags = VoicePlayFlags.Default)->#null *Voice fail
    {
        let voice = notnull create(file, createFlags)
        voice.play(playFlags)
        return voice
    }

    // Starts or resumes this voice.
    //
    // The default keeps the voice allocated after it stops. Add
    // [[Audio.VoicePlayFlags.DestroyOnStop]] for automatic cleanup, or call
    // [[Audio.Voice.destroy]] explicitly. Calling this while already playing
    // has no effect.
    mtd play(playFlags = VoicePlayFlags.Zero) fail
    {
        if .hasState(.Playing) do
            return
        .playFlags = playFlags
        .playNative()
        .setState(.Playing)

        if !.hasState(.PlayedOnce)
        {
            .setState(.PlayedOnce)
            g_Driver.updateVoice(me, .UpdateBuffers)
        }
    }

    // Pauses playback while preserving the current stream position.
    //
    // Calling this on a voice that is not playing has no effect.
    mtd pause() fail
    {
        if !.hasState(.Playing) do
            return
        .stopNative()
        .resetState(.Playing)
    }

    // Stops playback at the current stream position.
    //
    // If the active play flags include
    // [[Audio.VoicePlayFlags.DestroyOnStop]], this also schedules destruction.
    mtd stop() fail
    {
        if !.hasState(.Playing) do
            return
        .stopNative()
        .resetState(.Playing)
        if .playFlags.has(.DestroyOnStop) do
            .destroy()
    }

    // Schedules this voice and its native resources for destruction.
    //
    // Destruction is idempotent and completes on the audio update path. Do not
    // use the pointer after requesting destruction.
    mtd destroy()
    {
        if .hasState(.PendingDestroy) do
            return
        .setState(.PendingDestroy)
        g_Driver.updateVoice(me, .Destroy)
    }

    // Returns whether the voice is currently marked as playing.
    mtd isPlaying()->bool
    {
        if !.handle do
            return false
        return .hasState(.Playing)
    }

    // Sets this voice's gain in decibels.
    //
    // `batchID` is forwarded to backends that support deferred operation sets.
    mtd setVolumeDB(volumeDB: f32, batchID: u32 = 0) fail
    {
        .setVolume(convertDBToPercent(volumeDB), batchID)
    }

    // Returns this voice's current gain in decibels.
    mtd getVolumeDB()->f32 fail
    {
        return convertPercentToDB(.getVolume())
    }
}
