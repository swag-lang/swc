//! Format: Sequential sound-file decoding.
//! Supported: PCM16 decoding in bounded input windows and sample-frame ranges, with direct PCM/AAC positioning.
//! Not supported: Channel remixing, sample-rate conversion, and retaining callback slices.
//! Role: This file owns device-independent decoding for analysis and export consumers.
//
#global public

using Core, Core.Errors

private const SoundDecodeReadSize = 256 * 1024'u64

// Receives one borrowed chunk of interleaved PCM16 samples.
//
// The slice remains valid only for the duration of the call. PCM sources are read in complete
// sample frames with a 256 KiB input window, enlarged when one frame is larger. Packet codecs
// deliver one decoded packet per call. Return `true` to continue or `false` to stop successfully.
alias SoundPcm16Consumer = func||(const [..] s16)->bool

impl SoundFile
{
    // Decodes this sound sequentially to interleaved PCM16 chunks.
    //
    // Compressed packets are decoded in playback order with codec priming and padding omitted.
    // The delivered frame count matches [[Audio.SoundFile.sampleFrameCount]]. PCM sources are converted
    // without requiring an audio engine; their input reads target 256 KiB and contain whole frames,
    // except that a frame larger than the window is read in full. Packet-codec callback sizes follow
    // the decoded packet size. `consumer` borrows each chunk only until it returns; returning `false`
    // cancels the remaining work without failure.
    mtd const decodePcm16(consumer: SoundPcm16Consumer)->void fail
        => try .decodePcm16(0, .frameCount, consumer)

    // Decodes a selected audible sample-frame range to interleaved PCM16 chunks.
    //
    // `firstFrame` and `frameCount` exclude codec priming and padding and must fit
    // [[Audio.SoundFile.sampleFrameCount]]. An empty range makes no callback. PCM seeks directly;
    // indexed AAC starts one transform-preroll packet before the selected packet. Other packet
    // codecs decode their preceding history for correctness. No audio engine is needed.
    //
    // ```swag
    // try sound.decodePcm16(48_000, 96_000, func(part: const [..] s16)->bool
    // {
    //     Core.Console.println(part.count)
    //     return true
    // })
    // ```
    mtd const decodePcm16(firstFrame, frameCount: u64, consumer: SoundPcm16Consumer) fail
    {
        if not .availableFields.has(.Data) or not .channelCount do
            fail BadParameterError{"sound file has no audio data"}
        if firstFrame > .frameCount or frameCount > .frameCount - firstFrame do
            fail BadParameterError{"sound decode range is outside its audible sample frames"}
        if not frameCount do
            return

        if .usesPacketCodec()
        {
            try .decodePacketPcm16(firstFrame, frameCount, consumer)
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
        codec.configure(.encoding, .Pcm16, #typeof(CodecPcmToPcm16), unwrap Swag.getContext().allocator)
        let decoder: ICodec = &codec
        var empty:   u8
        discard try decoder.initialize(&empty, 0)

        let bytesPerFrame = bytesPerSample * .channelCount
        var byteOffset    = firstFrame * bytesPerFrame
        let byteEnd       = byteOffset + frameCount * bytesPerFrame

        // A contiguous PCM payload can reuse one read window for the whole range.
        let contiguous = .packets.isEmpty()
        var source: ByteSource
        if contiguous
        {
            if .isDataPreloaded()
            {
                source = ByteSource.openMemory(.data.toSlice())
                try source.seek(byteOffset)
            }
            else
            {
                source = try ByteSource.openFile(.path.toString(), .ReadWrite)
                try source.seek(.dataOffset + byteOffset)
            }
        }

        var decoded: Array's16
        while byteOffset < byteEnd
        {
            // Keep reads bounded, except when one complete interleaved frame is larger than
            // the window. A non-empty range always has at least one full frame remaining.
            var wantedBytes = Math.min(Math.max(SoundDecodeReadSize, bytesPerFrame), byteEnd - byteOffset)
            wantedBytes -= wantedBytes % bytesPerFrame
            if not wantedBytes do
                break

            var payload: Array'u8
            var input:   const [..] u8
            if contiguous
            {
                if byteOffset >= .dataSize or wantedBytes > .dataSize - byteOffset do
                    fail InvalidFormatError{"sound payload is truncated"}
                let window = try source.peek(wantedBytes)
                input = window[until wantedBytes]
            }
            else
            {
                payload = try .readPayload(byteOffset, wantedBytes)
                input   = payload.toSlice()
                if input.count != wantedBytes do
                    fail InvalidFormatError{"sound payload is truncated"}
            }

            decoded.resize(input.count / bytesPerSample)
            let outputBytes = decoded.count * #sizeof(s16)
            let progress    = try decoder.decode(decoded.storage(), outputBytes, input.buffer, input.count)
            if progress.bytesRead != input.count or progress.bytesWritten != outputBytes do
                fail InvalidFormatError{"sound payload decoded to an unexpected size"}
            if not consumer(decoded.toSlice()) do
                return
            if contiguous do
                try source.skip(wantedBytes)
            byteOffset += wantedBytes
        }
    }
}

private const SoundDecodeBatchBytes = 2 * 1024 * 1024'u64

private struct Pcm16Range
{
    skipFrames: u64
    framesLeft: u64
}

private impl Pcm16Range
{
    #[Swag.Inline]
    mtd publish(samples: const [..] s16, channels: u32, consumer: SoundPcm16Consumer)->bool
    {
        let packetFrames = samples.count / channels
        let skipped      = Math.min(.skipFrames, packetFrames)
        .skipFrames -= skipped
        let delivered = Math.min(.framesLeft, packetFrames - skipped)
        if not delivered do
            return true

        .framesLeft -= delivered
        let accepted = consumer(samples[skipped * channels until (skipped + delivered) * channels])
        return accepted and .framesLeft != 0
    }
}

private alias AacPacketBytes = const [..] u8
private const AacPcm16PacketFrames    = 1024'u64
private const SoundAacMinBatchPackets = 32'u64

private struct FlacDecodeJob
{
    nextPacket: u64
    endPacket:  u64
    error:      Swag.Error
}

private func readPcm16Packet(codec: IPacketCodec,
                             source: *ByteSource,
                             scratch: *Array'u8,
                             packet: SoundPacket,
                             destination: [*] u8,
                             destinationBytes: u64) fail
{
    // A packet without payload is a gap in the stream, delivered as silence.
    if not packet.byteSize
    {
        Memory.clear(destination, destinationBytes)
        return
    }

    try source.seek(packet.sourceOffset)
    var payload: const [..] u8
    if packet.byteSize <= ByteSource.WindowSize
    {
        let window = try source.peek(packet.byteSize)
        payload = window[until packet.byteSize]
    }
    else
    {
        if scratch.count != packet.byteSize do
            scratch.resize(packet.byteSize)
        try source.readExact(scratch.toSlice())
        payload = scratch.toSlice()
    }

    let produced = try codec.decodePacket(destination, destinationBytes, payload)
    if produced != destinationBytes do
        fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}
}

private impl SoundFile
{
    mtd const decodePacketPcm16(firstFrame, frameCount: u64, consumer: SoundPcm16Consumer) fail
    {
        let descriptor = findPacketCodec(.encoding)
        if not descriptor do
            fail UnsupportedFormatError{"unsupported packetized encoding"}

        if descriptor.type == #typeof(Mp3.Codec) and
           not Swag.jit() and
           (try Mp3.decodeParallel(me, firstFrame, frameCount, consumer)) do
            return

        // The registered FLAC codec has no state that carries over between native frames
        // or completed Ogg page runs. An alternate registered codec keeps the serial path.
        if descriptor.type == #typeof(Flac.Codec) and
           frameCount >= SoundDecodeReadSize / (.channelCount * #sizeof(s16)) and
           not Swag.jit()
        {
            let workers = Swag.workerCount()
            if workers > 1
            {
                try .decodeFlacPcm16(firstFrame, frameCount, workers, consumer)
                return
            }
        }

        let allocator   = unwrap Swag.getContext().allocator
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
        var source        = try ByteSource.openFile(.path.toString(), .ReadWrite)
        var packetBytes:  Array'u8
        var decodedBytes: Array'u8
        var firstPacket   = 0'u64
        let decodedTarget = .leadingTrim + firstFrame
        if .encoding == .AacLc
        {
            let containing = .packetAtDecodedFrame(decodedTarget)
            firstPacket = containing ? containing - 1 : 0
        }

        var range         = Pcm16Range{decodedTarget - .packetStarts[firstPacket], frameCount}
        let packetDecoder = unwrap packetCodec
        var aacLanes      = 0'u64
        var aacEnd        = 0'u64
        var batchSamples: Array's16
        if .encoding == .AacLc and
           frameCount >= SoundAacMinBatchPackets * AacPcm16PacketFrames and
           not Swag.jit() and
           Aac.canDecodePacketBatch(packetDecoder)
        {
            let workers = Swag.workerCount()
            if workers > 1
            {
                aacLanes = Math.min(Aac.MaxPacketBatchLanes, cast(u64, workers) + 1)
                aacEnd   = .packetAtDecodedFrame(decodedTarget + frameCount - 1) + 1
            }
        }

        var index = firstPacket
        while index < .packets.count
        {
            if aacLanes and index != firstPacket and index < aacEnd
            {
                var deferred: Swag.Error
                let count = catch .prepareAacPcm16Batch(packetDecoder, &source, index, aacEnd, aacLanes, &batchSamples) as deferred orelse 0
                if not deferred.isEmpty()
                {
                    // Preparation and synthesis leave the decoder unchanged on failure.
                    // Revisit the same packets normally so callbacks can cancel first.
                    aacLanes = 0
                }
                elif count
                {
                    let samplesPerPacket = AacPcm16PacketFrames * .channelCount
                    let samples = batchSamples.storage()
                    for packetIndex in count
                    {
                        let offset = packetIndex * samplesPerPacket
                        if not range.publish(samples[offset until offset + samplesPerPacket], .channelCount, consumer) do
                            return
                    }

                    index += count
                    continue
                }
            }

            let packet            = .packets[index]
            let sampleCount       = cast(u64, packet.sampleFrameCount) * .channelCount
            let decodedBytesCount = sampleCount * #sizeof(s16)
            if decodedBytes.count != decodedBytesCount do
                decodedBytes.resize(decodedBytesCount)

            try readPcm16Packet(packetDecoder, &source, &packetBytes, packet, decodedBytes.storage(), decodedBytesCount)
            let samples = cast(const [*] s16, decodedBytes.storage())
            if not range.publish(samples[until sampleCount], .channelCount, consumer) do
                return
            index += 1
        }
    }

    #[Swag.NoInline]
    mtd const prepareAacPcm16Batch(decoder: IPacketCodec,
                                   source: *ByteSource,
                                   begin,
                                   end,
                                   lanes: u64,
                                   samples: *Array's16)->u64 fail
    {
        let start            = .packets[begin].sourceOffset
        let samplesPerPacket = AacPcm16PacketFrames * .channelCount
        let pcmLimit         = SoundDecodeBatchBytes / (samplesPerPacket * #sizeof(s16))
        let maxCount         = Math.min(end - begin, Aac.MaxPacketBatchSize, pcmLimit)
        var count            = 0'u64
        var length           = 0'u64
        while count < maxCount
        {
            let entry = .packets[begin + count]
            if not entry.byteSize or
               entry.sampleFrameCount != AacPcm16PacketFrames or
               entry.sourceOffset < start do
                break
            let endByte = entry.sourceOffset - start + entry.byteSize
            if endByte > SoundDecodeBatchBytes do
                break
            length = Math.max(length, endByte)
            count  += 1
        }

        if count < SoundAacMinBatchPackets do
            return 0

        // Borrow one bounded compressed span. Each access unit may leave gaps between
        // payloads, but all slices remain valid until the batch joins.
        try source.seek(start)
        let bytes = try source.peek(length)
        var packetSlices: Array'AacPacketBytes
        packetSlices.reserve(count)
        let packets = packetSlices.storage()
        for index in count
        {
            let entry  = .packets[begin + index]
            let offset = entry.sourceOffset - start
            packets[index] = bytes[offset until offset + entry.byteSize]
        }

        let sampleCount = count * samplesPerPacket
        samples.reserve(sampleCount)
        let output = samples.storage()
        try Aac.decodePacketBatch(decoder, packets[until count], output[until sampleCount], lanes)
        return count
    }

    mtd const decodeFlacPcm16(firstFrame, frameCount: u64, workers: u32, consumer: SoundPcm16Consumer) fail
    {
        let decodedTarget = .leadingTrim + firstFrame
        let packetEnd     = .packetAtDecodedFrame(decodedTarget + frameCount - 1) + 1
        let bytesPerFrame = .channelCount * #sizeof(s16)
        var range         = Pcm16Range{decodedTarget, frameCount}
        var pcm:  Array's16
        var jobs: Array'FlacDecodeJob

        var batchFirst = 0'u64
        while batchFirst < packetEnd
        {
            // Bound both the output and the amount of compressed data read ahead. A packet
            // larger than the budget remains one serial job with the usual packet allocation.
            // Publish the first packet before starting read-ahead so an early cancellation
            // needs only one decode.
            let batchLimit      = batchFirst == 0 ? 1 : packetEnd
            var batchEnd        = batchFirst
            var batchFrames     = 0'u64
            var compressedBytes = 0'u64
            while batchEnd < batchLimit
            {
                let packet = .packets[batchEnd]
                if batchEnd != batchFirst and
                   ((batchFrames + packet.sampleFrameCount) * bytesPerFrame > SoundDecodeBatchBytes or
                    compressedBytes + packet.byteSize > SoundDecodeBatchBytes) do
                    break
                batchFrames     += packet.sampleFrameCount
                compressedBytes += packet.byteSize
                batchEnd        += 1
            }

            let batchFrame = .packetStarts[batchFirst]
            let jobCount   = Math.min(cast(u64, workers), batchEnd - batchFirst, Math.max(1'u64, batchFrames * bytesPerFrame / SoundDecodeReadSize))
            jobs.clear()
            jobs.resize(jobCount)
            var first = batchFirst
            for index in jobCount
            {
                var end = batchEnd
                if index + 1 < jobCount
                {
                    let splitFrame = batchFrame + batchFrames * (index + 1) / jobCount
                    end = Math.clamp(.packetAtDecodedFrame(splitFrame), first + 1, batchEnd - (jobCount - index - 1))
                }

                jobs[index].nextPacket = first
                jobs[index].endPacket  = end
                first = end
            }

            pcm.resize(Math.max(1'u64, batchFrames * .channelCount))
            let dst   = pcm.storage()
            let work  = jobs.storage()
            let sound = me
            parallel for |sound, work, dst, batchFrame| index in jobCount
            {
                let job = work + index
                catch sound.decodeFlacJob(job, dst, batchFrame) do
                    job.error.capture(Swag.err)
            }

            // Publish on the caller in packet order. A cancelled range never exposes an
            // error from read-ahead that the sequential consumer would not have reached.
            var packetIndex = batchFirst
            for &job in jobs
            {
                while packetIndex < job.nextPacket
                {
                    let packet = .packets[packetIndex]
                    let offset = (.packetStarts[packetIndex] - batchFrame) * .channelCount
                    let length = cast(u64, packet.sampleFrameCount) * .channelCount
                    if not range.publish(dst[offset until offset + length], .channelCount, consumer) do
                        return
                    packetIndex += 1
                }

                try job.error.raise()
            }

            batchFirst = batchEnd
        }
    }

    mtd const decodeFlacJob(job: *FlacDecodeJob, destination: [*] s16, batchFrame: u64) fail
    {
        var codec:       Flac.Codec
        let packetCodec: IPacketCodec = &codec
        try packetCodec.initialize(.decoderConfig.toSlice(), .sampleRate, .channelCount)

        var source = try ByteSource.openFile(.path.toString(), .ReadWrite)
        var scratch: Array'u8
        while job.nextPacket < job.endPacket
        {
            let packet = .packets[job.nextPacket]
            let offset = (.packetStarts[job.nextPacket] - batchFrame) * .channelCount
            let count  = cast(u64, packet.sampleFrameCount) * .channelCount
            try readPcm16Packet(packetCodec, &source, &scratch, packet, cast([*] u8, destination + offset), count * #sizeof(s16))
            job.nextPacket += 1
        }
    }
}
