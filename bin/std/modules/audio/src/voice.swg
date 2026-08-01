using Core, Core.Errors, Win32

// Selects optional backend capabilities for a new voice.
#[Swag.EnumFlags]
public enum VoiceCreateFlags
{
    None = 0                   // Requests no optional capability.
    PitchControl               // Allows playback frequency changes.
    Default = PitchControl     // Enables all supported optional capabilities.
}

// Controls one playback run and its end-of-playback lifetime.
#[Swag.EnumFlags]
public enum VoicePlayFlags
{
    None = 0                    // Plays once and leaves the voice allocated when it stops.
    Loop                        // Restarts at the beginning when the source reaches its end.
    DestroyOnStop               // Schedules the voice for destruction when playback stops.
    Default = DestroyOnStop     // Uses fire-and-forget lifetime without looping.
}

// Reports internal playback and destruction state.
#[Swag.EnumFlags]
#[Swag.NoDoc]
public enum VoiceState
{
    None = 0           // The voice has not started playback.
    PlayedOnce         // At least one playback run has initialized its source buffers.
    Playing            // The backend is currently advancing this voice.
    PendingDestroy     // Destruction has been requested and will complete asynchronously.
}

// Controls one playback instance of a sound file.
//
// A voice borrows its source [[Audio.SoundFile]], which must remain alive until
// the voice is destroyed. Use [[Audio.Voice.play]] for fire-and-forget playback
// or [[Audio.Voice.create]] when the caller needs explicit control.
#[Swag.Opaque]
public struct Voice
{
    const StreamBufferSize  = 16 * 1024'u64     // Number of encoded bytes read per streaming step.
    const NumDecodedBuffers = 3                 // Number of decoded buffers rotated during streaming.
    const DecodedBufferSize = 65536'u64         // Capacity in bytes of each decoded streaming buffer.

    // Playback state, owned by the voice and by the driver that drains it. A caller drives a
    // voice through its methods; touching this state from outside the module races the driver.
    internal
    {
        allocationAllocator: IAllocator = undefined     // Allocator that owns this voice and its buffers.
        handle:              #null *void                // Identity of the voice inside the driver.
        file:                #null *SoundFile           // Borrowed source, alive for the voice's lifetime.

        requestedEncoding = SoundFileEncoding.Unknown     // Encoding the caller asked to decode to.
        codec: #null ICodec                               // Decoder instance for a streamed source.

        playFlags:        VoicePlayFlags                   // Flags 'play' was given.
        state:            VoiceState                       // Where the voice is in its lifecycle.
        idxInList:        u32                              // Slot of the voice in the driver's list.
        stream:           File.FileStream                  // Reader over the encoded source.
        streamCurSeek:    u64                              // Read position in the encoded source.
        streamBuffer:     Array'u8                         // Encoded bytes waiting to be decoded.
        decodedBuffers:   [NumDecodedBuffers] Array'u8     // Decoded buffers rotated while streaming.
        decodedBufferIdx: u32                              // Buffer the mixing thread reads next.
    }
}

private impl Voice
{
    mtd recycle()
    {
        .file              = null
        .playFlags         = .None
        .state             = .None
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
    // [[Audio.VoicePlayFlags.DestroyOnStop]]. Success returns a non-null pointer.
    func create(file: *SoundFile, createFlags = VoiceCreateFlags.Default)->#null *Voice fail
    {
        if !g_Driver.isCreated do
            fail BadParameterError{"audio engine is not created"}
        if !file.availableFields.has(.Data) do
            fail BadParameterError{"sound file has no audio data"}

        let voice = g_Driver.createVoice()
        defer #fail
        {
            voice.destroyNative()
            let allocator = voice.allocationAllocator
            Memory.delete(voice, allocator)
        }

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
        defer #fail voice.destroy()
        voice.play(playFlags)
        return voice
    }

    // Starts or resumes this voice.
    //
    // The default keeps the voice allocated after it stops. Add
    // [[Audio.VoicePlayFlags.DestroyOnStop]] for automatic cleanup, or call
    // [[Audio.Voice.destroy]] explicitly. Calling this while already playing
    // has no effect.
    mtd play(playFlags = VoicePlayFlags.None) fail
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

    // Stops playback, discards queued backend buffers, and rewinds to the beginning.
    //
    // If the active play flags include
    // [[Audio.VoicePlayFlags.DestroyOnStop]], this also schedules destruction.
    mtd stop() fail
    {
        if !.hasState(.PlayedOnce) do
            return
        if .hasState(.Playing) do
            .stopNative()
        .resetNative()
        .closeBuffer()
        .resetState(.Playing | .PlayedOnce)
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
    // `batchId` is forwarded to backends that support deferred operation sets.
    mtd setVolumeDb(decibels: f32, batchId: u32 = 0) fail
    {
        .setVolume(decibelsToLinearGain(decibels), batchId)
    }

    // Returns this voice's current gain in decibels.
    mtd volumeDb()->f32 fail
    {
        return linearGainToDecibels(.volume())
    }
}
