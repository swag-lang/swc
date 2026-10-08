using Core, Core.Errors

impl Voice
{
    mtd decodedBytesPerFrame()->u64
    {
        var bytesPerSample = 2'u64
        switch .requestedEncoding
        {
        case .Pcm8:  bytesPerSample = 1
        case .Pcm16: bytesPerSample = 2
        case .Pcm24: bytesPerSample = 3
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
        let file = .file!
        var largestPacketFrames = 0'u64
        if file.usesPacketCodec()
        {
            for packet in file.packets do
                largestPacketFrames = Math.max(largestPacketFrames, cast(u64, packet.sampleFrameCount))
        }

        .decodedCapacity = Math.max(DecodedBufferSize, largestPacketFrames * .decodedBytesPerFrame())
        return .decodedCapacity
    }

    // Keeps one submitted buffer near 100 ms. With the backend maintaining two queued buffers,
    // this is enough scheduling margin without letting decoded audio run far ahead of transport
    // commands or the picture clock.
    mtd decodedFillSize()->u64
    {
        let file        = .file!
        var targetBytes = Math.max(cast(u64, file.sampleRate) / 10 * .decodedBytesPerFrame(), 1)
        if file.usesPacketCodec()
        {
            let firstPacket = file.packets[Math.min(.streamPacketIdx, file.packets.count - 1)]
            targetBytes = Math.max(targetBytes, cast(u64, firstPacket.sampleFrameCount) * .decodedBytesPerFrame())
        }

        return Math.min(targetBytes, .decodedBufferCapacity())
    }

    mtd readBuffer()->{ buffer: [*] void?, size: u64 } fail
    {
        let file = .file!

        if file.usesPacketCodec()
        {
            if .streamPacketIdx >= file.packets.count
            {
                if not .playFlags.has(.Loop) do
                    return {null, 0}
                .rewindData()
            }

            if .decodedBuffers[.decodedBufferIdx].count < .decodedBufferCapacity() do
                .decodedBuffers[.decodedBufferIdx].resize(.decodedBufferCapacity())
            let destBuffer   = .decodedBuffers[.decodedBufferIdx].storage()
            let decodedBytes = try .decodePacketData(destBuffer, .decodedFillSize())
            .decodedBufferIdx = (.decodedBufferIdx + 1) % NumDecodedBuffers
            return {destBuffer, decodedBytes}
        }

        // At the end of the source, return no buffer unless looping is enabled. A loop rewinds
        // the source before filling the next buffer.
        if .streamCurSeek >= file.dataSize
        {
            if not .playFlags.has(.Loop) do
                return {null, 0}
            .rewindData()
        }

        // If the file is prefetched and in a driver requested format, just submit the
        // prefetched data
        if .streamCurSeek < file.data.count and file.encoding == .requestedEncoding
        {
            let prefetchedOffset = .streamCurSeek
            let readBytes        = (file.data.count - .streamCurSeek)
            .streamCurSeek = file.data.count
            let dataBuffer = file.data.storage()
            return {dataBuffer + prefetchedOffset, readBytes}
        }

        // Otherwise decode into a temporary buffer.
        if not .decodedBuffers[.decodedBufferIdx].buffer do
            .decodedBuffers[.decodedBufferIdx].resize(DecodedBufferSize)

        let destBuffer   = .decodedBuffers[.decodedBufferIdx].storage()
        let decodedBytes = try .decodeData(destBuffer, .decodedFillSize())

        .decodedBufferIdx = (.decodedBufferIdx + 1) % NumDecodedBuffers
        return {destBuffer, decodedBytes}
    }

    mtd closeBuffer()
    {
        closeData(me)
        .destroyCodec()
        .destroyPacketCodec()
    }

    mtd createCodec() fail
    {
        let file       = .file!
        let descriptor = findCodec(.requestedEncoding, file.encoding)
        if not descriptor do
            fail UnsupportedFormatError{"unsupported encoding"}
        let allocator   = .handle ? .allocationAllocator : Swag.getContext().allocator!
        let decoderData = Memory.new(descriptor.type, allocator)
        let decoder     = cast(*Codec, decoderData)
        decoder.configure(file.encoding, .requestedEncoding, descriptor.type, allocator)
        .codec = Swag.makeInterface(decoder, descriptor.type, ICodec)
    }

    mtd destroyCodec()
    {
        if not .codec do
            return
        let decoder   = cast(*Codec, (.codec).buffer)
        let allocator = decoder.allocationAllocator
        if decoder.type.opDrop do
            decoder.type.opDrop(decoder)
        Memory.free(decoder, cast(u64, decoder.type.sizeof), allocator)
        .codec = null
    }

    mtd createPacketCodec() fail
    {
        let file       = .file!
        let descriptor = findPacketCodec(file.encoding)
        if not descriptor do
            fail UnsupportedFormatError{"unsupported packetized encoding"}
        let allocator   = .handle ? .allocationAllocator : Swag.getContext().allocator!
        let decoderData = Memory.new(descriptor.type, allocator)
        let decoder     = cast(*Codec, decoderData)
        decoder.configure(file.encoding, .Pcm16, descriptor.type, allocator)
        .packetCodec = Swag.makeInterface(decoder, descriptor.type, IPacketCodec)
        defer #fail .destroyPacketCodec()
        try .packetCodec!.initialize(file.decoderConfig.toSlice(), file.sampleRate, file.channelCount)
    }

    mtd destroyPacketCodec()
    {
        if not .packetCodec do
            return
        let decoder   = cast(*Codec, (.packetCodec).buffer)
        let allocator = decoder.allocationAllocator
        if decoder.type.opDrop do
            decoder.type.opDrop(decoder)
        Memory.free(decoder, cast(u64, decoder.type.sizeof), allocator)
        .packetCodec = null
    }

    // Decodes whole access units until the backend buffer is full. Payload reads use the
    // container offsets directly, so sparse MP4 chunks and multi-gigabyte media never become
    // one artificial contiguous allocation.
    mtd decodePacketData(destination: [*] void, destinationSize: u64)->u64 fail
    {
        let file = .file!
        if not .packetCodec do
            try .createPacketCodec()

        var writtenBytes = 0'u64
        while .streamPacketIdx < file.packets.count
        {
            let packet = file.packets[.streamPacketIdx]
            let packetDecodedBytes = cast(u64, packet.sampleFrameCount) * file.channelCount * 2
            if packetDecodedBytes > destinationSize - writtenBytes do
                break

            if .packetBuffer.count != packet.byteSize do
                .packetBuffer.resize(packet.byteSize)
            if not .stream.isOpen() do
                .stream = try ByteSource.openFile(file.path)
            try .stream.seek(packet.sourceOffset)
            if try .stream.read(.packetBuffer.toSlice()) != packet.byteSize do
                fail InvalidFormatError{"compressed sound packet is truncated"}

            if .seekDiscardFrames
            {
                if .packetScratch.count != packetDecodedBytes do
                    .packetScratch.resize(packetDecodedBytes)

                // A codec restarted by a seek may lack the history the first packets of the run need
                // and produce fewer frames than the index states. Those frames are the leading ones,
                // and the seek discards that region anyway, so the shortfall counts as discarded.
                let producedBytes = try .packetCodec!.decodePacket(.packetScratch.storage(),
                                                                   packetDecodedBytes,
                                                                   .packetBuffer.toSlice())
                if producedBytes > packetDecodedBytes do
                    fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}
                let missingBytes  = packetDecodedBytes - producedBytes
                let discardFrames = Math.min(.seekDiscardFrames, packet.sampleFrameCount)
                let discardBytes  = cast(u64, discardFrames) * file.channelCount * 2
                if discardBytes < missingBytes do
                    fail InvalidFormatError{"compressed sound packet decoded fewer frames than its index states"}
                let availableDiscardBytes = discardBytes - missingBytes
                let keptBytes = producedBytes - availableDiscardBytes
                if keptBytes
                {
                    Memory.copy(cast([*] u8, destination) + writtenBytes,
                                .packetScratch.storage() + availableDiscardBytes,
                                keptBytes)
                    writtenBytes += keptBytes
                }

                .seekDiscardFrames -= discardFrames
            }
            else
            {
                let producedBytes = try .packetCodec!.decodePacket(cast([*] u8, destination) + writtenBytes,
                                                                   packetDecodedBytes,
                                                                   .packetBuffer.toSlice())
                if producedBytes != packetDecodedBytes do
                    fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}
                writtenBytes += producedBytes
            }

            .streamPacketIdx += 1
            .streamCurSeek   += packet.byteSize
        }

        return writtenBytes
    }

    mtd decodeData(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file = .file!

        // If the file contains data in the encoding requested by the driver, no need
        // to decode, we can directly read in the destination buffer
        if file.encoding == .requestedEncoding
        {
            let readStart = .streamCurSeek
            let bytesRead = try .readData(destBuffer, length)
            .streamCurSeek = readStart + bytesRead
            return bytesRead
        }

        // Otherwise we need a codec
        if not .codec
        {
            expect .createCodec()
            .streamBuffer.reserve(StreamBufferSize)
            let readStart    = .streamCurSeek
            let streamBuffer = .streamBuffer.storage()
            let codec        = .codec!
            .streamBuffer.count = try .readData(streamBuffer, StreamBufferSize)
            .streamCurSeek      = readStart + (try codec.initialize(streamBuffer, .streamBuffer.count))
        }

        let readStart    = .streamCurSeek
        let streamBuffer = .streamBuffer.storage()
        let codec        = .codec
        .streamBuffer.count = try .readData(streamBuffer, StreamBufferSize)
        let progress = try codec.decode(destBuffer, length, streamBuffer, .streamBuffer.count)
        .streamCurSeek = readStart + progress.bytesRead
        return progress.bytesWritten
    }

    mtd readData(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file = .file!

        // End of the audio payload.
        if .streamCurSeek >= file.dataSize do
            return 0

        var wantedBytes = length

        if not file.packets.isEmpty() do
            return try .readPacketBytes(destBuffer, wantedBytes)

        // First take from the prefetched buffer if there's something there, instead of reading
        // from the file.
        if .streamCurSeek < file.data.count
        {
            let prefetchedBytes = Math.min(file.data.count - .streamCurSeek, length)
            let dataBuffer      = file.data.storage()
            Memory.copy(destBuffer, dataBuffer + .streamCurSeek, prefetchedBytes)
            .streamCurSeek += prefetchedBytes
            if .streamCurSeek >= file.dataSize do
                return prefetchedBytes
            wantedBytes -= prefetchedBytes
            if not wantedBytes do
                return prefetchedBytes
        }

        // Open file for streaming
        if not .stream.isOpen() do
            .stream = try ByteSource.openFile(file.path)

        // Read from file. A payload the header declares past what the file holds ends where the
        // file does.
        let fileOffset = file.dataOffset + .streamCurSeek
        if fileOffset >= .stream.size() do
            return 0
        try .stream.seek(fileOffset)
        wantedBytes = Math.min(wantedBytes, file.dataSize - .streamCurSeek)
        return try .stream.read(Swag.makeSlice(cast([*] u8, destBuffer), wantedBytes))
    }

    // Reads a logical byte range from PCM chunks that are scattered through a container.
    mtd readPacketBytes(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file              = .file!
        let bytesPerFrame     = cast(u64, file.channelCount) * cast(u64, (file.bitsPerSample / 8))
        var writtenBytes      = 0'u64
        var logicalByteOffset = .streamCurSeek
        var low               = 0'u64
        var high              = file.packetStarts.count

        // Locate the packet containing the logical playback position.
        let targetFrame = logicalByteOffset / bytesPerFrame
        while low + 1 < high
        {
            let middle = low + (high - low) / 2
            if file.packetStarts[middle] <= targetFrame do
                low = middle
            else do
                high = middle
        }

        var packetIndex = low

        if not .stream.isOpen() do
            .stream = try ByteSource.openFile(file.path)

        while writtenBytes < length and packetIndex < file.packets.count
        {
            let packet          = file.packets[packetIndex]
            let packetStartByte = file.packetStarts[packetIndex] * bytesPerFrame
            let packetEndByte   = packetStartByte + packet.byteSize
            if logicalByteOffset >= packetEndByte
            {
                packetIndex += 1
                continue
            }

            let packetSkipBytes = logicalByteOffset - packetStartByte
            let readBytes       = Math.min(cast(u64, packet.byteSize) - packetSkipBytes, length - writtenBytes)
            try .stream.seek(packet.sourceOffset + packetSkipBytes)
            if try .stream.read(Swag.makeSlice(cast([*] u8, destBuffer) + writtenBytes, readBytes)) != readBytes do
                fail InvalidFormatError{"PCM source chunk is truncated"}
            writtenBytes      += readBytes
            logicalByteOffset += readBytes
            if logicalByteOffset == packetEndByte do
                packetIndex += 1
        }

        return writtenBytes
    }

    mtd rewindData()
    {
        .streamCurSeek     = 0
        .streamPacketIdx   = 0
        .seekDiscardFrames = .file ? cast(u32, .file.leadingTrim) : 0
        .destroyCodec()
        .packetCodec?.reset()
    }

    mtd closeData()
    {
        .streamCurSeek     = 0
        .streamPacketIdx   = 0
        .seekDiscardFrames = 0
        .stream.close()
    }
}
