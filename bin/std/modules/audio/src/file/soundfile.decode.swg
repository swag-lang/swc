//! Format: Sequential sound-file decoding.
//! Supported: PCM and indexed compressed sources converted to bounded interleaved PCM16 chunks.
//! Not supported: Channel remixing, sample-rate conversion, seeking, and retaining callback slices.
//! Role: This file owns device-independent decoding for analysis and export consumers.
//
#global public

using Core, Core.Errors

private const SoundDecodeReadSize = 256 * 1024'u64

// Receives one borrowed chunk of interleaved PCM16 samples.
//
// The slice remains valid only for the duration of the call. Return `true` to continue decoding or
// `false` to stop successfully after this chunk.
alias SoundPcm16Consumer = func||(const [..] s16)->bool

impl SoundFile
{
    // Decodes this sound sequentially to interleaved PCM16 chunks.
    //
    // Compressed packets are decoded in playback order and codec priming is omitted, so the total
    // delivered frame count matches [[Audio.SoundFile.sampleFrameCount]]. PCM sources are converted
    // without requiring an audio engine. `consumer` borrows each bounded chunk only until it
    // returns; returning `false` cancels the remaining work without failure.
    mtd const decodePcm16(consumer: SoundPcm16Consumer) fail
    {
        if not .availableFields.has(.Data) or not .channelCount do
            fail BadParameterError{"sound file has no audio data"}

        if .usesPacketCodec()
        {
            try .decodePacketPcm16(consumer)
            return
        }

        var bytesPerSample: u64
        switch .encoding
        {
        case .Pcm8:    bytesPerSample = 1
        case .Pcm16:   bytesPerSample = 2
        case .Pcm24:   bytesPerSample = 3
        case .Pcm32:   bytesPerSample = 4
        case .Float32: bytesPerSample = 4
        default:       fail UnsupportedFormatError{"unsupported sound encoding"}
        }

        var codec: CodecPcmToPcm16
        codec.configure(.encoding, .Pcm16, #typeof(CodecPcmToPcm16), Swag.getContext().allocator!)
        let decoder: ICodec = &codec
        var empty:   u8
        discard try decoder.initialize(&empty, 0)

        let bytesPerFrame = bytesPerSample * .channelCount
        var byteOffset: u64
        var decoded:    Array's16
        while byteOffset < .dataSize
        {
            // Keep reads on complete interleaved frames.
            var wantedBytes = Math.min(SoundDecodeReadSize, .dataSize - byteOffset)
            wantedBytes -= wantedBytes % bytesPerFrame
            if not wantedBytes do
                break

            let source = try .readPayload(byteOffset, wantedBytes)
            if source.count != wantedBytes do
                fail InvalidFormatError{"sound payload is truncated"}
            decoded.resize(source.count / bytesPerSample)
            let outputBytes = decoded.count * #sizeof(s16)
            let progress    = try decoder.decode(decoded.storage(), outputBytes, source.storage(), source.count)
            if progress.bytesRead != source.count or progress.bytesWritten != outputBytes do
                fail InvalidFormatError{"sound payload decoded to an unexpected size"}
            if not consumer(decoded.toSlice()) do
                return
            byteOffset += source.count
        }
    }
}

private impl SoundFile
{
    mtd const decodePacketPcm16(consumer: SoundPcm16Consumer) fail
    {
        let descriptor = findPacketCodec(.encoding)
        if not descriptor do
            fail UnsupportedFormatError{"unsupported packetized encoding"}

        let allocator   = Swag.getContext().allocator!
        let decoderData = Memory.new(descriptor.type, allocator)
        let decoder     = cast(*Codec, decoderData)
        decoder.configure(.encoding, .Pcm16, descriptor.type, allocator)
        let packetCodec = Swag.makeInterface(decoder, descriptor.type, IPacketCodec)
        defer
        {
            if decoder.type.opDrop do
                decoder.type.opDrop(decoder)
            Memory.free(decoder, cast(u64, decoder.type.sizeof), allocator)
        }

        try packetCodec!.initialize(.decoderConfig.toSlice(), .sampleRate, .channelCount)
        var source        = try ByteSource.openFile(.path.toString())
        var packetBytes:  Array'u8
        var decodedBytes: Array'u8
        var discardFrames = .leadingTrim

        for packet in .packets
        {
            if packetBytes.count != packet.byteSize do
                packetBytes.resize(packet.byteSize)
            try source.seek(packet.sourceOffset)
            try source.readExact(packetBytes.toSlice())

            let decodedByteCount = cast(u64, packet.sampleFrameCount) * .channelCount * #sizeof(s16)
            if decodedBytes.count != decodedByteCount do
                decodedBytes.resize(decodedByteCount)
            let producedBytes = try packetCodec!.decodePacket(decodedBytes.storage(),
                                                              decodedByteCount,
                                                              packetBytes.toSlice())
            if producedBytes != decodedByteCount do
                fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}

            // Omit encoder priming before borrowing the samples to the consumer.
            let skippedFrames = Math.min(discardFrames, cast(u64, packet.sampleFrameCount))
            discardFrames -= skippedFrames
            let firstSample = skippedFrames * .channelCount
            let sampleCount = producedBytes / #sizeof(s16)
            if firstSample < sampleCount
            {
                let samples = cast(const [*] s16, decodedBytes.storage())
                if not consumer(samples[firstSample until sampleCount]) do
                    return
            }
        }
    }
}
