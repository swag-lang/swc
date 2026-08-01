using Core, Core.Errors

impl Voice
{
    mtd readBuffer()->{ buffer: #null [*] void, size: u64 } fail
    {
        let file = notnull .file

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
            let dataBuffer = notnull file.data.buffer
            return {dataBuffer + orgSeek, readSize}
        }

        // Otherwise decode into a temporary buffer.
        if !.decodedBuffers[.decodedBufferIdx].buffer do
            .decodedBuffers[.decodedBufferIdx].resize(DecodedBufferSize)

        let destBuffer = notnull .decodedBuffers[.decodedBufferIdx].buffer
        let destSize   = .decodeData(destBuffer, DecodedBufferSize)

        .decodedBufferIdx = (.decodedBufferIdx + 1) % NumDecodedBuffers
        return {destBuffer, destSize}
    }

    mtd closeBuffer()
    {
        closeData(me)
        .destroyCodec()
    }

    mtd createCodec() fail
    {
        let file = notnull .file
        let desc = findCodec(.requestedEncoding, file.encoding)
        if !desc do
            fail UnsupportedFormatError{"unsupported encoding"}
        let decoderData = notnull Memory.new(desc.type)
        let decoder     = cast(*Codec) decoderData
        decoder.sourceEncoding      = file.encoding
        decoder.destinationEncoding = .requestedEncoding
        decoder.type                = desc.type
        .codec                      = @mkinterface(decoder, desc.type, ICodec)
    }

    mtd destroyCodec()
    {
        if !.codec do
            return
        let decoder = cast(*Codec) (notnull @dataof(.codec))
        if decoder.type.opDrop do
            decoder.type.opDrop(decoder)
        Memory.free(decoder, cast(u64) decoder.type.sizeof)
        .codec = null
    }

    mtd decodeData(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file = notnull .file

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
            let streamBuffer = notnull .streamBuffer.buffer
            let codec        = notnull .codec
            .streamBuffer.count = .readData(streamBuffer, StreamBufferSize)
            .streamCurSeek      = readStart + codec.initialize(streamBuffer, .streamBuffer.count)
        }

        let readStart    = .streamCurSeek
        let streamBuffer = notnull .streamBuffer.buffer
        let codec        = notnull .codec
        .streamBuffer.count = .readData(streamBuffer, StreamBufferSize)
        let used = codec.decode(destBuffer, length, streamBuffer, .streamBuffer.count)
        .streamCurSeek = readStart + used.bytesRead
        return used.bytesWritten
    }

    mtd readData(destBuffer: [*] void, length: u64)->u64 fail
    {
        let file = notnull .file

        // End of the audio payload.
        if .streamCurSeek >= file.dataSize do
            return 0

        var wantedLength = length

        // First take from the prefetched buffer if there's something there, instead of reading
        // from the file.
        if .streamCurSeek < file.data.count
        {
            let remain     = Math.min(file.data.count - .streamCurSeek, length)
            let dataBuffer = notnull file.data.buffer
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

    mtd rewindData() fail
    {
        .streamCurSeek = 0
        .destroyCodec()
        if .stream.isOpen()
        {
            let file = notnull .file
            .stream.seek(.Begin, file.dataOffset)
        }
    }

    mtd closeData()
    {
        .streamCurSeek = 0
        if .stream.isOpen() do
            .stream.close()
    }
}
