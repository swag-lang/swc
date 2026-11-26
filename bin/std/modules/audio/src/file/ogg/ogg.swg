//! Format: Ogg transport of Vorbis, Opus, and FLAC sound.
//! Supported: Page checksums, packets spanning pages, multiplexed streams, and indexed page runs.
//! Not supported: Chained streams beyond the first link, Speex, Theora, and writing Ogg.
//! Role: This file owns Ogg page syntax, file traversal, and the streamed packet sound it builds; the codecs assemble packets from the pages they are handed.
//
#global namespace Ogg
#global internal

using Core, Core.Errors

const PageHeaderSize = 27'u64
const MaxSegments    = 255'u64
const MaxPageSize    = PageHeaderSize + MaxSegments + MaxSegments * 255

// The granule position of a page on which no packet ends.
const NoGranule = Swag.U64.Max

// Flags of the page header type byte.
const ContinuedPacket = 0x01'u8
const FirstPage       = 0x02'u8
const LastPage        = 0x04'u8

// The generator every page checksum is computed with, clause 6 of RFC 3533.
private const ChecksumPolynomial = 0x04C11DB7'u32
private const ChecksumOffset     = 22'u64
private const ChecksumEnd        = ChecksumOffset + #sizeof(u32)
private const ChecksumTable      = #run buildChecksumTable()

// What one page header states.
struct PageHeader
{
    headerBytes: u64     // Header size including the segment table.
    bodyBytes:   u64     // Sum of the segment sizes.
    flags:       u8
    granule:     u64     // [[NoGranule]] when no packet ends on the page.
    serial:      u32
    sequence:    u32
    segments:    u32
    lacing:      [255] u8     // Segment sizes; a segment of 255 bytes continues into the next.
}

impl PageHeader
{
    mtd const totalBytes()->u64 => .headerBytes + .bodyBytes
}

func readU32(bytes: const [..] u8, offset: u64)->u32
{
    return Math.make32(bytes[offset + 3], bytes[offset + 2], bytes[offset + 1], bytes[offset])
}

// Reads the page header at `offset`, which needs the capture pattern, the fixed header, and the
// segment table to be inside `bytes`.
func readPageHeader(bytes: const [..] u8, offset: u64)->PageHeader fail
{
    if offset > bytes.count do
        fail InvalidFormatError{"Ogg page header is truncated"}
    if bytes.count - offset < PageHeaderSize do
        fail InvalidFormatError{"Ogg page header is truncated"}
    if bytes[offset] != 'O' or
       bytes[offset + 1] != 'g' or
       bytes[offset + 2] != 'g' or
       bytes[offset + 3] != 'S' do
        fail InvalidFormatError{"Ogg page has no capture pattern"}
    if bytes[offset + 4] != 0 do
        fail UnsupportedFormatError{"Ogg page uses an unknown stream structure version"}
    if bytes[offset + 5] & 0xF8 do
        fail InvalidFormatError{"Ogg page sets reserved header flags"}

    with var result: #returntype
    {
        .flags       = bytes[offset + 5]
        .granule     = cast(u64, readU32(bytes, offset + 6)) | (cast(u64, readU32(bytes, offset + 10)) << 32)
        .serial      = readU32(bytes, offset + 14)
        .sequence    = readU32(bytes, offset + 18)
        .segments    = cast(u32, bytes[offset + 26])
        .headerBytes = PageHeaderSize + .segments
    }

    if bytes.count - offset < result.headerBytes do
        fail InvalidFormatError{"Ogg page segment table is truncated"}
    for index in result.segments
    {
        result.lacing[index] = bytes[offset + PageHeaderSize + index]
        result.bodyBytes     += result.lacing[index]
    }

    return result
}

// The checksum a page must carry, computed over the page with its own checksum field zeroed.
internal func pageChecksum(page: const [..] u8)->u32
{
    var crc = 0'u32
    let beforeChecksum = Math.min(page.count, ChecksumOffset)
    let afterChecksum  = Math.min(page.count, ChecksumEnd)
    for index in beforeChecksum do
        crc = (crc << 8) ^ ChecksumTable[0, (crc >> 24) ^ page[index]]
    for beforeChecksum until afterChecksum do
        crc = (crc << 8) ^ ChecksumTable[0, crc >> 24]

    var offset = afterChecksum
    #static if not Core.BIG_ENDIAN
    {
        let foldBytes = (page.count - offset) & ~15'u64
        if foldBytes >= 64
        {
            let block = foldMsbChecksum'(32'u32, ChecksumPolynomial)(page[offset until offset + foldBytes], crc)
            crc    = updateChecksum(block, 0)
            offset += foldBytes
        }
    }

    return updateChecksum(page[offset until], crc)
}

private func updateChecksum(bytes: const [..] u8, initial: u32)->u32
{
    // The tables fold each byte's contribution after up to seven further bytes.
    var crc    = initial
    var offset = 0'u64
    while bytes.count - offset >= #sizeof(u64)
    {
        let word  = Math.bigEndianToNative(cast(const [*] u64, bytes.buffer + offset)[0])
        let mixed = word ^ (cast(u64, crc) << 32)
        crc = ChecksumTable[7, mixed >> 56] ^
              ChecksumTable[6, (mixed >> 48) & 0xFF] ^
              ChecksumTable[5, (mixed >> 40) & 0xFF] ^
              ChecksumTable[4, (mixed >> 32) & 0xFF] ^
              ChecksumTable[3, (mixed >> 24) & 0xFF] ^
              ChecksumTable[2, (mixed >> 16) & 0xFF] ^
              ChecksumTable[1, (mixed >> 8) & 0xFF] ^
              ChecksumTable[0, mixed & 0xFF]
        offset += #sizeof(u64)
    }

    for index in offset until bytes.count do
        crc = (crc << 8) ^ ChecksumTable[0, (crc >> 24) ^ bytes[index]]
    return crc
}

private func buildChecksumTable()->[8, 256] u32
{
    var result: #returntype
    for index in 256
    {
        var value = cast(u32, index) << 24
        for 8 do
            value = value & 0x80000000 ? (value << 1) ^ ChecksumPolynomial : value << 1
        result[0, index] = value
    }

    for slice in 1 until 8
    {
        for index in 256
        {
            let previous = result[slice - 1, index]
            result[slice, index] = (previous << 8) ^ result[0, previous >> 24]
        }
    }

    return result
}

// Which codec a stream carries, found from its first packet.
private enum StreamKind
{
    Unknown
    Vorbis
    Opus
    Flac
}

// What the first packet of the sound stream says about it.
private struct StreamInfo
{
    kind:                     StreamKind
    serial:                   u32
    channels:                 u32
    sampleRate:               u32
    headerPackets:            u32     // Packets the codec setup occupies before the sound starts.
    preSkip:                  u64     // Opus priming frames omitted before audible frame zero.
    speakerMask:              u32
    firstAudioSequence:       u32
    headerPacketsOnAudioPage: u32
}

// Reads the identification packet at the start of a first page's body.
private func identify(body: const [..] u8)->StreamInfo fail
{
    var result: #returntype
    if body.count >= 30 and
       body[0] == 1 and
       body[1] == 'v' and
       body[2] == 'o' and
       body[3] == 'r' and
       body[4] == 'b' and
       body[5] == 'i' and
       body[6] == 's'
    {
        if readU32(body, 7) != 0 do
            fail UnsupportedFormatError{"Vorbis stream uses an unknown version"}
        result.kind          = .Vorbis
        result.channels      = cast(u32, body[11])
        result.sampleRate    = readU32(body, 12)
        result.headerPackets = 3
        if not result.channels or result.channels > Vorbis.MaxChannels do
            fail UnsupportedFormatError{"Vorbis stream needs one to eight channels"}
        if not result.sampleRate do
            fail InvalidFormatError{"Vorbis stream declares no sample rate"}
        result.speakerMask = Vorbis.speakerMask(result.channels)
        return result
    }

    if body.count >= 19 and
       body[0] == 'O' and
       body[1] == 'p' and
       body[2] == 'u' and
       body[3] == 's' and
       body[4] == 'H' and
       body[5] == 'e' and
       body[6] == 'a' and
       body[7] == 'd'
    {
        if (body[8] >> 4) != 0 do
            fail UnsupportedFormatError{"Opus stream uses an unknown version"}
        result.kind          = .Opus
        result.channels      = cast(u32, body[9])
        result.preSkip       = cast(u64, body[10]) | (cast(u64, body[11]) << 8)
        result.sampleRate    = Opus.OutputRate
        result.headerPackets = 2
        if body[18] != 0 do
            fail UnsupportedFormatError{"Opus stream uses a multistream channel mapping"}
        if not result.channels or result.channels > 2 do
            fail UnsupportedFormatError{"Opus stream needs one or two channels"}
        return result
    }

    if body.count >= 5 and body[0] == 0x7F and body[1 until 5] == cast(const [..] u8, "FLAC")
    {
        // The nine-byte mapping header is followed by the native marker and STREAMINFO block.
        if body.count != 51 or
           body[9 until 13] != cast(const [..] u8, "fLaC") or
           (body[13] & 0x7F) != 0 or
           body[14] != 0 or
           body[15] != 0 or
           body[16] != 34 do
            fail InvalidFormatError{"Ogg FLAC identification packet does not hold STREAMINFO"}
        if body[5] != 1 or body[6] != 0 do
            fail UnsupportedFormatError{"Ogg FLAC stream mapping needs version 1.0"}
        var probe: Flac.Codec
        try probe.readStreamInfo(body[9 to])
        result.kind          = .Flac
        result.channels      = probe.info.channels
        result.sampleRate    = probe.info.sampleRate
        result.headerPackets = 1 + (cast(u32, body[7]) << 8) + cast(u32, body[8])
    }

    return result
}

// Walks the pages of a file, verifies them, and records the sound stream they carry.
//
// A page is at most [[MaxPageSize]] bytes, which one read window of the source holds, so the
// walk peeks at pages in place and never copies one.
private struct Walker
{
    source:  ByteSource
    offset:  u64     // Where the page being examined starts.
    packets: Array'SoundPacket
}

private impl Walker
{
    // Reads and verifies the page at `.offset`, or returns false at the end of the file.
    mtd next(header: *PageHeader)->bool fail
    {
        if .offset >= .source.size() do
            return false
        try .source.seek(.offset)
        let remaining = .source.remaining()
        let head      = try .source.peek(Math.min(PageHeaderSize + MaxSegments, remaining))
        header[] = try readPageHeader(head, 0)
        let total = header.totalBytes()
        if total > remaining do
            fail InvalidFormatError{"Ogg page runs past the end of the file"}
        let bytes = head.count < total ? try .source.peek(total) : head
        let page  = bytes[until total]
        if pageChecksum(page) != readU32(page, ChecksumOffset) do
            fail InvalidFormatError{"Ogg page checksum does not match its content"}
        return true
    }

    // Verifies interleaved pages while advancing to the requested stream.
    mtd nextStreamPage(serial: u32, header: *PageHeader)->bool fail
    {
        while try .next(header)
        {
            if header.serial == serial do
                return true
            .offset += header.totalBytes()
        }

        return false
    }

    // Returns the body of the page at `.offset`, whose header was just read.
    //
    // The slice borrows the source's window and is valid until the walk moves on.
    mtd body(header: const *PageHeader)->const [..] u8 fail
    {
        try .source.seek(.offset + header.headerBytes)
        return (try .source.peek(header.bodyBytes))[0 until header.bodyBytes]
    }
}

// Finds the sound stream among the first pages, which every stream of the file opens with.
private func findStream(walker: *Walker)->StreamInfo fail
{
    var header: PageHeader
    while try walker.next(&header)
    {
        if not (header.flags & FirstPage) do
            break
        let info = try identify(try walker.body(&header))
        if info.kind != .Unknown
        {
            var result = info
            result.serial = header.serial
            return result
        }

        walker.offset += header.totalBytes()
    }

    fail UnsupportedFormatError{"Ogg file carries no Vorbis, Opus, or FLAC stream"}
}

private struct HeaderEnd
{
    configEnd:  u64     // End of the page containing the last header packet.
    audioStart: u64     // Start of that page when audio follows its headers; otherwise `configEnd`.
}

// Advances past the pages holding the codec's header packets and returns where the sound starts.
private func skipHeaders(walker: *Walker, info: *StreamInfo)->HeaderEnd fail
{
    var completed         = 0'u32
    var sequence          = 0'u32
    var hasSequence       = false
    var expectedContinued = false
    var header: PageHeader
    while try walker.next(&header)
    {
        let pageOffset = walker.offset
        if header.serial == info.serial
        {
            if hasSequence
            {
                let expectedSequence = sequence == Swag.U32.Max ? 0 : sequence + 1
                if header.sequence != expectedSequence do
                    fail InvalidFormatError{"Ogg header page sequence has a gap"}
                if ((header.flags & ContinuedPacket) != 0) != expectedContinued do
                    fail InvalidFormatError{"Ogg header continued-packet flag disagrees with the preceding page lacing"}
            }
            elif header.sequence != 0 or (header.flags & ContinuedPacket) != 0
            {
                fail InvalidFormatError{"Ogg first header page has an invalid sequence or continuation flag"}
            }

            sequence          = header.sequence
            hasSequence       = true
            expectedContinued = false
            if header.segments do
                expectedContinued = header.lacing[header.segments - 1] == 255

            var completedOnPage = 0'u32
            for index in header.segments
            {
                if header.lacing[index] < 255
                {
                    completed       += 1
                    completedOnPage += 1
                    if completed == info.headerPackets
                    {
                        let pageEnd = pageOffset + header.totalBytes()
                        if index + 1 < cast(u64, header.segments)
                        {
                            info.firstAudioSequence       = header.sequence
                            info.headerPacketsOnAudioPage = completedOnPage
                            walker.offset = pageOffset
                            return HeaderEnd{pageEnd, pageOffset}
                        }

                        info.firstAudioSequence = header.sequence == Swag.U32.Max ? 0 : header.sequence + 1
                        walker.offset = pageEnd
                        return HeaderEnd{pageEnd, pageEnd}
                    }
                }
            }
        }

        walker.offset += header.totalBytes()
    }

    fail InvalidFormatError{"Ogg stream ends inside its header packets"}
}

// Reads the FLAC setup and identifies where audio starts on a page shared with metadata.
func flacSetup(config: const [..] u8)->{streamInfo: const [..] u8, serial: u32, firstAudioSequence: u32, headerPacketsOnAudioPage: u32} fail
{
    var walker: Walker
    walker.source = ByteSource.openMemory(config)
    var info = try findStream(&walker)
    if info.kind != .Flac do
        fail InvalidFormatError{"Ogg FLAC configuration has no FLAC identification packet"}
    var header: PageHeader
    if not try walker.next(&header) do
        fail InvalidFormatError{"Ogg FLAC configuration ends before the identification page"}
    let start = walker.offset + header.headerBytes + 9
    discard try skipHeaders(&walker, &info)
    return {config[start until start + 42], info.serial, info.firstAudioSequence, info.headerPacketsOnAudioPage}
}

// One run of pages being merged into a packet of the index.
private struct Run
{
    start:  u64 = Swag.U64.Max
    bytes:  u64
    frames: u64      // Opus: frames the packets starting in the run play.
    open:   bool     // Opus: a packet continues from the previous page.
}

// Builds the page-run index of the sound stream.
//
// A run ends on a page that completes at least one packet and whose successor starts a fresh
// packet, so a codec handed one run never needs a byte from the run before it. The first run and
// the last one are trimmed by the granule positions as the formats require.
private func indexRuns(walker: *Walker, info: const *StreamInfo)->u64 fail
{
    var run:       Run
    var total             = 0'u64
    var previous          = 0'u64     // Granule position at the end of the previous run.
    var sequence          = 0'u32
    var hasSequence       = false
    var expectedContinued = false
    var firstRun          = true
    var header:    PageHeader
    var lookahead: PageHeader
    if not (try walker.nextStreamPage(info.serial, &header)) do
        return 0

    for
    {
        let pageOffset = walker.offset
        let pageBytes  = header.totalBytes()

        let continued = (header.flags & ContinuedPacket) != 0
        if hasSequence
        {
            if continued != expectedContinued do
                fail InvalidFormatError{"Ogg continued-packet flag disagrees with the preceding page lacing"}
            let expectedSequence = sequence == Swag.U32.Max ? 0 : sequence + 1
            if header.sequence != expectedSequence do
                fail InvalidFormatError{"Ogg page sequence has a gap"}
        }

        sequence          = header.sequence
        hasSequence       = true
        expectedContinued = false
        if header.segments do
            expectedContinued = header.lacing[header.segments - 1] == 255

        if run.start == Swag.U64.Max
        {
            run.start = pageOffset
            run.open  = (header.flags & ContinuedPacket) != 0
        }

        run.bytes += pageBytes

        if info.kind == .Opus
        {
            let body = try walker.body(&header)
            var at   = 0'u64
            var headersToSkip = header.sequence == info.firstAudioSequence ? info.headerPacketsOnAudioPage : 0'u32
            for index in header.segments
            {
                let size = cast(u64, header.lacing[index])
                if not run.open
                {
                    if not headersToSkip
                    {
                        let frames = Opus.packetFrames(body[at until at + size])
                        if not frames do
                            fail InvalidFormatError{"Opus packet has an invalid table of contents"}
                        if run.frames > Swag.U64.Max - frames do
                            fail OverflowError{"Ogg Opus run sample count overflows"}
                        run.frames += frames
                    }
                }

                if size < 255 and headersToSkip do
                    headersToSkip -= 1
                run.open = size == 255
                at       += size
            }
        }

        // Keep the verified lookahead for the next iteration.
        let pageEnd = pageOffset + pageBytes
        walker.offset = pageEnd
        let more      = try walker.nextStreamPage(info.serial, &lookahead)
        let continues = more and (lookahead.flags & ContinuedPacket) != 0
        let last      = (header.flags & LastPage) != 0 or not more

        if header.granule != NoGranule and (not continues or last)
        {
            if header.granule < previous do
                fail InvalidFormatError{"Ogg granule position runs backwards"}
            var frames: u64
            if info.kind != .Opus
            {
                frames = header.granule - previous
            }
            else
            {
                frames = run.frames
                if firstRun do
                    frames = Math.min(frames, header.granule)
                elif last and header.granule >= previous do
                    frames = Math.min(frames, header.granule - previous)
            }

            if frames or last
            {
                if not frames
                {
                    // A final page that completes no frame extends the run before it.
                    if not walker.packets.isEmpty()
                    {
                        let previousBytes = cast(u64, walker.packets.backPtr().byteSize)
                        if run.bytes > Swag.U32.Max or run.bytes > Swag.U32.Max - previousBytes do
                            fail InvalidFormatError{"Ogg page run is larger than a packet may be"}
                        walker.packets.backPtr().byteSize += cast(u32, run.bytes)
                    }
                }
                else
                {
                    if run.bytes > Swag.U32.Max or frames > Swag.U32.Max do
                        fail InvalidFormatError{"Ogg page run is larger than a packet may be"}
                    if total > Swag.U64.Max - frames do
                        fail OverflowError{"Ogg sound sample count overflows"}
                    walker.packets.add(SoundPacket{run.start, cast(u32, run.bytes), cast(u32, frames)})
                    total += frames
                }

                previous = header.granule
                firstRun = false
                run      = {}
            }
        }

        if last do
            break

        // Interleaved pages belong to the byte range only while an audio run is open.
        if run.start != Swag.U64.Max do
            run.bytes += walker.offset - pageEnd
        header = lookahead
    }

    return total
}

// Opens an Ogg file as a streamed packet sound.
//
// The audio stays in the file: opening verifies every page and records where each run of pages
// starts and how many sample frames it completes. The codec receives the header pages as its
// configuration and the runs as its packets.
#[Swag.Propagate]
func openFile(path: string)->SoundFile fail
{
    var walker: Walker
    walker.source = ByteSource.openFile(path)

    var info      = findStream(&walker)
    let headerEnd = skipHeaders(&walker, &info)
    walker.offset = headerEnd.audioStart
    let total = indexRuns(&walker, &info)
    if walker.packets.isEmpty() do
        fail InvalidFormatError{"Ogg stream carries no sound page"}

    var config: Array'u8
    config.resize(headerEnd.configEnd)
    walker.source.seek(0)
    walker.source.readExact(config.toSlice())
    walker.source.close()

    var encoding: SoundFileEncoding
    switch info.kind
    {
    case .Vorbis: encoding = .Vorbis
    case .Opus:   encoding = .Opus
    case .Flac:   encoding = .Flac
    default:      unreachable
    }

    return SoundFile.openPacketStream(path, encoding, info.sampleRate, info.channels, total, walker.packets.toSlice(), config.toSlice(), {leadingTrimFrames: info.preSkip, speakerMask: info.speakerMask})
}
