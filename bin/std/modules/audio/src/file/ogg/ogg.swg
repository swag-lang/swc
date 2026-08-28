//! Format: Ogg transport of Vorbis and Opus sound.
//! Supported: Native `.ogg`, `.oga`, and `.opus` files whose first sound stream is Vorbis or Opus: page checksums, packets spanning pages, other streams multiplexed alongside, and an index of page runs whose sample counts come from the granule positions or, for Opus, from the packet durations.
//! Not supported: Chained streams, of which only the first link plays; Ogg FLAC, Speex, and Theora; and writing Ogg.
//! Role: This file owns Ogg page syntax, file traversal, and the streamed packet sound it builds; the codecs assemble packets from the pages they are handed.
//
#global namespace Ogg
#global internal

using Core, Core.Errors

const PageHeaderSize = 27'u64
const MaxSegments = 255'u64
const MaxPageSize = PageHeaderSize + MaxSegments + MaxSegments * 255

// The granule position of a page on which no packet ends.
const NoGranule = Swag.U64.Max

// Flags of the page header type byte.
const ContinuedPacket = 0x01'u8
const FirstPage = 0x02'u8
const LastPage = 0x04'u8

// How much of the file the page walk holds at once.
private const ScanWindow = 256 * 1024'u64

// The generator every page checksum is computed with, clause 6 of RFC 3533.
private const ChecksumPolynomial = 0x04C11DB7'u32

// What one page header states.
struct PageHeader
{
    headerBytes: u64          // Header size including the segment table.
    bodyBytes:   u64          // Sum of the segment sizes.
    flags:       u8
    granule:     u64          // [[NoGranule]] when no packet ends on the page.
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
    return cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8) | (cast(u32) bytes[offset + 2] << 16) | (cast(u32) bytes[offset + 3] << 24)
}

// Reads the page header at `offset`, which needs the capture pattern, the fixed header, and the
// segment table to be inside `bytes`.
func readPageHeader(bytes: const [..] u8, offset: u64)->PageHeader fail
{
    if offset > @countof(bytes) or @countof(bytes) - offset < PageHeaderSize do
        fail InvalidFormatError{"Ogg page header is truncated"}
    if bytes[offset] != 'O' or bytes[offset + 1] != 'g' or bytes[offset + 2] != 'g' or bytes[offset + 3] != 'S' do
        fail InvalidFormatError{"Ogg page has no capture pattern"}
    if bytes[offset + 4] != 0 do
        fail UnsupportedFormatError{"Ogg page uses an unknown stream structure version"}

    var result: retval
    result.flags       = bytes[offset + 5]
    result.granule     = cast(u64) readU32(bytes, offset + 6) | (cast(u64) readU32(bytes, offset + 10) << 32)
    result.serial      = readU32(bytes, offset + 14)
    result.sequence    = readU32(bytes, offset + 18)
    result.segments    = cast(u32) bytes[offset + 26]
    result.headerBytes = PageHeaderSize + result.segments
    if @countof(bytes) - offset < result.headerBytes do
        fail InvalidFormatError{"Ogg page segment table is truncated"}
    for index in result.segments
    {
        result.lacing[index] = bytes[offset + PageHeaderSize + index]
        result.bodyBytes     += result.lacing[index]
    }

    return result
}

// The checksum a page must carry, computed over the page with its own checksum field zeroed.
internal func pageChecksum(page: const [..] u8, table: const [256] u32)->u32
{
    var crc = 0'u32
    for byte, index in page
    {
        let value = index >= 22 and index < 26 ? 0'u8 : byte
        crc = (crc << 8) ^ table[((crc >> 24) ^ cast(u32) value) & 0xFF]
    }

    return crc
}

internal func buildChecksumTable()->[256] u32
{
    var result: retval
    for index in 256
    {
        var value = cast(u32) index << 24
        for 8 do
            value = value & 0x80000000 ? (value << 1) ^ ChecksumPolynomial : value << 1
        result[index] = value
    }

    return result
}

// Reads file windows on demand while the pages are walked.
private struct Source
{
    stream:      #null *File.FileStream
    size:        u64
    window:      Array'u8
    windowStart: u64
}

private impl Source
{
    // Loads `count` bytes at `offset` into the window and returns their index inside it.
    mtd load(offset, count: u64)->u64 fail
    {
        if offset > .size or count > .size - offset do
            fail InvalidFormatError{"Ogg page runs past the end of the file"}
        if offset < .windowStart or offset + count > .windowStart + .window.count
        {
            let want = Math.min(Math.max(count, ScanWindow), .size - offset)
            .window.resize(want)
            if !try .stream!.readExactAt(offset, .window.toSlice()) do
                fail InvalidFormatError{"Ogg page is truncated"}
            .windowStart = offset
        }

        return offset - .windowStart
    }
}

// Which codec a stream carries, found from its first packet.
private enum StreamKind
{
    Unknown
    Vorbis
    Opus
}

// What the first packet of the sound stream says about it.
private struct StreamInfo
{
    kind:          StreamKind
    serial:        u32
    channels:      u32
    sampleRate:    u32
    headerPackets: u32     // Packets the codec setup occupies before the sound starts.
    preSkip:       u64     // Opus priming frames omitted before audible frame zero.
    speakerMask:   u32
}

// Reads the identification packet at the start of a first page's body.
private func identify(body: const [..] u8)->StreamInfo fail
{
    var result: retval
    if @countof(body) >= 30 and body[0] == 1 and body[1] == 'v' and body[2] == 'o' and body[3] == 'r' and body[4] == 'b' and body[5] == 'i' and body[6] == 's'
    {
        if readU32(body, 7) != 0 do
            fail UnsupportedFormatError{"Vorbis stream uses an unknown version"}
        result.kind          = .Vorbis
        result.channels      = cast(u32) body[11]
        result.sampleRate    = readU32(body, 12)
        result.headerPackets = 3
        if !result.channels or result.channels > Vorbis.MaxChannels do
            fail UnsupportedFormatError{"Vorbis stream needs one to eight channels"}
        if !result.sampleRate do
            fail InvalidFormatError{"Vorbis stream declares no sample rate"}
        result.speakerMask = Vorbis.speakerMask(result.channels)
        return result
    }

    if @countof(body) >= 19 and body[0] == 'O' and body[1] == 'p' and body[2] == 'u' and body[3] == 's' and body[4] == 'H' and body[5] == 'e' and body[6] == 'a' and body[7] == 'd'
    {
        if (body[8] >> 4) != 0 do
            fail UnsupportedFormatError{"Opus stream uses an unknown version"}
        result.kind          = .Opus
        result.channels      = cast(u32) body[9]
        result.preSkip       = cast(u64) body[10] | (cast(u64) body[11] << 8)
        result.sampleRate    = Opus.OutputRate
        result.headerPackets = 2
        if body[18] != 0 do
            fail UnsupportedFormatError{"Opus stream uses a multistream channel mapping"}
        if !result.channels or result.channels > 2 do
            fail UnsupportedFormatError{"Opus stream needs one or two channels"}
        return result
    }

    return result
}

// Walks the pages of a file, verifies them, and records the sound stream they carry.
private struct Walker
{
    source:  Source
    table:   [256] u32
    offset:  u64            // Where the page being examined starts.
    packets: Array'SoundPacket
}

private impl Walker
{
    // Reads and verifies the page at `.offset`, or returns false at the end of the file.
    mtd next(header: *PageHeader)->bool fail
    {
        if .offset >= .source.size do
            return false
        let at = try .source.load(.offset, Math.min(MaxPageSize, .source.size - .offset))
        header[] = try readPageHeader(.source.window.toSlice(), at)
        let total = header.totalBytes()
        if .offset + total > .source.size do
            fail InvalidFormatError{"Ogg page runs past the end of the file"}
        let pageAt = try .source.load(.offset, total)
        let page   = .source.window.toSlice()[pageAt until pageAt + total]
        if pageChecksum(page, .table) != readU32(page, 22) do
            fail InvalidFormatError{"Ogg page checksum does not match its content"}
        return true
    }

    // Returns the window index of the body of the page at `.offset`, whose header was just read.
    mtd bodyIndex(header: const *PageHeader)->u64 fail
    {
        let at = try .source.load(.offset, header.totalBytes())
        return at + header.headerBytes
    }
}

// Finds the sound stream among the first pages, which every stream of the file opens with.
private func findStream(walker: *Walker)->StreamInfo fail
{
    var header: PageHeader
    while try walker.next(&header)
    {
        if !(header.flags & FirstPage) do
            break
        let at   = try walker.bodyIndex(&header)
        let info = try identify(walker.source.window.toSlice()[at until at + header.bodyBytes])
        if info.kind != .Unknown
        {
            var result = info
            result.serial = header.serial
            return result
        }

        walker.offset += header.totalBytes()
    }

    fail UnsupportedFormatError{"Ogg file carries no Vorbis or Opus stream"}
}

// Advances past the pages holding the codec's header packets and returns where the sound starts.
private func skipHeaders(walker: *Walker, info: const *StreamInfo)->u64 fail
{
    var completed = 0'u32
    var header:   PageHeader
    while try walker.next(&header)
    {
        if header.serial == info.serial
        {
            for index in header.segments where header.lacing[index] < 255 do
                completed += 1
        }

        walker.offset += header.totalBytes()
        if completed >= info.headerPackets do
            return walker.offset
    }

    fail InvalidFormatError{"Ogg stream ends inside its header packets"}
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
    var total      = 0'u64
    var previous   = 0'u64      // Granule position at the end of the previous run.
    var sequence   = Swag.U32.Max
    var firstRun   = true
    var header:    PageHeader
    var lookahead: PageHeader
    var hasPage    = try walker.next(&header)
    while hasPage
    {
        let pageOffset = walker.offset
        let pageBytes  = header.totalBytes()
        if header.serial != info.serial
        {
            // Another stream's page inside a run stays in the run; the codec skips it.
            if run.start != Swag.U64.Max do
                run.bytes += pageBytes
            walker.offset += pageBytes
            hasPage = try walker.next(&header)
            continue
        }

        if sequence != Swag.U32.Max and header.sequence != sequence + 1 do
            fail InvalidFormatError{"Ogg page sequence has a gap"}
        sequence = header.sequence

        if run.start == Swag.U64.Max do
            run.start = pageOffset
        run.bytes += pageBytes

        if info.kind == .Opus
        {
            let bodyAt = try walker.bodyIndex(&header)
            var at     = bodyAt
            for index in header.segments
            {
                let size = cast(u64) header.lacing[index]
                if !run.open
                {
                    let frames = Opus.packetFrames(walker.source.window.toSlice()[at until at + size])
                    if !frames do
                        fail InvalidFormatError{"Opus packet has an invalid table of contents"}
                    run.frames += frames
                }

                run.open = size == 255
                at       += size
            }
        }

        // Find the next page of this stream, to know whether a packet continues into it.
        var probe     = pageOffset + pageBytes
        var continues = false
        var more      = false
        while true
        {
            walker.offset = probe
            if !try walker.next(&lookahead) do
                break
            if lookahead.serial == info.serial
            {
                more      = true
                continues = (lookahead.flags & ContinuedPacket) != 0
                break
            }

            probe += lookahead.totalBytes()
        }

        walker.offset = pageOffset + pageBytes
        let last = (header.flags & LastPage) != 0 or !more

        if header.granule != NoGranule and (!continues or last)
        {
            var frames: u64
            if info.kind == .Vorbis
            {
                if header.granule < previous do
                    fail InvalidFormatError{"Ogg granule position runs backwards"}
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
                if !frames
                {
                    // A final page that completes no frame extends the run before it.
                    if walker.packets.count do
                        walker.packets.backPtr().byteSize += cast(u32) run.bytes
                }
                else
                {
                    if run.bytes > Swag.U32.Max or frames > Swag.U32.Max do
                        fail InvalidFormatError{"Ogg page run is larger than a packet may be"}
                    walker.packets.add({run.start, cast(u32) run.bytes, cast(u32) frames})
                    total += frames
                }

                previous = header.granule
                firstRun = false
                run      = {}
            }
        }

        if last do
            break
        hasPage = try walker.next(&header)
    }

    return total
}

// Opens an Ogg file as a streamed packet sound.
//
// The audio stays in the file: opening verifies every page and records where each run of pages
// starts and how many sample frames it completes. The codec receives the header pages as its
// configuration and the runs as its packets.
func openFile(path: string)->SoundFile fail
{
    var stream = File.openRead(path)
    var walker: Walker
    walker.source.stream = &stream
    walker.source.size   = try stream.size()
    walker.table         = buildChecksumTable()

    let info  = try findStream(&walker)
    let start = try skipHeaders(&walker, &info)
    let total = try indexRuns(&walker, &info)
    if !walker.packets.count do
        fail InvalidFormatError{"Ogg stream carries no sound page"}

    var config: Array'u8
    config.resize(start)
    if !try stream.readExactAt(0, config.toSlice()) do
        fail InvalidFormatError{"Ogg header pages are truncated"}
    stream.close()

    let encoding = info.kind == .Vorbis ? SoundFileEncoding.Vorbis : SoundFileEncoding.Opus
    return try SoundFile.openPacketStream(path, encoding, info.sampleRate, info.channels, total, walker.packets.toSlice(), config.toSlice(), {leadingTrimFrames: info.preSkip, speakerMask: info.speakerMask})
}
