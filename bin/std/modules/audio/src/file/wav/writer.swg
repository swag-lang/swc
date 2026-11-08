//! Format: RIFF/WAVE PCM16 streaming writer.
//! Supported: Mono and stereo interleaved signed 16-bit PCM with a playable flushed prefix.
//! Not supported: RF64, more than two channels, compressed samples, and files over the RIFF size limit.
//! Role: This file writes a sound-only recording without retaining its samples in memory.
//
#global namespace Wav
#global export

using Core, Core.Errors

// Writes a mono or stereo PCM16 WAVE file one group of sample frames at a time.
//
// A new file contains a valid empty WAVE header. Each `flush` updates both length fields and
// makes the complete prefix playable if recording stops unexpectedly. The writer buffers at most
// one [[Core.ByteSink.WindowSize]] window; the caller retains ownership of its input samples.
// Call `end` to finalize the file and report write errors. The classic RIFF container limits the
// data chunk to 4 GiB minus its header; this writer fails before crossing that limit.
#[Swag.NoCopy]
struct Writer
{
    private
    {
        sink:       ByteSink
        frameCount: u64
        sampleRate: u32
        channels:   u16
        isEnded:    bool
    }
}

impl Writer
{
    // Creates a PCM16 WAVE file, replacing any file at `fileName`.
    //
    // `channels` must be one or two and `sampleRate` positive. The header is flushed before
    // returning, so an interrupted recording with no samples remains a valid empty file.
    func create(fileName: string, channels: u16, sampleRate: u32)->Writer fail
    {
        if (channels != 1 and channels != 2) or
           not sampleRate or
           cast(u64, channels) * sampleRate * 2 > Swag.U32.Max do
            fail BadParameterError{"WAV writer needs mono or stereo PCM16 at a representable sample rate"}
        with var result: #returntype
        {
            .sink       = try ByteSink.createFile(fileName)
            .channels   = channels
            .sampleRate = sampleRate
        }

        try result.writeHeader()
        try result.sink.flush()
        return result
    }

    // Continues a stopped PCM16 WAVE file made by this writer.
    //
    // The last flushed header determines the complete sample prefix. Bytes beyond that prefix
    // are discarded before new samples are written. A malformed or truncated committed prefix
    // fails without changing the file. The file must remain unchanged during validation; an
    // I/O failure after truncation leaves the already playable prefix in place.
    func resume(fileName: string)->Writer fail
    {
        let originalSize = (try File.info(fileName)).size
        var source       = try ByteSource.openFile(fileName)
        var header: [44] u8
        try source.readExact(Swag.makeSlice(&header[0], header.count))
        if Memory.compare(&header[0], "RIFF".buffer, 4) != 0 or
           Memory.compare(&header[8], "WAVEfmt ".buffer, 8) != 0 or
           Memory.compare(&header[36], "data".buffer, 4) != 0 do
            fail InvalidFormatError{"WAV resume needs a classic PCM16 header"}

        try source.seek(4)
        let riffSize = try source.readLittleEndian'u32()
        try source.seek(16)
        let formatSize    = try source.readLittleEndian'u32()
        let formatTag     = try source.readLittleEndian'u16()
        let channels      = try source.readLittleEndian'u16()
        let sampleRate    = try source.readLittleEndian'u32()
        let byteRate      = try source.readLittleEndian'u32()
        let blockAlign    = try source.readLittleEndian'u16()
        let bitsPerSample = try source.readLittleEndian'u16()
        try source.seek(40)
        let dataSize      = try source.readLittleEndian'u32()
        if formatSize != 16 or
           formatTag != 1 or
           (channels != 1 and channels != 2) or
           not sampleRate or
           blockAlign != channels * 2 or
           bitsPerSample != 16 or
           cast(u64, channels) * sampleRate * 2 != byteRate or
           dataSize > Swag.U32.Max - 36 or
           riffSize != dataSize + 36 or
           dataSize % blockAlign or
           cast(u64, dataSize) + 44 > originalSize do
            fail InvalidFormatError{"WAV resume header or committed samples are invalid"}
        source.close()

        scope
        {
            var file = try File.open(fileName, .Open, .ReadWrite, .Zero)
            if try file.size() != originalSize do
                fail InvalidFormatError{"WAV file changed during resume"}
            try file.resize(cast(u64, dataSize) + 44)
            file.close()
        }

        var result: #returntype
        result.sink       = try ByteSink.openAppendFile(fileName)
        result.channels   = channels
        result.sampleRate = sampleRate
        result.frameCount = dataSize / blockAlign
        return result
    }

    // Returns the number of complete sample frames successfully submitted.
    mtd const sampleFrameCount()->u64 => .frameCount

    // Returns the accepted file byte count, including bytes still in the sink's write window.
    mtd const writtenByteCount()->u64 => .sink.position()

    // Appends interleaved signed 16-bit samples as complete sample frames.
    //
    // The input count must be divisible by the channel count. Its bytes are copied or written
    // before this call returns and may then be reused. The file remains within classic RIFF's
    // 32-bit length limit; exceeding it fails before appending the new samples.
    mtd addFrames(samples: const [..] s16) fail
    {
        if .isEnded do
            fail BadParameterError{"cannot append to an ended WAV writer"}
        if samples.count % .channels do
            fail BadParameterError{"WAV samples must contain complete interleaved frames"}
        let usedBytes = .frameCount * .channels * #sizeof(s16)
        if samples.count > (Swag.U32.Max - 36 - usedBytes) / #sizeof(s16) do
            fail OverflowError{"WAV data exceeds the classic RIFF size limit"}
        let bytes = samples.count * #sizeof(s16)

        if Core.BIG_ENDIAN
        {
            for sample in samples do
                try .sink.writeLittleEndian(sample)
        }
        else
        {
            try .sink.write(Swag.makeSlice(cast(const [*] u8, samples.buffer), bytes))
        }

        .frameCount += samples.count / .channels
    }

    // Updates the RIFF and data lengths and flushes a playable prefix to the file.
    mtd flush() fail
    {
        if .isEnded do
            fail BadParameterError{"cannot flush an ended WAV writer"}
        let dataBytes = .frameCount * .channels * #sizeof(s16)
        var riffSize  = Math.nativeToLittleEndian(cast(u32, 36 + dataBytes))
        var dataSize  = Math.nativeToLittleEndian(cast(u32, dataBytes))
        try .sink.patch(4, Swag.makeSlice(cast(const [*] u8, &riffSize), 4))
        try .sink.patch(40, Swag.makeSlice(cast(const [*] u8, &dataSize), 4))
        try .sink.flush()
    }

    // Finalizes the lengths and closes the file; repeated calls do nothing.
    mtd end() fail
    {
        if .isEnded do
            return
        try .flush()
        try .sink.close()
        .isEnded = true
    }
}

private impl Writer
{
    mtd writeHeader() fail
    {
        try .sink.writeText("RIFF")
        try .sink.writeLittleEndian(36'u32)
        try .sink.writeText("WAVEfmt ")
        try .sink.writeLittleEndian(16'u32)
        try .sink.writeLittleEndian(1'u16)
        try .sink.writeLittleEndian(.channels)
        try .sink.writeLittleEndian(.sampleRate)
        try .sink.writeLittleEndian(cast(u32, .sampleRate * .channels * 2))
        try .sink.writeLittleEndian(cast(u16, .channels * 2))
        try .sink.writeLittleEndian(16'u16)
        try .sink.writeText("data")
        try .sink.writeLittleEndian(0'u32)
    }
}
