#global internal

using Core

// Signatures the three records a reader needs are found by.
private const ZipEndSignature = 0x06054B50'u32
private const ZipEntrySignature = 0x02014B50'u32
private const ZipZip64LocatorSignature = 0x07064B50'u32

// How far back the trailing record is looked for. It sits at the very end unless the archive
// carries a comment, and a comment is bounded by the sixteen bits that measure it.
private const ZipEndSearch = 0xFFFF + 22'u64

// Returns whether the file is a ZIP archive, whatever the container built on top of it is called.
//
// A jar, an apk, an epub, a wheel and every current office document are ZIP archives with an
// agreed-upon set of members, so the same reader takes all of them apart.
func isZipArchive(image: *BinaryImage)->bool
{
    image.bigEndian = false
    if image.matches(0, "PK\x03\x04") or image.matches(0, "PK\x05\x06") or image.matches(0, "PK\x07\x08") do
        return true
    return zipEndAt(image) != Swag.U64.Max
}

// Returns the compression a method number names.
func zipMethodName(value: u16)->string
{
    switch value
    {
    case 0:  return "store"
    case 1:  return "shrink"
    case 6:  return "implode"
    case 8:  return "deflate"
    case 9:  return "deflate64"
    case 12: return "bzip2"
    case 14: return "lzma"
    case 20: return "zstd"
    case 93: return "zstd"
    case 95: return "xz"
    case 96: return "jpeg"
    case 97: return "wavpack"
    case 98: return "ppmd"
    case 99: return "aes"
    }

    return "?"
}

// Adds the index a ZIP archive keeps of itself, and every entry that index names.
//
// Nothing is decompressed: the central directory is the whole of what an archive says it holds, and
// reading it is what tells a reader whether opening the archive is worth it at all.
func reportZipArchive(image: *BinaryImage, report: *BinaryReport)
{
    image.bigEndian = false

    let s     = binStrings()
    let endAt = zipEndAt(image)
    if endAt == Swag.U64.Max
    {
        report.note(s.zip_NoDirectory)
        report.formatName = String.from("ZIP")
        report.summary    = String.from(s.zip_NoDirectory)
        return
    }

    let declared   = cast(u64) image.u16At(endAt + 10)
    let size       = cast(u64) image.u32At(endAt + 12)
    let at         = cast(u64) image.u32At(endAt + 16)
    let commentLen = cast(u64) image.u16At(endAt + 20)

    report.beginGroup(s.zip_End, "PK\x05\x06", "", offset: endAt, length: 22 + commentLen, open: true)
    report.numField(endAt + 4, 2, "DiskNumber", cast(u64) image.u16At(endAt + 4))
    report.numField(endAt + 10, 2, "TotalEntries", declared)
    report.sizeField(endAt + 12, 4, "DirectorySize", size)
    report.hexField(endAt + 16, 4, "DirectoryOffset", at)

    if commentLen
    {
        let comment = image.fixedTextAt(endAt + 22, Math.min(commentLen, 512'u64))
        report.field(endAt + 22, commentLen, s.zip_Comment, comment.toString())
    }

    // A Zip64 locator sits immediately in front of the record when the archive outgrew the fields
    // above, so the numbers they carry are placeholders rather than the truth.
    if endAt >= 20 and image.u32At(endAt - 20) == ZipZip64LocatorSignature do
        report.hexField(endAt - 20 + 8, 8, s.zip_Zip64, image.u64At(endAt - 20 + 8))
    report.endGroup()

    reportZipEntries(image, report, at, size, declared)
}

private func reportZipEntries(image: *BinaryImage, report: *BinaryReport, at, size, declared: u64)
{
    let s     = binStrings()
    let end   = at + size
    let total = countText(declared, s.word_Entry, s.word_Entries)

    report.beginGroup(s.zip_Directory, total.toString(), s.zip_DirectoryDesc, offset: at, length: size, open: true)

    var scan     = at
    var shown    = 0'u64
    var packed   = 0'u64
    var unpacked = 0'u64

    while scan + 46 <= end and shown < BinaryListLimit
    {
        if image.u32At(scan) != ZipEntrySignature do
            break

        let flags      = image.u16At(scan + 8)
        let method     = image.u16At(scan + 10)
        let crc        = image.u32At(scan + 16)
        let compressed = cast(u64) image.u32At(scan + 20)
        let plain      = cast(u64) image.u32At(scan + 24)
        let nameLen    = cast(u64) image.u16At(scan + 28)
        let extraLen   = cast(u64) image.u16At(scan + 30)
        let commentLen = cast(u64) image.u16At(scan + 32)
        let localAt    = cast(u64) image.u32At(scan + 42)
        let name       = image.fixedTextAt(scan + 46, Math.min(nameLen, 512'u64))
        let stamp      = zipTimeText(image.u16At(scan + 14), image.u16At(scan + 12))
        let stored     = StrConv.toDisplaySize(compressed)

        packed   += compressed
        unpacked += plain

        // A name that ends in a separator is a folder the archive recorded rather than a payload,
        // and it has no bytes anywhere to point at.
        let folder = nameLen and (name.toString()[nameLen - 1] == '/'u8 or name.toString()[nameLen - 1] == '\\'u8)
        report.beginGroup(name.toString(), folder ? s.zip_Folder : stored.toString(), zipMethodName(method), offset: folder ? Swag.U64.Max : localAt, length: folder ? 0 : compressed + 30 + nameLen)

        report.field(scan + 12, 4, "Modified", stamp.toString())
        report.numField(scan + 10, 2, s.zip_Method, cast(u64) method, zipMethodName(method))
        report.hexField(scan + 16, 4, "CRC-32", cast(u64) crc)
        report.sizeField(scan + 20, 4, "CompressedSize", compressed)
        report.sizeField(scan + 24, 4, "UncompressedSize", plain)
        report.hexField(scan + 42, 4, "LocalHeaderOffset", localAt)
        report.hexField(scan + 8, 2, "Flags", cast(u64) flags, flags & 1 ? s.zip_Encrypted : "")
        report.hexField(scan + 38, 4, "ExternalAttributes", cast(u64) image.u32At(scan + 38))

        if plain and !folder
        {
            let ratio = Format.toString(s.zip_Ratio, compressed * 100 / plain)
            report.derived(s.zip_Ratio, ratio.toString())
        }

        report.endGroup()
        shown += 1
        scan  += 46 + nameLen + extraLen + commentLen
    }

    report.listCut(shown, declared)
    report.endGroup()

    let counted = countText(declared, s.word_Entry, s.word_Entries)
    report.formatName = String.from("ZIP")
    if unpacked
    {
        let ratio = Format.toString(s.zip_Ratio, packed * 100 / unpacked)
        report.summary = Format.toString("ZIP · % · %", counted, ratio)
        return
    }

    report.summary = Format.toString("ZIP · %", counted)
}

// Returns where the trailing record starts, searching backwards from the end of what was loaded.
private func zipEndAt(image: *BinaryImage)->u64
{
    if image.bytes.count < 22 do
        return Swag.U64.Max

    let last  = image.bytes.count - 22
    let limit = last > ZipEndSearch ? last - ZipEndSearch : 0
    var scan  = last

    while true
    {
        if image.u32At(scan) == ZipEndSignature do
            return scan
        if scan == limit do
            return Swag.U64.Max
        scan -= 1
    }

    return Swag.U64.Max
}

// Returns the calendar time the two packed DOS words name.
private func zipTimeText(date, time: u16)->String
{
    if !date do
        return String.from(BinaryNoValue)
    return Format.toString("%-%{02}-%{02} %{02}:%{02}:%{02}", 1980 + (date >> 9), (date >> 5) & 0xF, date & 0x1F, time >> 11, (time >> 5) & 0x3F, (time & 0x1F) * 2)
}
