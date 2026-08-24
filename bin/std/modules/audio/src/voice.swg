using Core, Core.Errors

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
        file:                #null const *SoundFile     // Borrowed source, alive for the voice's lifetime.
        dataMutex:           Sync.Mutex                 // Serializes buffer feeding with transport changes.

        requestedEncoding               = SoundFileEncoding.Unknown     // Encoding the caller asked to decode to.
        codec:       #null ICodec       = null                          // Decoder instance for a streamed source.
        packetCodec: #null IPacketCodec = null                          // Decoder instance for packetized media.

        playFlags:         VoicePlayFlags                   // Flags 'play' was given.
        state:             VoiceState                       // Where the voice is in its lifecycle.
        idxInList:         u32                              // Slot of the voice in the driver's list.
        stream:            File.FileStream                  // Reader over the encoded source.
        streamCurSeek:     u64                              // Read position in the encoded source.
        streamBuffer:      Array'u8                         // Encoded bytes waiting to be decoded.
        packetBuffer:      Array'u8 = {}                    // One compressed access unit read from its source.
        packetScratch:     Array'u8 = {}                    // Decoded packet used when a seek trims its prefix.
        decodedBuffers:    [NumDecodedBuffers] Array'u8     // Decoded buffers rotated while streaming.
        decodedBufferIdx:  u32                              // Buffer the mixing thread reads next.
        streamPacketIdx:   u64                              // Next compressed packet in playback order.
        seekDiscardFrames: u32                              // Leading decoded frames omitted after a seek.

        playbackBaseFrame: u64     // Source frame corresponding to the native origin.
        nativeFrameOrigin: u64     // Backend sample counter captured at the last seek.
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
        .streamPacketIdx   = 0
        .seekDiscardFrames = 0
        .playbackBaseFrame = 0
        .nativeFrameOrigin = 0
        .requestedEncoding = .Unknown
        .destroyCodec()
        .destroyPacketCodec()
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
        .destroyPacketCodec()
    }

    // Creates a controllable playback instance for a sound file.
    //
    // Multiple voices may borrow the same [[Audio.SoundFile]]. `file` must
    // outlive the returned voice. The caller owns the voice and must call
    // [[Audio.Voice.destroy]] unless a later playback uses
    // [[Audio.VoicePlayFlags.DestroyOnStop]]. Success returns a non-null pointer.
    func create(file: const *SoundFile, createFlags = VoiceCreateFlags.Default)->#null *Voice fail
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
    func play(file: const *SoundFile, createFlags = VoiceCreateFlags.Default, playFlags = VoicePlayFlags.Default)->#null *Voice fail
    {
        let voice = create(file, createFlags)!
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
        .dataMutex.lock()
        defer .dataMutex.unlock()
        if .hasState(.Playing) do
            return
        .playFlags = playFlags
        .playNative()
        .setState(.Playing)

        if !.hasState(.PlayedOnce)
        {
            .setState(.PlayedOnce)
            .nativeFrameOrigin = .playedFramesNative()
            g_Driver.updateVoice(me, .UpdateBuffers)
        }
    }

    // Pauses playback while preserving the current stream position.
    //
    // Calling this on a voice that is not playing has no effect.
    mtd pause() fail
    {
        .dataMutex.lock()
        defer .dataMutex.unlock()
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
        .dataMutex.lock()
        defer .dataMutex.unlock()
        if !.hasState(.PlayedOnce) do
            return
        if .hasState(.Playing) do
            .stopNative()
        .resetNative()
        .closeBuffer()
        .playbackBaseFrame = 0
        .nativeFrameOrigin = .playedFramesNative()
        .resetState(.Playing | .PlayedOnce)
        if .playFlags.has(.DestroyOnStop) do
            .destroy()
    }

    // Seeks to a decoded sample frame and preserves whether playback was running.
    //
    // Compressed packet sources restart on the packet containing `frame`; decoded frames before
    // the requested position are discarded before submission. Indexed PCM sources seek directly
    // inside their chunk. The backend queue is flushed, so [[Audio.Voice.playbackSampleFrame]]
    // immediately uses the new position as its origin.
    mtd seekSampleFrame(frame: u64) fail
    {
        .dataMutex.lock()
        defer .dataMutex.unlock()
        if !.handle or !.file do
            fail BadParameterError{"voice is not valid"}
        let file       = .file!
        let target     = Math.min(frame, file.frameCount)
        let wasPlaying = .hasState(.Playing)
        if wasPlaying do
            .stopNative()
        .resetNative()
        .closeData()
        .destroyCodec()
        .destroyPacketCodec()
        .streamCurSeek     = 0
        .streamPacketIdx   = 0
        .seekDiscardFrames = 0
        .playbackBaseFrame = target

        if file.usesPacketCodec() and target < file.frameCount
        {
            var low  = 0'u64
            var high = file.packetStarts.count
            while low + 1 < high
            {
                let middle = low + (high - low) / 2
                if file.packetStarts[middle] <= target do
                    low = middle
                else do
                    high = middle
            }

            // AAC synthesis overlaps the current transform with the preceding access unit.
            // Decode one preroll packet and discard it so a random seek has the same samples as
            // uninterrupted playback from the very first audible frame.
            let preroll = low ? low - 1 : low
            .streamPacketIdx   = preroll
            .seekDiscardFrames = cast(u32) (target - file.packetStarts[preroll])
        }
        elif !file.usesPacketCodec()
        {
            let bytesPerFrame = cast(u64) file.channelCount * cast(u64) (file.bitsPerSample / 8)
            .streamCurSeek = Math.min(target * bytesPerFrame, file.dataSize)
        }
        else do
            .streamPacketIdx = file.packets.count

        .nativeFrameOrigin = .playedFramesNative()
        if wasPlaying
        {
            .setState(.PlayedOnce)
            .playNative()
            .setState(.Playing)
            g_Driver.updateVoice(me, .UpdateBuffers)
            return
        }

        // The seek discarded every queued buffer and a paused voice submits none, so the source
        // is no longer primed. Saying otherwise would make the next [[Audio.Voice.play]] take a
        // running voice for granted and start the backend on an empty queue: it would report
        // itself playing, stay silent, and never advance its played-sample count. This is the
        // same reset [[Audio.Voice.stop]] performs after discarding its own buffers.
        .resetState(.PlayedOnce)
    }

    // Returns the decoded source sample frame currently heard at the output device.
    mtd playbackSampleFrame()->u64
    {
        if !.handle or !.file do
            return 0
        let native   = .playedFramesNative()
        let advanced = native >= .nativeFrameOrigin ? native - .nativeFrameOrigin : 0
        return Math.min(.playbackBaseFrame + advanced, .file!.frameCount)
    }

    // Returns the output-device playback position in seconds.
    mtd playbackPositionSeconds()->f64
    {
        if !.file or !.file!.sampleRate do
            return 0
        return cast(f64) .playbackSampleFrame() / cast(f64) .file!.sampleRate
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
