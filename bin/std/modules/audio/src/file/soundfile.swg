#global public

using Core, Core.Errors

// Identifies which sound-file properties were discovered while loading.
#[Swag.EnumFlags]
enum SoundFileFields
{
    None = 0               // No property has been validated.
    Format                 // The source encoding is known.
    SampleRate             // The sample rate is known.
    ChannelCount           // The number of interleaved channels is known.
    SpeakerMask            // The WAVE speaker-position mask is known.
    BitsPerSample          // The storage width of one channel sample is known.
    Duration               // The duration in seconds is known.
    FrameCount             // The number of sample frames is known.
    ValidBitsPerSample     // The significant bit count inside each sample is known.
    Data                   // The location and byte size of the audio payload are known.
}

// Describes the in-memory encoding of sound samples.
enum SoundFileEncoding
{
    Unknown     // The loader or codec has not identified the encoding.
    Pcm8        // Unsigned, uncompressed 8-bit PCM.
    Pcm16       // Signed, uncompressed 16-bit PCM.
    Pcm24       // Signed, uncompressed 24-bit PCM.
    Pcm32       // Signed, uncompressed 32-bit PCM.
    Float32     // Uncompressed 32-bit IEEE floating-point samples.
}

// Describes a validated sound source that may be prefetched or streamed.
//
// The value owns the bytes exposed by [[Audio.SoundFile.preloadedData]]. When
// the payload is not prefetched, voices reopen the source path and read the
// payload on demand. Keep this value alive while any voice borrows it.
#[Swag.Opaque]
struct SoundFile
{
    internal
    {
        path: String       // Source path used for deferred streaming reads.
        data: Array'u8     // Prefetched payload bytes in [[Audio.SoundFile.sampleEncoding]].

        frameCount: u64     // Number of sample frames across all channels.
        dataSize:   u64     // Payload size in bytes.
        dataOffset: u64     // Byte offset of the payload in the source file.

        encoding = SoundFileEncoding.Unknown     // Encoding of the payload bytes.

        availableFields:    SoundFileFields     // Properties validated by the loader.
        sampleRate:         u32                 // Sample frames per second, in hertz.
        channelCount:       u32                 // Number of interleaved channels.
        waveSpeakerMask:    u32                 // WAVE speaker-position bit mask, when present.
        bitsPerSample:      u32                 // Storage width of one channel sample, in bits.
        durationSeconds:    f32                 // Playback duration in seconds.
        validBitsPerSample: u16                 // Significant bits per sample, at most `bitsPerSample`.
    }
}

impl SoundFile
{
    // Returns the source path used to load this sound.
    mtd const sourcePath()->string => .path

    // Returns the payload bytes retained in memory.
    //
    // The slice is empty when loading used `preloadData: false` and remains
    // valid only while this sound file remains alive and unchanged.
    mtd const preloadedData()->const [..] u8 => .data.toSlice()

    // Returns whether the complete payload is retained in memory.
    mtd const isDataPreloaded()->bool => .data.count == .dataSize

    // Reads an owned range of the validated audio payload.
    //
    // `offset` is relative to the first payload byte. The range is clamped at the payload end,
    // and an offset at or beyond that end returns an empty array. A prefetched sound copies from
    // memory; a streamed sound reopens its source and can therefore be sampled independently of
    // any voice reading the same file.
    mtd const readPayload(offset, count: u64)->Array'u8 fail
    {
        var result: retval
        if !count or offset >= .dataSize do
            return result

        let wanted = Math.min(count, .dataSize - offset)
        result.resize(wanted)
        if .isDataPreloaded()
        {
            Memory.copy(result.buffer, .data.buffer + offset, wanted)
            return result
        }

        var stream = File.openRead(.path.toString())
        stream.seek(.Begin, .dataOffset + offset)
        let read = stream.read(result.toSlice())
        result.resize(read)
        return result
    }

    // Returns the validated payload encoding.
    mtd const sampleEncoding()->SoundFileEncoding => .encoding

    // Returns the number of sample frames across all channels.
    mtd const sampleFrameCount()->u64 => .frameCount

    // Returns the payload size in bytes.
    mtd const payloadSize()->u64 => .dataSize

    // Returns the sample rate in hertz.
    mtd const sampleRateHz()->u32 => .sampleRate

    // Returns the number of interleaved channels.
    mtd const numChannels()->u32 => .channelCount

    // Returns the speaker-position mask, or zero when the source omits it.
    mtd const speakerChannelMask()->u32 => .waveSpeakerMask

    // Returns the storage width of one channel sample, in bits.
    mtd const sampleStorageBits()->u32 => .bitsPerSample

    // Returns the significant width of one sample, in bits.
    mtd const sampleValidBits()->u16 => .validBitsPerSample

    // Returns the playback duration in seconds.
    mtd const durationInSeconds()->f32 => .durationSeconds

    // Returns whether the loader validated the requested property.
    mtd const hasField(field: SoundFileFields)->bool => .availableFields.has(field)

    // Loads and validates a WAV sound file.
    //
    // `preloadData` keeps the complete payload in memory; otherwise voices stream
    // it from `path`. Unsupported extensions, encodings, and malformed files fail.
    func load(path: string, preloadData = true)->SoundFile fail
    {
        if Path.lowercaseExtension(path) != ".wav" do
            fail UnsupportedFormatError{"unsupported file extension"}

        var result: retval
        var stream = File.openRead(path)
        Wav.load(&result, &stream, preloadData)
        result.path = path
        return result
    }
}
