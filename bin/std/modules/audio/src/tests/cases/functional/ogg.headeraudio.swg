#global if #command == Swag.CompilerCommand.Test

using Core

private struct OggTestPage
{
    offset: u64
    bytes:  u64
    header: Ogg.PageHeader
}

private func oggTestPage(source: const [..] u8, wantedIndex: u64)->OggTestPage fail
{
    var offset = 0'u64
    var index  = 0'u64
    for
    {
        if offset >= source.count do
            break
        let header = try Ogg.readPageHeader(source, offset)
        let bytes  = header.totalBytes()
        if bytes > source.count - offset do
            fail InvalidFormatError{"Ogg test page runs past its fixture"}
        if index == wantedIndex do
            return OggTestPage{offset, bytes, header}
        offset += bytes
        index  += 1
    }

    fail InvalidFormatError{"Ogg test fixture has too few pages"}
}

private func oggRefreshTestChecksum(page: *Array'u8)
{
    for index in 4 do
        page[22 + index] = 0
    let checksum = Ogg.pageChecksum(page.toSlice())
    for index in 4 do
        page[22 + index] = cast(u8, (checksum >> cast(u32, index * 8)) & 0xFF'u32)
}

// Moves the first audio page's packets onto the page that ends the codec headers.
private func oggMoveAudioPageAfterHeaders(source: const [..] u8,
                                          headerPageIndex,
                                          audioPageIndex: u64)->Array'u8 fail
{
    if audioPageIndex <= headerPageIndex do
        fail BadParameterError{"Ogg test audio page must follow its header page"}
    let headerPage = try oggTestPage(source, headerPageIndex)
    let audioPage  = try oggTestPage(source, audioPageIndex)
    if headerPage.header.serial != audioPage.header.serial do
        fail InvalidFormatError{"Ogg test pages must belong to the same stream"}
    let segmentCount = headerPage.header.segments + audioPage.header.segments
    if segmentCount > 255 do
        fail InvalidFormatError{"Ogg test page exceeds its segment table"}

    var merged: Array'u8
    merged.add(source[headerPage.offset until headerPage.offset + Ogg.PageHeaderSize])
    merged[26] = cast(u8, segmentCount)
    for index in 8 do
        merged[6 + index] = cast(u8, (audioPage.header.granule >> cast(u32, index * 8)) & 0xFF'u64)
    for index in headerPage.header.segments do
        merged.add(headerPage.header.lacing[index])
    for index in audioPage.header.segments do
        merged.add(audioPage.header.lacing[index])
    merged.add(source[headerPage.offset + headerPage.header.headerBytes until
                      headerPage.offset + headerPage.bytes])
    merged.add(source[audioPage.offset + audioPage.header.headerBytes until
                      audioPage.offset + audioPage.bytes])
    oggRefreshTestChecksum(&merged)

    var result: Array'u8
    var offset = 0'u64
    var index  = 0'u64
    for
    {
        if offset >= source.count do
            break
        let header = try Ogg.readPageHeader(source, offset)
        let bytes  = header.totalBytes()
        if index == headerPageIndex
        {
            result.add(merged.toSlice())
        }
        elif index != audioPageIndex
        {
            var page: Array'u8
            page.add(source[offset until offset + bytes])
            if index > audioPageIndex
            {
                let sequence = header.sequence - 1
                for part in 4 do
                    page[18 + part] = cast(u8, (sequence >> cast(u32, part * 8)) & 0xFF'u32)
                oggRefreshTestChecksum(&page)
            }

            result.add(page.toSlice())
        }

        offset += bytes
        index  += 1
    }

    return result
}

// Sets an impossible continuation bit on a later page and keeps that page's CRC valid.
private func oggSetUnexpectedContinuation(source: const [..] u8)->Array'u8 fail
{
    var previous: OggTestPage
    var hasPrevious = false
    var offset      = 0'u64
    for
    {
        if offset >= source.count do
            break
        let header = try Ogg.readPageHeader(source, offset)
        let page   = OggTestPage{offset, header.totalBytes(), header}
        if hasPrevious and
           page.header.serial == previous.header.serial and
           previous.header.sequence < Swag.U32.Max and
           page.header.sequence == previous.header.sequence + 1 and
           page.header.sequence >= 3 and
           not (page.header.flags & Ogg.ContinuedPacket) and
           previous.header.segments and
           previous.header.lacing[previous.header.segments - 1] < 255
        {
            var changedPage: Array'u8
            changedPage.add(source[offset until offset + page.bytes])
            changedPage[5] |= Ogg.ContinuedPacket
            oggRefreshTestChecksum(&changedPage)

            var result: #returntype
            result.add(source[until offset])
            result.add(changedPage.toSlice())
            result.add(source[offset + page.bytes to])
            return result
        }

        previous    = page
        hasPrevious = true
        offset      += page.bytes
    }

    fail InvalidFormatError{"Ogg fixture has no eligible page for a continuation flag mutation"}
}

// Skips a page sequence number between the first two pages of the sound stream.
private func oggSetHeaderSequenceGap(source: const [..] u8)->Array'u8 fail
{
    var serial    = 0'u32
    var hasStream = false
    var offset    = 0'u64
    for
    {
        if offset >= source.count do
            break
        let header = try Ogg.readPageHeader(source, offset)
        let bytes  = header.totalBytes()
        if bytes > source.count - offset do
            fail InvalidFormatError{"Ogg test page runs past its fixture"}

        if not hasStream and (header.flags & Ogg.FirstPage) != 0
        {
            serial    = header.serial
            hasStream = true
        }
        elif hasStream and header.serial == serial
        {
            if header.sequence > Swag.U32.Max - 2 do
                fail InvalidFormatError{"Ogg test page sequence cannot carry a gap"}

            var changedPage: Array'u8
            changedPage.add(source[offset until offset + bytes])
            let sequence = header.sequence + 2
            for part in 4 do
                changedPage[18 + part] = cast(u8, (sequence >> cast(u32, part * 8)) & 0xFF'u32)
            oggRefreshTestChecksum(&changedPage)

            var result: #returntype
            result.add(source[until offset])
            result.add(changedPage.toSlice())
            result.add(source[offset + bytes to])
            return result
        }

        offset += bytes
    }

    fail InvalidFormatError{"Ogg fixture has no second page of its sound stream"}
}

// Claims a header packet continues even though the preceding header page completed it.
private func oggSetUnexpectedHeaderContinuation(source: const [..] u8)->Array'u8 fail
{
    var serial    = 0'u32
    var hasStream = false
    var previous: OggTestPage
    var offset    = 0'u64
    for
    {
        if offset >= source.count do
            break
        let header = try Ogg.readPageHeader(source, offset)
        let bytes  = header.totalBytes()
        if bytes > source.count - offset do
            fail InvalidFormatError{"Ogg test page runs past its fixture"}

        if not hasStream and (header.flags & Ogg.FirstPage) != 0
        {
            serial    = header.serial
            hasStream = true
            previous  = OggTestPage{offset, bytes, header}
        }
        elif hasStream and header.serial == serial
        {
            if not previous.header.segments or previous.header.lacing[previous.header.segments - 1] == 255 do
                fail InvalidFormatError{"Ogg first header page does not complete its last packet"}
            if (header.flags & Ogg.ContinuedPacket) != 0 do
                fail InvalidFormatError{"Ogg second header page already continues a packet"}

            var changedPage: Array'u8
            changedPage.add(source[offset until offset + bytes])
            changedPage[5] |= Ogg.ContinuedPacket
            oggRefreshTestChecksum(&changedPage)

            var result: #returntype
            result.add(source[until offset])
            result.add(changedPage.toSlice())
            result.add(source[offset + bytes to])
            return result
        }

        if hasStream and header.serial == serial do
            previous = OggTestPage{offset, bytes, header}
        offset += bytes
    }

    fail InvalidFormatError{"Ogg fixture has no second page of its sound stream"}
}

private func oggDecodePcm16(sound: const *SoundFile)->Array's16 fail
{
    var result: #returntype
    try sound.decodePcm16(func|result = &result|(samples: const [..] s16)->bool
    {
        result.add(samples)
        return true
    })
    return result
}

private func oggAssertMatchesPcm(decoded: const [..] s16, expected: const [..] u8)
{
    Swag.require(decoded.count * #sizeof(s16) == expected.count)
    let reference = cast(const [*] s16, expected.buffer)
    var energy: f64
    for index in decoded.count
    {
        let difference = cast(f64, decoded[index]) - cast(f64, reference[index])
        energy += difference * difference
    }

    let rms = Math.sqrt(energy / cast(f64, decoded.count)) / 32768.0'f64
    Swag.require(rms <= 0.0001'f64)
}

// Ogg FLAC keeps its lossless PCM, including audio placed on the last setup page.
#test
{
    let path = audioGetTestDataPath("flac-stereo-44100.oga")
    let native = expect SoundFile.load(audioGetTestDataPath("flac-stereo-44100.flac"))
    let expected = expect oggDecodePcm16(&native)
    let ogg = expect SoundFile.load(path)
    Swag.require(ogg.sampleEncoding() == .Flac and ogg.numChannels() == 2 and ogg.sampleRateHz() == 44_100)
    Swag.require(Slice.equals((expect oggDecodePcm16(&ogg)).toSlice(), expected.toSlice()))

    let source = expect File.readAllBytes(path)
    let merged = expect oggMoveAudioPageAfterHeaders(source.toSlice(), 1, 2)
    let mixedPath = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("audio-ogg-flac-%.oga", Guid64.random()))
    defer discard catch File.delete(mixedPath)
    expect File.writeAllBytes(mixedPath, merged.toSlice())
    let mixed = expect SoundFile.load(mixedPath)
    Swag.require(Slice.equals((expect oggDecodePcm16(&mixed)).toSlice(), expected.toSlice()))
}

// A frame split across Ogg pages survives intervening pages of another logical stream.
#test
{
    const FragmentBytes = 255'u64

    let flac      = expect File.readAllBytes(audioGetTestDataPath("flac-stereo-44100.oga"))
    let firstFlac = expect oggTestPage(flac.toSlice(), 0)
    let audio     = expect oggTestPage(flac.toSlice(), 2)
    let body      = audio.offset + audio.header.headerBytes
    Swag.require(audio.header.lacing[0] == FragmentBytes and audio.header.sequence == 2)

    var firstPart: Array'u8
    firstPart.add(flac.toSlice()[audio.offset until audio.offset + Ogg.PageHeaderSize])
    firstPart[5]  = 0
    firstPart[26] = 1
    for index in 8 do
        firstPart[6 + index] = 0xFF
    firstPart.add(255)
    firstPart.add(flac.toSlice()[body until body + FragmentBytes])
    oggRefreshTestChecksum(&firstPart)

    var lastPart: Array'u8
    lastPart.add(flac.toSlice()[audio.offset until audio.offset + Ogg.PageHeaderSize])
    lastPart[5]  |= Ogg.ContinuedPacket
    lastPart[18] += 1
    lastPart[26] -= 1
    lastPart.add(flac.toSlice()[audio.offset + Ogg.PageHeaderSize + 1 until body])
    lastPart.add(flac.toSlice()[body + FragmentBytes until audio.offset + audio.bytes])
    oggRefreshTestChecksum(&lastPart)

    let other      = expect File.readAllBytes(audioGetTestDataPath("vorbis-stereo-44100.ogg"))
    let firstOther = expect oggTestPage(other.toSlice(), 0)
    var mixed: Array'u8
    mixed.add(flac.toSlice()[until firstFlac.bytes])
    mixed.add(other.toSlice()[until firstOther.bytes])
    mixed.add(flac.toSlice()[firstFlac.bytes until audio.offset])
    mixed.add(firstPart.toSlice())
    mixed.add(other.toSlice()[firstOther.bytes to])
    mixed.add(lastPart.toSlice())

    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("audio-ogg-flac-split-%.oga", Guid64.random()))
    defer discard catch File.delete(path)
    expect File.writeAllBytes(path, mixed.toSlice())
    let decoded = expect SoundFile.load(path)
    let native  = expect SoundFile.load(audioGetTestDataPath("flac-stereo-44100.flac"))
    Swag.require(Slice.equals((expect oggDecodePcm16(&decoded)).toSlice(), (expect oggDecodePcm16(&native)).toSlice()))
}

// Header and audio packets may share an Ogg page; indexing and decoding retain every audio packet.
#test
{
    const HeaderPage = 1'u64
    const AudioPage  = 2'u64

    let opusSource = expect File.readAllBytes(audioGetTestDataPath("opus-stereo-48000.opus").toString())
    let opusMerged = expect oggMoveAudioPageAfterHeaders(opusSource.toSlice(), HeaderPage, AudioPage)
    let opusPath   = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                                  Format.toString("audio-ogg-opus-headers-%.opus", Guid64.random()).toString())
    defer discard catch File.delete(opusPath.toString())
    expect File.writeAllBytes(opusPath.toString(), opusMerged.toSlice())
    var opusSound = expect SoundFile.load(opusPath.toString())
    Swag.require(opusSound.sampleFrameCount() == 48_000)
    let opusDecoded = expect oggDecodePcm16(&opusSound)
    Swag.require(opusDecoded.count == 48_000 * 2)
    let opusExpected = expect File.readAllBytes(audioGetTestDataPath("opus-stereo-48000.pcm").toString())
    oggAssertMatchesPcm(opusDecoded.toSlice(), opusExpected.toSlice())

    let vorbisSource = expect File.readAllBytes(audioGetTestDataPath("vorbis-stereo-44100.ogg").toString())
    let vorbisMerged = expect oggMoveAudioPageAfterHeaders(vorbisSource.toSlice(), HeaderPage, AudioPage)
    let vorbisPath   = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                                    Format.toString("audio-ogg-vorbis-headers-%.ogg", Guid64.random()).toString())
    defer discard catch File.delete(vorbisPath.toString())
    expect File.writeAllBytes(vorbisPath.toString(), vorbisMerged.toSlice())
    var vorbisSound = expect SoundFile.load(vorbisPath.toString())
    Swag.require(vorbisSound.sampleFrameCount() == 44_160)
    let vorbisDecoded = expect oggDecodePcm16(&vorbisSound)
    Swag.require(vorbisDecoded.count == 44_160 * 2)
    let vorbisExpected = expect File.readAllBytes(audioGetTestDataPath("vorbis-stereo-44100.pcm").toString())
    oggAssertMatchesPcm(vorbisDecoded.toSlice(), vorbisExpected.toSlice())
}

// An inconsistent continuation flag is invalid even when the page checksum is correct.
#test
{
    let source = expect File.readAllBytes(audioGetTestDataPath("opus-stereo-48000.opus").toString())
    let broken = expect oggSetUnexpectedContinuation(source.toSlice())
    let path   = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                              Format.toString("audio-ogg-continuation-%.opus", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    expect File.writeAllBytes(path.toString(), broken.toSlice())

    var rejected: Swag.Error
    discard catch SoundFile.load(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

// Header pages of one Ogg stream must have consecutive sequence numbers too.
#test
{
    let source = expect File.readAllBytes(audioGetTestDataPath("vorbis-stereo-44100.ogg").toString())
    let broken = expect oggSetHeaderSequenceGap(source.toSlice())
    let path   = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                              Format.toString("audio-ogg-header-sequence-%.ogg", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    expect File.writeAllBytes(path.toString(), broken.toSlice())

    var rejected: Swag.Error
    discard catch SoundFile.load(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

// Header pages must carry the continuation flag only when the previous page ends mid-packet.
#test
{
    let source = expect File.readAllBytes(audioGetTestDataPath("opus-stereo-48000.opus").toString())
    let broken = expect oggSetUnexpectedHeaderContinuation(source.toSlice())
    let path   = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                              Format.toString("audio-ogg-header-continuation-%.opus", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    expect File.writeAllBytes(path.toString(), broken.toSlice())

    var rejected: Swag.Error
    discard catch SoundFile.load(path.toString()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}
