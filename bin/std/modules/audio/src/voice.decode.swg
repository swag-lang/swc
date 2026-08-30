using Core, Core.Errors

impl Voice
{
    mtd decodedBytesPerFrame()->u64
    {
        var bytesPerSample = 2'u64
        switch .requestedEncoding
        {
        case .Pcm8:            bytesPerSample = 1
        case .Pcm16:           bytesPerSample = 2
        case .Pcm24:           bytesPerSample = 3
        case .Pcm32, .Float32: bytesPerSample = 4
        }

        return bytesPerSample * .file!.channelCount
    }

    // Returns the capacity of one decoded buffer: the streaming size, or the largest packet of the
    // source when one decodes to more than that, since a packet is never split across buffers.
    mtd decodedBufferCapacity()->u64
    {
        if .decodedCapacity do
            return .decodedCapacity
        let file    = .file!
        var largest = 0'u64
        if file.usesPacketCodec()
        {
            for packet in file.packets do
                largest = Math.max(largest, cast(u64) packet.sampleFrameCount)
        }

        .decodedCapacity = Math.max(DecodedBufferSize, largest * .decodedBytesPerFrame())
        return .decodedCapacity
    }

    // Keeps one submitted buffer near 100 ms. With the backend maintaining two queued buffers,
    // this is enough scheduling margin without letting decoded audio run far ahead of transport
    // commands or the picture clock.
    mtd decodedFillSize()->u64
    {
        let file   = .file!
        var target = Math.max(cast(u64) file.sampleRate / 10 * .decodedBytesPerFrame(), 1)
        if file.usesPacketCodec()
        {
            let firstPacket = file.packets[Math.min(.streamPacketIdx, file.packets.count - 1)]
            target = Math.max(target, cast(u64) firstPacket.sampleFrameCount * .decodedBytesPerFrame())
        }

        return Math.min(target, .decodedBufferCapacity())
    }

    mtd readBuffer()->{ buffer: #null [*] void, size: u64 } fail
    {
        let file = .file!

        if file.usesPacketCodec()
        {
            if .streamPacketIdx >= file.packets.count
            {
                if !.playFlags.has(.Loop) do
                    return {null, 0}
                .rewindData()
            }

            if .decodedBuffers[.decodedBufferIdx].count < .decodedBufferCapacity() do
                .decodedBuffers[.decodedBufferIdx].resize(.decodedBufferCapacity())
            let destBuffer = .decodedBuffers[.decodedBufferIdx].buffer!
            let destSize   = .decodePacketData(destBuffer, .decodedFillSize())
            .decodedBufferIdx = (.decodedBufferIdx + 1) % NumDecodedBuffers
            return {destBuffer, destSize}
        }

        // At the end of the source, return no buffer unless looping is enabled. A loop rewinds
        // the source before filling the next buffer.
        if .streamCurSeek >= file.dataSize
        {
            if !.playFlags.has(.Loop) do
                return {null, 0}
            .rewindData()
        }

        // If the file is prefetched and in a driver requested format, just submit the
        // prefetched data
        if .streamCurSeek < file.data.count and file.encoding == .requestedEncoding
        {
            let orgSeek  = .streamCurSeek
            let readSize = (file.data.count - .streamCurSeek)
            .streamCurSeek = file.data.count
            let dataBuffer = file.data.buffer!
            return {dataBuffer + orgSeek, readSize}
        }

        // Otherwise decode into a temporary buffer.
        if !.decodedBuffers[.decodedBufferIdx].buffer do
            .decodedBuffers[.decodedBufferIdx].resize(DecodedBufferSize)

        let destBuffer = .decodedBuffers[.decodedBufferIdx].buffer!
        let destSize   = .decodeData(destBuffer, .decodedFillSize())

        .decodedBufferIdx = (.decodedBufferIdx + 1) % NumDecodedBuffers
        return {destBuffer, destSize}
    }

    mtd closeBuffer()
    {
        closeData(me)
        .destroyCodec()
        .destroyPacketCodec()
    }

    mtd createCodec() fail
    {
        let file = .file!
        let desc = findCodec(.requestedEncoding, file.encoding)
        if !desc do
            fail UnsupportedFormatError{"unsupported encoding"}
        let allocator   = .handle ? .allocationAllocator : Swag.getContext().allocator!
        let decoderData = Memory.new(desc.type, allocator)!
        let decoder     = cast(*Codec) decoderData
        decoder.configure(file.encoding, .requestedEncoding, desc.type, allocator)
        .codec = Swag.makeInterface(decoder, desc.type, ICodec)
    }

    mtd destroyCodec()
    {
        if !.codec do
            return
        let decoder   = cast(*Codec) (.codec).buffer!
        let allocator = decoder.allocationAllocator
        if decoder.type.opDrop do
            decoder.type.opDrop(decoder)
        Memory.free(decoder, cast(u64) decoder.type.sizeof, allocator)
        .codec = null
    }

    mtd createPacketCodec() fail
    {
        let file = .file!
        let desc = findPacketCodec(file.encoding)
        if !desc do
            fail UnsupportedFormatError{"unsupported packetized encoding"}
        let allocator   = .handle ? .allocationAllocator : Swag.getContext().allocator!
        let decoderData = Memory.new(desc.type, allocator)!
        let decoder     = cast(*Codec) decoderData
        decoder.configure(file.encoding, .Pcm16, desc.type, allocator)
        .packetCodec = Swag.makeInterface(decoder, desc.type, IPacketCodec)
        defer #fail .destroyPacketCodec()
        .packetCodec!.initialize(file.decoderConfig.toSlice(), file.sampleRate, file.channelCount)
    }

    mtd destroyPacketCodec()
    {
        if !.packetCodec do
            return
        let decoder   = cast(*Codec) (.packetCodec).buffer!
        let allocator = decoder.allocationAllocator
        if decoder.type.opDrop do
            decoder.type.opDrop(decoder)
        Memory.free(decoder, cast(u64) decoder.type.sizeof, allocator)
        .packetCodec = null
    }

    // Decodes whole access units until the backend buffer is full. Payload reads use the
    // container offsets directly, so sparse MP4 chunks and multi-gigabyte media never become
    // one artificial contiguous allocation.
    mtd decodePacketData(destination: [*] void, destinationSize: u64)->u64 fail
    {
        let file = .file!
        if !.packetCodec do
            .createPacketCodec()

        var written = 0'u64
        while .streamPacketIdx < file.packets.count
        {
            let packet      = file.packets[.streamPacketIdx]
            let decodedSize = cast(u64) packet.sampleFrameCount * file.channelCount * 2
            if decodedSize > destinationSize - written do
                break

            if .packetBuffer.count != packet.byteSize do
                .packetBuffer.resize(packet.byteSize)
            if !.stream.isOpen() do
                .stream = File.open(file.path, File.FileMode.Open, File.FileAccess.Read, File.FileShare.Read)
            .stream.seek(.Begin, packet.sourceOffset)
            if .stream.read(.packetBuffer.toSlice()) != packet.byteSize do
                fail InvalidFormatError{"compressed sound packet is truncated"}

            if .seekDiscardFrames
            {
                if .packetScratch.count != decodedSize do
                    .packetScratch.resize(decodedSize)

                // A codec restarted by a seek may lack the history the first packets of the run need
                // and produce fewer frames than the index states. Those frames are the leading ones,
                // and the seek discards that region anyway, so the shortfall counts as discarded.
                let produced = .packetCodec!.decodePacket(.packetScratch.buffer!, decodedSize, .packetBuffer.toSlice())
                if produced > decodedSize do
                    fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}
                let missing       = decodedSize - produced
                let discardFrames = Math.min(.seekDiscardFrames, packet.sampleFrameCount)
                let discardBytes  = cast(u64) discardFrames * file.channelCount * 2
                if discardBytes < missing do
                    fail InvalidFormatError{"compressed sound packet decoded fewer frames than its index states"}
                let kept = produced - (discardBytes - missing)
                if kept
                {
                    Memory.copy(cast([*] u8) destination + written, .packetScratch.buffer! + (discardBytes - missing), kept)
                    written += kept
                }

                .seekDiscardFrames -= discardFrames
            }
            else
            {
                let produced = .packetCodec!.decodePacket(cast([*] u8) destination + written, decodedSize, .packetBuffer.toSlice())
                if produced != decodedSize do
                    fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}
                written += produced
            }

            .streamPacketIdx += 1
            .streamCurSeek   += packet.byteSize
        }

        return written
    }

    mtd decodeData(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file = .file!

        // If the file contains data in the encoding requested by the driver, no need
        // to decode, we can directly read in the destination buffer
        if file.encoding == .requestedEncoding
        {
            let readStart = .streamCurSeek
            let bytesRead = .readData(destBuffer, length)
            .streamCurSeek = readStart + bytesRead
            return bytesRead
        }

        // Otherwise we need a codec
        if !.codec
        {
            expect .createCodec()
            .streamBuffer.reserve(StreamBufferSize)
            let readStart    = .streamCurSeek
            let streamBuffer = .streamBuffer.buffer!
            let codec        = .codec!
            .streamBuffer.count = .readData(streamBuffer, StreamBufferSize)
            .streamCurSeek      = readStart + codec.initialize(streamBuffer, .streamBuffer.count)
        }

        let readStart    = .streamCurSeek
        let streamBuffer = .streamBuffer.buffer!
        let codec        = .codec!
        .streamBuffer.count = .readData(streamBuffer, StreamBufferSize)
        let used = codec.decode(destBuffer, length, streamBuffer, .streamBuffer.count)
        .streamCurSeek = readStart + used.bytesRead
        return used.bytesWritten
    }

    mtd readData(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file = .file!

        // End of the audio payload.
        if .streamCurSeek >= file.dataSize do
            return 0

        var wantedLength = length

        if file.packets.count do
            return .readPacketBytes(destBuffer, wantedLength)

        // First take from the prefetched buffer if there's something there, instead of reading
        // from the file.
        if .streamCurSeek < file.data.count
        {
            let remain     = Math.min(file.data.count - .streamCurSeek, length)
            let dataBuffer = file.data.buffer!
            Memory.copy(destBuffer, dataBuffer + .streamCurSeek, remain)
            .streamCurSeek += remain
            if .streamCurSeek >= file.dataSize do
                return remain
            wantedLength -= remain
            if !wantedLength do
                return remain
        }

        // Open file for streaming
        if !.stream.isOpen() do
            .stream = File.open(file.path, File.FileMode.Open, File.FileAccess.Read, File.FileShare.Read)

        // Read from file
        .stream.seek(.Begin, file.dataOffset + .streamCurSeek)
        wantedLength = Math.min(wantedLength, file.dataSize - .streamCurSeek)
        return .stream.read(destBuffer, wantedLength)
    }

    // Reads a logical byte range from PCM chunks that are scattered through a container.
    mtd readPacketBytes(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file          = .file!
        let bytesPerFrame = cast(u64) file.channelCount * cast(u64) (file.bitsPerSample / 8)
        var written       = 0'u64
        var logicalOffset = .streamCurSeek
        var low           = 0'u64
        var high          = file.packetStarts.count

        let targetFrame = logicalOffset / bytesPerFrame
        while low + 1 < high
        {
            let middle = low + (high - low) / 2
            if file.packetStarts[middle] <= targetFrame do
                low = middle
            else do
                high = middle
        }

        var packetIndex = low

        if !.stream.isOpen() do
            .stream = File.open(file.path, File.FileMode.Open, File.FileAccess.Read, File.FileShare.Read)

        while written < length and packetIndex < file.packets.count
        {
            let packet      = file.packets[packetIndex]
            let packetStart = file.packetStarts[packetIndex] * bytesPerFrame
            let packetEnd   = packetStart + packet.byteSize
            if logicalOffset >= packetEnd
            {
                packetIndex += 1
                continue
            }

            let packetSkip = logicalOffset - packetStart
            let readSize   = Math.min(cast(u64) packet.byteSize - packetSkip, length - written)
            .stream.seek(.Begin, packet.sourceOffset + packetSkip)
            if .stream.read(cast([*] u8) destBuffer + written, readSize) != readSize do
                fail InvalidFormatError{"PCM source chunk is truncated"}
            written       += readSize
            logicalOffset += readSize
            if logicalOffset == packetEnd do
                packetIndex += 1
        }

        return written
    }

    mtd rewindData() fail
    {
        .streamCurSeek     = 0
        .streamPacketIdx   = 0
        .seekDiscardFrames = .file ? cast(u32) .file!.leadingTrim : 0
        .destroyCodec()
        if .packetCodec do
            .packetCodec!.reset()
        if .stream.isOpen()
        {
            let file = .file!
            .stream.seek(.Begin, file.dataOffset)
        }
    }

    mtd closeData()
    {
        .streamCurSeek     = 0
        .streamPacketIdx   = 0
        .seekDiscardFrames = 0
        if .stream.isOpen() do
            .stream.close()
    }
}
