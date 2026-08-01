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
    ChannelMask            // The speaker-position mask is known.
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
// The value owns any bytes in [[Audio.SoundFile.data]]. When the payload is not
// prefetched, voices reopen [[Audio.SoundFile.path]] and read from `dataOffset`
// on demand. Keep this value alive while any voice borrows it.
struct SoundFile
{
    path: String       // Source path used for deferred streaming reads.
    data: Array'u8     // Prefetched payload bytes in [[Audio.SoundFile.encoding]].

    frameCount: u64     // Number of sample frames across all channels.
    dataSize:   u64     // Payload size in bytes.
    dataOffset: u64     // Byte offset of the payload in the source file.

    encoding = SoundFileEncoding.Unknown     // Encoding of the payload bytes.

    availableFields:    SoundFileFields     // Properties validated by the loader.
    sampleRate:         u32                 // Sample frames per second, in hertz.
    channelCount:       u32                 // Number of interleaved channels.
    channelMask:        u32                 // Windows speaker-position bit mask, when present.
    bitsPerSample:      u32                 // Storage width of one channel sample, in bits.
    durationSeconds:    f32                 // Playback duration in seconds.
    validBitsPerSample: u16                 // Significant bits per sample, at most `bitsPerSample`.
}

impl SoundFile
{
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
