#global public

using Core, Core.Errors

// Identifies which sound-file properties were discovered while loading.
#[Swag.EnumFlags]
enum SoundFileValidityMask
{
    Zero = 0               // No property has been validated.
    Format                 // The source encoding is known.
    Frequency              // The sample frequency is known.
    ChannelCount           // The number of interleaved channels is known.
    ChannelMask            // The speaker-position mask is known.
    BitsPerSample          // The storage width of one channel sample is known.
    Duration               // The duration in seconds is known.
    SampleCount            // The number of sample frames is known.
    ValidBitsPerSample     // The significant bit count inside each sample is known.
    Data                   // The location and byte size of the audio payload are known.
    MetaData               // Reserved for loader-provided metadata availability.
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
// The value owns any bytes in [[Audio.SoundFile.datas]]. When the payload is
// not prefetched, voices reopen [[Audio.SoundFile.fullname]] and read from
// `dataSeek` on demand. Keep this value alive while any voice borrows it.
struct SoundFile
{
    fullname: String       // Source path used for deferred streaming reads.
    datas:    Array'u8     // Prefetched payload bytes in [[Audio.SoundFile.encoding]].

    sampleCount: u64     // Number of sample frames across all channels.
    dataSize:    u64     // Payload size in bytes.
    dataSeek:    u64     // Byte offset of the payload in the source file.

    encoding = SoundFileEncoding.Unknown     // Encoding of the payload bytes.

    validity:           SoundFileValidityMask     // Properties validated by the loader.
    frequency:          u32                       // Sample frames per second, in hertz.
    channelCount:       u32                       // Number of interleaved channels.
    channelMask:        u32                       // Windows speaker-position bit mask, when present.
    bitsPerSample:      u32                       // Storage width of one channel sample, in bits.
    duration:           f32                       // Playback duration in seconds.
    validBitsPerSample: u16                       // Significant bits per sample, at most `bitsPerSample`.
}

impl SoundFile
{
    // Loads and validates a WAV sound file.
    //
    // `loadDatas` keeps the complete payload in memory; otherwise voices stream
    // it from `fullname`. `loadMetaDatas` continues scanning auxiliary chunks
    // after the audio payload. Unsupported extensions, encodings, and malformed
    // files fail.
    func load(fullname: string, loadDatas = true, loadMetaDatas = false)->SoundFile fail
    {
        if Path.getExtensionLowerCase(fullname) != ".wav" do
            fail UnsupportedFormatError{"unsupported file extension"}

        var result: retval
        var stream = File.openRead(fullname)
        Wav.loadFile(&result, &stream, loadDatas, loadMetaDatas)
        result.fullname = fullname
        return result
    }
}
