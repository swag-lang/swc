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
        if !.availableFields.has(.Data) or !.channelCount do
            fail BadParameterError{"sound file has no audio data"}

        if .usesPacketCodec()
        {
            let desc = findPacketCodec(.encoding)
            if !desc do
                fail UnsupportedFormatError{"unsupported packetized encoding"}

            let allocator   = Swag.getContext().allocator!
            let decoderData = Memory.new(desc.type, allocator)!
            let decoder     = cast(*Codec) decoderData
            decoder.configure(.encoding, .Pcm16, desc.type, allocator)
            let packetCodec = Swag.makeInterface(decoder, desc.type, IPacketCodec)
            defer
            {
                if decoder.type.opDrop do
                    decoder.type.opDrop(decoder)
                Memory.free(decoder, cast(u64) decoder.type.sizeof, allocator)
            }

            try packetCodec!.initialize(.decoderConfig.toSlice(), .sampleRate, .channelCount)
            var stream        = File.open(.path.toString(), File.FileMode.Open, File.FileAccess.Read, File.FileShare.Read)
            var packetBytes:  Array'u8
            var decodedBytes: Array'u8
            var discardFrames = .leadingTrim

            for packet in .packets
            {
                if packetBytes.count != packet.byteSize do
                    packetBytes.resize(packet.byteSize)
                stream.seek(.Begin, packet.sourceOffset)
                if stream.read(packetBytes.toSlice()) != packet.byteSize do
                    fail InvalidFormatError{"compressed sound packet is truncated"}

                let decodedSize = cast(u64) packet.sampleFrameCount * .channelCount * #sizeof(s16)
                if decodedBytes.count != decodedSize do
                    decodedBytes.resize(decodedSize)
                let produced = try packetCodec!.decodePacket(decodedBytes.buffer!, decodedSize, packetBytes.toSlice())
                if produced != decodedSize do
                    fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}

                let skippedFrames = Math.min(discardFrames, cast(u64) packet.sampleFrameCount)
                discardFrames -= skippedFrames
                let firstSample = skippedFrames * .channelCount
                let sampleCount = produced / #sizeof(s16)
                if firstSample < sampleCount
                {
                    let samples = cast(const [*] s16) decodedBytes.buffer!
                    if !consumer(samples[firstSample until sampleCount]) do
                        return
                }
            }

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
        let itf:   ICodec = &codec
        var empty: u8
        discard try itf.initialize(&empty, 0)

        let bytesPerFrame = bytesPerSample * .channelCount
        var byteOffset: u64
        var decoded:    Array's16
        while byteOffset < .dataSize
        {
            var wanted = Math.min(SoundDecodeReadSize, .dataSize - byteOffset)
            wanted -= wanted % bytesPerFrame
            if !wanted do
                break

            let source = try .readPayload(byteOffset, wanted)
            if source.count != wanted do
                fail InvalidFormatError{"sound payload is truncated"}
            decoded.resize(source.count / bytesPerSample)
            let progress = try itf.decode(decoded.buffer!, decoded.count * #sizeof(s16), source.buffer!, source.count)
            if progress.bytesRead != source.count or progress.bytesWritten != decoded.count * #sizeof(s16) do
                fail InvalidFormatError{"sound payload decoded to an unexpected size"}
            if !consumer(decoded.toSlice()) do
                return
            byteOffset += source.count
        }
    }
}
