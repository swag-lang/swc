#global internal

using Core

// Returns whether the file is a RIFF container, in either of the two byte orders it exists in.
//
// One walker covers WAV, AVI, WebP, ANI and every other format built on the same chunk chain, which
// is what the container was designed for.
func isRiffContainer(image: *BinaryImage)->bool
{
    return image.matches(0, "RIFF") or image.matches(0, "RIFX") or image.matches(0, "RF64")
}

// Adds the chunk chain of a RIFF container, including the chunks nested inside its lists.
func reportRiffContainer(image: *BinaryImage, report: *BinaryReport)
{
    // `RIFX` is the same container written the other way round; everything else about it is equal.
    image.bigEndian = image.matches(0, "RIFX")

    let s      = binStrings()
    let size   = cast(u64) image.u32At(4)
    let form   = image.fixedTextAt(8, 4)
    let stored = StrConv.toDisplaySize(size)

    report.beginGroup(s.riff_Container, form.toString(), stored.toString(), offset: 0, length: Math.min(size + 8, image.bytes.count), open: true)
    report.field(0, 4, "Signature", image.fixedTextAt(0, 4).toString())
    report.sizeField(4, 4, "Size", size)
    report.field(8, 4, s.riff_Form, form.toString())
    report.endGroup()

    let end   = Math.min(12 + size, image.bytes.count)
    let count = reportRiffChunks(image, report, 12, end, open: true)

    let counted = countText(count, s.word_Chunk, s.word_Chunks)
    report.formatName = Format.toString("RIFF %", form)
    report.summary    = Format.toString("% · %", report.formatName, counted)
}

// Adds the chunks between `at` and `end`, and returns how many there were.
private func reportRiffChunks(image: *BinaryImage, report: *BinaryReport, at, end: u64, open: bool)->u64
{
    let s     = binStrings()
    var scan  = at
    var count = 0'u64

    report.beginGroup(s.riff_Chunks, "", "", offset: at, length: end > at ? end - at : 0, open: open)

    while scan + 8 <= end and count < BinaryListLimit
    {
        let id     = image.fixedTextAt(scan, 4)
        let size   = cast(u64) image.u32At(scan + 4)
        let bodyAt = scan + 8
        let stored = StrConv.toDisplaySize(size)
        if size > end - bodyAt do
            break

        // A list is a chunk whose payload begins with the form it holds, then more chunks.
        if id == "LIST" or id == "RIFF"
        {
            let form = image.fixedTextAt(bodyAt, 4)
            report.beginGroup(id.toString(), form.toString(), stored.toString(), offset: bodyAt, length: size)
            discard reportRiffChunks(image, report, bodyAt + 4, bodyAt + size, open: false)
            report.endGroup()
        }
        else
        {
            report.beginGroup(id.toString(), stored.toString(), "", offset: bodyAt, length: size)
            report.sizeField(scan + 4, 4, "Size", size)
            reportRiffKnownChunk(image, report, id.toString(), bodyAt, size)
            report.endGroup()
        }

        count += 1

        // Every chunk starts on an even offset, so an odd payload is followed by one padding byte
        // that belongs to no chunk.
        scan = bodyAt + size + (size & 1)
    }

    report.listCut(count, count)
    report.endGroup()
    return count
}

// Adds the fields of the few chunks whose content is a header rather than a payload.
private func reportRiffKnownChunk(image: *BinaryImage, report: *BinaryReport, id: string, at, size: u64)
{
    // A chunk identifier is four bytes padded with blanks, and those blanks were trimmed off when
    // it was read, so `fmt ` arrives here as `fmt`.
    if id == "fmt" and size >= 16
    {
        let format   = image.u16At(at)
        let channels = image.u16At(at + 2)
        report.numField(at, 2, "wFormatTag", cast(u64) format, riffWaveFormatName(format))
        report.numField(at + 2, 2, "nChannels", cast(u64) channels)
        report.numField(at + 4, 4, "nSamplesPerSec", cast(u64) image.u32At(at + 4))
        report.numField(at + 8, 4, "nAvgBytesPerSec", cast(u64) image.u32At(at + 8))
        report.numField(at + 12, 2, "nBlockAlign", cast(u64) image.u16At(at + 12))
        report.numField(at + 14, 2, "wBitsPerSample", cast(u64) image.u16At(at + 14))
        return
    }

    if id == "avih" and size >= 40
    {
        report.numField(at, 4, "dwMicroSecPerFrame", cast(u64) image.u32At(at))
        report.numField(at + 16, 4, "dwTotalFrames", cast(u64) image.u32At(at + 16))
        report.numField(at + 24, 4, "dwStreams", cast(u64) image.u32At(at + 24))
        report.numField(at + 32, 4, "dwWidth", cast(u64) image.u32At(at + 32))
        report.numField(at + 36, 4, "dwHeight", cast(u64) image.u32At(at + 36))
        return
    }

    // Every text chunk of the `INFO` list is exactly a string, and those are what a reader is
    // actually looking for in a media file.
    if size and size <= 512 and id[0] == 'I'u8
    {
        let text = image.fixedTextAt(at, size)
        if !text.isEmpty() do
            report.field(at, size, "Text", text.toString())
    }
}

// Returns the encoding a WAVE format tag names.
private func riffWaveFormatName(value: u16)->string
{
    switch value
    {
    case 1:      return "PCM"
    case 2:      return "ADPCM"
    case 3:      return "IEEE float"
    case 6:      return "A-law"
    case 7:      return "mu-law"
    case 17:     return "IMA ADPCM"
    case 85:     return "MPEG layer 3"
    case 0xFFFE: return "extensible"
    }

    return "?"
}
