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
    AacLc       // MPEG-4 AAC Low Complexity access units.
    Ac3         // Dolby Digital AC-3 sync frames.
    Eac3        // Dolby Digital Plus E-AC-3 sync frames.
    Flac        // Free Lossless Audio Codec frames.
}

// Configures an indexed compressed sound stream.
struct PacketStreamOptions
{
    public
    {
        leadingTrimFrames: u64     // Decoded priming frames omitted before audible frame zero.
        speakerMask:       u32     // WAVE speaker-position mask; zero derives the standard mask from the channel count.
        timelineStartSeconds: f64  // Position of audible frame zero on the containing media timeline, in seconds.
    }
}

// Locates one indexed packet or chunk in a source file.
//
// Payloads need not be contiguous. `sampleFrameCount` is the number of decoded
// sample frames contributed by the packet, across all interleaved channels.
// Packet order is playback order.
struct SoundPacket
{
    public
    {
        sourceOffset:     u64     // Absolute byte offset of the packet payload in the source file.
        byteSize:         u32     // Packet or chunk payload size in bytes.
        sampleFrameCount: u32     // Decoded sample frames contributed by this packet.
    }
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
        path:          String                // Source path used for deferred streaming reads.
        data:          Array'u8              // Prefetched payload bytes in [[Audio.SoundFile.sampleEncoding]].
        packets:       Array'SoundPacket     // Indexed source packets or chunks, empty for one contiguous byte stream.
        packetStarts:  Array'u64             // Decoded sample-frame start of every packet.
        decoderConfig: Array'u8              // Codec initialization bytes copied from the container.
        leadingTrim:   u64                   // Decoded priming frames before audible frame zero.
        timelineStart: f64                   // Position of frame zero on an enclosing media timeline.

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

    // Returns whether this source is made of independently indexed packets.
    mtd const isPacketStream()->bool => .packets.count != 0

    // Returns whether indexed packets need the compressed packet codec.
    internal mtd const usesPacketCodec()->bool => isPacketEncoding(.encoding) and .packets.count != 0

    // Returns the number of indexed packets or chunks in this source.
    mtd const packetCount()->u64 => .packets.count

    // Returns packet `index` in playback order.
    mtd const packet(index: u64)->SoundPacket fail
    {
        if index >= .packets.count do
            fail BadParameterError{"sound packet index exceeds the packet count"}
        return .packets[index]
    }

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
        if .packets.count
        {
            var stream        = File.openRead(.path.toString())
            var logicalStart  = 0'u64
            var logicalOffset = offset
            var written       = 0'u64
            for packet in .packets
            {
                let logicalEnd = logicalStart + packet.byteSize
                if logicalOffset < logicalEnd and written < wanted
                {
                    let packetSkip = logicalOffset > logicalStart ? logicalOffset - logicalStart : 0
                    let available  = cast(u64) packet.byteSize - packetSkip
                    let readSize   = Math.min(available, wanted - written)
                    stream.seek(.Begin, packet.sourceOffset + packetSkip)
                    if stream.read(result.buffer! + written, readSize) != readSize do
                        fail InvalidFormatError{"sound packet or chunk is truncated"}
                    written       += readSize
                    logicalOffset += readSize
                }

                logicalStart = logicalEnd
                if written == wanted do
                    break
            }

            result.resize(written)
            return result
        }

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

    // Returns the position of frame zero on the containing media timeline, in seconds.
    //
    // Standalone sounds and complete container tracks start at zero. A container may expose a
    // bounded packet window with a later origin so a player can seek without indexing the entire
    // media file first.
    mtd const timelineStartSeconds()->f64 => .timelineStart

    // Returns whether the loader validated the requested property.
    mtd const hasField(field: SoundFileFields)->bool => .availableFields.has(field)

    // Loads and validates a sound file.
    //
    // `preloadData` keeps the complete payload in memory; otherwise voices stream
    // it from `path`. A FLAC file is always streamed — its audio is compressed, so keeping it in
    // memory would keep the wrong bytes — and `preloadData` does not apply to it. Unsupported
    // extensions, encodings, and malformed files fail.
    func load(path: string, preloadData = true)->SoundFile fail
    {
        let extension = Path.lowercaseExtension(path)
        if extension == ".flac"
        {
            return try Flac.openFile(path)
        }

        if extension != ".wav" do
            fail UnsupportedFormatError{"unsupported file extension"}

        var result: retval
        var stream = File.openRead(path)
        Wav.load(&result, &stream, preloadData)
        result.path = path
        return result
    }

    // Creates a streamed compressed sound from a container's packet index.
    //
    // The packet table and decoder configuration are copied, while media bytes stay in
    // `path` and are read only as playback reaches them. Memory holds the compact packet index,
    // never the compressed media payload. `frameCount` is validated against the sum of packet
    // durations. `options.timelineStartSeconds` locates frame zero on an enclosing media timeline;
    // voice seeking and playback positions remain local to this sound.
    func openPacketStream(path: string, encoding: SoundFileEncoding, sampleRateHz, channels: u32, frameCount: u64, packets: const [..] SoundPacket, decoderConfig: const [..] u8, options: PacketStreamOptions = {})->SoundFile fail
    {
        if !isPacketEncoding(encoding) do
            fail UnsupportedFormatError{"unsupported packetized sound encoding"}
        if !sampleRateHz or !channels or channels > 8 do
            fail BadParameterError{"packetized sound needs one to eight channels and a non-zero sample rate"}
        if !@countof(packets) do
            fail BadParameterError{"packetized sound needs packets"}
        if (encoding == .AacLc or encoding == .Flac) and !@countof(decoderConfig) do
            fail BadParameterError{"packetized sound needs decoder configuration"}

        var stream     = File.openRead(path)
        let sourceSize = stream.size()

        var result: retval
        result.path               = path
        result.encoding           = encoding
        result.sampleRate         = sampleRateHz
        result.channelCount       = channels
        result.bitsPerSample      = 16
        result.validBitsPerSample = 16
        result.waveSpeakerMask    = options.speakerMask
        result.timelineStart      = options.timelineStartSeconds
        if !Math.isFinite(result.timelineStart) or result.timelineStart < 0 do
            fail BadParameterError{"sound timeline start is not finite and non-negative"}
        if !result.waveSpeakerMask
        {
            switch channels
            {
            case 1: result.waveSpeakerMask = 0x0004
            case 2: result.waveSpeakerMask = 0x0003
            case 3: result.waveSpeakerMask = 0x0007
            case 4: result.waveSpeakerMask = 0x0107
            case 5: result.waveSpeakerMask = 0x0037
            case 6: result.waveSpeakerMask = 0x003F
            case 7: result.waveSpeakerMask = 0x070F
            case 8: result.waveSpeakerMask = 0x063F
            }
        }

        result.leadingTrim = options.leadingTrimFrames
        result.packets.reserve(@countof(packets))
        result.packetStarts.reserve(@countof(packets))
        result.decoderConfig.add(decoderConfig)

        var decodedFrames = 0'u64
        var payloadBytes  = 0'u64
        for packet in packets
        {
            if !packet.byteSize or !packet.sampleFrameCount do
                fail BadParameterError{"sound packets need non-zero byte and sample-frame counts"}
            if packet.sourceOffset > sourceSize or cast(u64) packet.byteSize > sourceSize - packet.sourceOffset do
                fail InvalidFormatError{"sound packet runs past the end of its source file"}
            if decodedFrames > Swag.U64.Max - packet.sampleFrameCount or payloadBytes > Swag.U64.Max - packet.byteSize do
                fail OverflowError{"sound packet table is too large"}

            result.packetStarts.add(decodedFrames)
            result.packets.add(packet)
            decodedFrames += packet.sampleFrameCount
            payloadBytes  += packet.byteSize
        }

        if decodedFrames != frameCount do
            fail InvalidFormatError{"sound packet durations do not match the declared frame count"}
        if result.leadingTrim > Swag.U32.Max do
            fail UnsupportedFormatError{"sound priming exceeds the supported seek-discard range"}
        if result.leadingTrim >= decodedFrames do
            fail InvalidFormatError{"sound priming consumes every decoded frame"}

        result.frameCount      = frameCount - result.leadingTrim
        result.dataSize        = payloadBytes
        result.durationSeconds = cast(f32) result.frameCount / cast(f32) sampleRateHz
        result.availableFields = .Format | .SampleRate | .ChannelCount | .SpeakerMask | .BitsPerSample | .ValidBitsPerSample | .Duration | .FrameCount | .Data
        return result
    }

    // Creates a streamed PCM sound from a container's chunk index.
    //
    // The chunk table is copied, while sample bytes stay in `path` and are read only as playback
    // reaches them. Every chunk must hold complete interleaved sample frames in playback order.
    // Supported encodings are 8-, 16-, 24-, and 32-bit integer PCM.
    func openPcmPacketStream(path: string, encoding: SoundFileEncoding, sampleRateHz, channels: u32, packets: const [..] SoundPacket)->SoundFile fail
    {
        var bitsPerSample: u32
        switch encoding
        {
        case .Pcm8:  bitsPerSample = 8
        case .Pcm16: bitsPerSample = 16
        case .Pcm24: bitsPerSample = 24
        case .Pcm32: bitsPerSample = 32
        default:     fail UnsupportedFormatError{"packetized PCM stream only supports 8-, 16-, 24-, and 32-bit integer PCM"}
        }

        if !sampleRateHz or !channels do
            fail BadParameterError{"packetized PCM needs channels and a non-zero sample rate"}
        if !@countof(packets) do
            fail BadParameterError{"packetized PCM needs source chunks"}
        let bytesPerFrame = cast(u64) channels * cast(u64) (bitsPerSample / 8)
        var stream        = File.openRead(path)
        let sourceSize    = stream.size()

        var result: retval
        result.path               = path
        result.encoding           = encoding
        result.sampleRate         = sampleRateHz
        result.channelCount       = channels
        result.bitsPerSample      = bitsPerSample
        result.validBitsPerSample = cast(u16) bitsPerSample
        if channels == 1 do
            result.waveSpeakerMask = 4
        elif channels == 2 do
            result.waveSpeakerMask = 3
        result.packets.reserve(@countof(packets))
        result.packetStarts.reserve(@countof(packets))

        for packet in packets
        {
            if !packet.byteSize or !packet.sampleFrameCount do
                fail BadParameterError{"PCM source chunks need non-zero byte and sample-frame counts"}
            if packet.sourceOffset > sourceSize or cast(u64) packet.byteSize > sourceSize - packet.sourceOffset do
                fail InvalidFormatError{"PCM source chunk runs past the end of its source file"}
            if cast(u64) packet.sampleFrameCount > Swag.U64.Max / bytesPerFrame or cast(u64) packet.sampleFrameCount * bytesPerFrame != packet.byteSize do
                fail InvalidFormatError{"PCM source chunk size does not match its sample-frame count"}
            if result.frameCount > Swag.U64.Max - packet.sampleFrameCount or result.dataSize > Swag.U64.Max - packet.byteSize do
                fail OverflowError{"packetized PCM stream exceeds the supported size"}

            result.packetStarts.add(result.frameCount)
            result.packets.add(packet)
            result.frameCount += packet.sampleFrameCount
            result.dataSize   += packet.byteSize
        }

        result.durationSeconds = cast(f32) result.frameCount / cast(f32) sampleRateHz
        result.availableFields = .Format | .SampleRate | .ChannelCount | .BitsPerSample | .ValidBitsPerSample | .Duration | .FrameCount | .Data
        if result.waveSpeakerMask do
            result.availableFields |= .SpeakerMask
        return result
    }
}
