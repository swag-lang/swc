#global internal

using Core, Pixel

// Bytes an entropy estimate is taken over. Byte disorder is a property of the whole file, and a
// quarter of a megabyte says as much about it as ten do.
private const BinaryEntropySample = 256 * 1024'u64

// Formats this viewer takes apart rather than merely identifies.
enum BinaryFormatKind
{
    Unknown        // Nothing claimed the file; it is identified and measured only.
    PeImage        // A Windows executable, library, or driver.
    CoffObject     // A compiled object with no image header.
    Archive        // A static or import library.
    Elf            // An ELF executable, shared object, or object.
    MachO          // A Mach-O image, or a universal wrapper around several.
    Wasm           // A WebAssembly module.
    Zip            // A ZIP archive, whatever the container built on it is called.
    Riff           // A RIFF container such as WAV, AVI, or WebP.
    Font           // An sfnt font or a collection of them.
    Scc            // A Swag Chunk Container.
    Icon           // A Windows icon containing one or more image resources.
}

// One image understood inside a binary container, with the short label shown under it.
struct BinaryPreview
{
    image: Image
    label: String
}

// One opened file and everything that could be extracted from it.
struct BinaryDocument
{
    image:    BinaryImage
    report:   BinaryReport
    previews: Array'BinaryPreview
    kind:     BinaryFormatKind
    opened:   bool
}

impl BinaryDocument
{
    // Reads `fileName`, recognizes it, and extracts everything its format allows.
    //
    // Returns false only when the file could not be read at all: a file no reader claims still
    // produces a report, because what a binary is can be worth as much as what it contains.
    mtd open(fileName: string)->bool
    {
        .report.rows.clear()
        .previews.clear()
        .report.level = 0
        .opened       = .image.load(fileName)
        if !.opened do
            return false

        // Recognition reads past the end of a short file on purpose, so what it learned about the
        // bytes is dropped before the chosen reader starts: only the reader's own short reads are
        // worth telling the reader about.
        .kind            = detectBinaryFormat(&.image)
        .image.truncated = false

        switch .kind
        {
        case .PeImage:    reportPeImage(&.image, &.report)
        case .CoffObject: reportCoffObject(&.image, &.report)
        case .Archive:    reportArchive(&.image, &.report)
        case .Elf:        reportElfImage(&.image, &.report)
        case .MachO:      reportMachO(&.image, &.report)
        case .Wasm:       reportWasmModule(&.image, &.report)
        case .Zip:        reportZipArchive(&.image, &.report)
        case .Riff:       reportRiffContainer(&.image, &.report)
        case .Font:       reportSfntFont(&.image, &.report)
        case .Scc:        reportSccContainer(&.image, &.report, fileName)
        case .Icon:       reportIconContainer(&.image, &.report, &.previews)
        case .Unknown:    reportUnknownBinary(&.image, &.report)
        }

        if .kind == .Scc do
            loadSccImagePreviews(fileName, &.previews)

        Debug.assert(.report.level == 0, "a format reader left a group open")
        .prependFileSummary()
        return true
    }

    // Puts what the file is in front of what it contains.
    //
    // The format readers name the format as they go, so the summary can only be written once they
    // are done — and it still has to be read first.
    private mtd prependFileSummary()
    {
        let s = binStrings()

        var head: BinaryReport
        head.beginGroup(s.rep_File, .report.formatName.toString(), .report.summary.toString(), offset: 0, length: .image.fileSize, open: true)

        let size = StrConv.toDisplaySize(.image.fileSize)
        head.derived(s.rep_Size, size.toString())

        if .image.isBounded()
        {
            let read = StrConv.toDisplaySize(.image.bytes.count)
            head.derived(s.rep_Read, read.toString(), s.rep_Bounded)
        }

        // The bytes and their printable rendering go in separate lanes: together they are wider
        // than any column, and a signature cut in half says nothing.
        let magic = .signatureText()
        if !magic.isEmpty()
        {
            let readable = .signatureAsText()
            head.field(0, Math.min(.image.bytes.count, 16'u64), s.rep_FirstBytes, magic.toString(), readable.toString())
        }

        if .image.bytes.count
        {
            let entropy = .entropy()
            let value   = Format.toString("%{f2} / 8", entropy)
            head.derived(s.rep_Entropy, value.toString(), entropy > 7.2 ? s.rep_EntropyHigh : (entropy > 5 ? s.rep_EntropyMid : s.rep_EntropyLow))
        }

        if .image.truncated do
            head.note(s.rep_Truncated)
        head.endGroup()

        .report.rows.insertAt(0, head.rows.toSlice())
    }

    // Returns the leading bytes as the hexadecimal a signature is quoted in.
    private mtd const signatureText()->String
    {
        let count = Math.min(.image.bytes.count, 16'u64)
        if !count do
            return {}

        var text: Array'u8
        text.reserve(count * 3)
        for index in count
        {
            let value  = .image.bytes[index]
            let digits = [cast(u8) (value >> 4), value & 0xF]
            if index do
                text.add(' 'u8)
            for nibble in digits do
                text.add(nibble < 10 ? '0'u8 + nibble : 'A'u8 + nibble - 10)
        }

        return String.from(@mkstring(text.buffer!, text.count))
    }

    // Returns the same leading bytes as the letters a reader recognizes them by.
    private mtd const signatureAsText()->String
    {
        let count = Math.min(.image.bytes.count, 16'u64)
        if !count do
            return {}

        var text: Array'u8
        text.reserve(count)
        for index in count
        {
            let value = .image.bytes[index]
            text.add(value >= 32 and value < 127 ? value : '.'u8)
        }

        return String.from(@mkstring(text.buffer!, text.count))
    }

    // Returns the Shannon entropy of the beginning of the file, in bits per byte.
    //
    // It is the cheapest reading that separates a packed or encrypted payload from a structured
    // one, which is exactly the question a reader has about a binary nothing else explains.
    private mtd const entropy()->f32
    {
        let count = Math.min(.image.bytes.count, BinaryEntropySample)
        if !count do
            return 0

        var histogram: [256] u32
        for index in count do
            histogram[.image.bytes[index]] += 1

        var result = 0'f32
        for slot in 256 where histogram[slot]
        {
            let share = cast(f32) histogram[slot] / cast(f32) count
            result -= share * Math.log2(share)
        }

        return result
    }
}

// Returns which reader claims the file, by what it begins with rather than by how it is named.
//
// A viewer is opened on whatever the reader dropped on it, and an extension is a hint the file
// itself never agreed to. Content decides; the plugin index only decides which files are offered
// this view by default.
func detectBinaryFormat(image: *BinaryImage)->BinaryFormatKind
{
    if isIconContainer(image) do
        return .Icon
    if isSccContainer(image) do
        return .Scc
    if isArchive(image) do
        return .Archive
    if isElfImage(image) do
        return .Elf
    if isPeImage(image) do
        return .PeImage
    if isMachO(image) do
        return .MachO
    if isWasmModule(image) do
        return .Wasm
    if isRiffContainer(image) do
        return .Riff
    if isSfntFont(image) do
        return .Font

    // A ZIP is recognized by the record at its end as well as by the one at its start, so it is
    // asked last: a file that begins with something more specific is that thing first.
    if isZipArchive(image) do
        return .Zip
    if isCoffObject(image) do
        return .CoffObject
    return .Unknown
}

// One file signature and the format it names.
private struct BinarySignature
{
    offset: u64
    magic:  string
    name:   string
}

// Adds what can be said about a file no reader takes apart.
//
// Identifying it is still worth doing: a reader who opened a `.bin` wants to know it is a ZIP
// before anything else, and the entropy above says whether looking further is even worth it.
func reportUnknownBinary(image: *BinaryImage, report: *BinaryReport)
{
    let s    = binStrings()
    let name = binarySignatureName(image)

    if @countof(name)
    {
        report.formatName = String.from(name)
        let size = StrConv.toDisplaySize(image.fileSize)
        report.summary = Format.toString("% · %", name, size)
        return
    }

    report.formatName = String.from(s.rep_Unknown)
    report.summary    = String.from(image.fileSize ? s.rep_UnknownDesc : s.rep_Empty)
}

// Returns the name of the format a file's leading bytes belong to, or an empty name.
//
// These are the containers a binary viewer is most often pointed at by mistake. Nothing here is
// taken apart; naming it is what lets a reader stop looking.
func binarySignatureName(image: *BinaryImage)->string
{
    const Signatures = [BinarySignature{0, "\x1F\x8B", "gzip stream"},
                        BinarySignature{0, "BZh", "bzip2 stream"},
                        BinarySignature{0, "\xFD7zXZ", "XZ stream"},
                        BinarySignature{0, "\x28\xB5\x2F\xFD", "Zstandard stream"},
                        BinarySignature{0, "7z\xBC\xAF\x27\x1C", "7-Zip archive"},
                        BinarySignature{0, "Rar!", "RAR archive"},
                        BinarySignature{0, "MSCF", "Windows cabinet"},
                        BinarySignature{0, "\xD0\xCF\x11\xE0", "OLE compound file"},
                        BinarySignature{257, "ustar", "TAR archive"},
                        BinarySignature{0, "%PDF-", "PDF document"},
                        BinarySignature{0, "%!PS", "PostScript program"},
                        BinarySignature{0, "\x89PNG\r\n\x1A\n", "PNG image"},
                        BinarySignature{0, "GIF8", "GIF image"},
                        BinarySignature{0, "\xFF\xD8\xFF", "JPEG image"},
                        BinarySignature{0, "BM", "BMP image"},
                        BinarySignature{0, "II*\0", "TIFF image"},
                        BinarySignature{0, "MM\0*", "TIFF image"},
                        BinarySignature{0, "OggS", "Ogg stream"},
                        BinarySignature{0, "fLaC", "FLAC sound"},
                        BinarySignature{0, "ID3", "MP3 sound"},
                        BinarySignature{0, "\x1A\x45\xDF\xA3", "Matroska media container"},
                        BinarySignature{4, "ftyp", "ISO media container"},
                        BinarySignature{0, "\xCA\xFE\xBA\xBE", "Java class"},
                        BinarySignature{0, "dex\n", "Dalvik executable"},
                        BinarySignature{0, "SQLite format 3", "SQLite database"},
                        BinarySignature{0, "Microsoft C/C++ MSF 7.00", "Program database"},
                        BinarySignature{0, "wOF2", "WOFF2 font"},
                        BinarySignature{0, "wOFF", "WOFF font"}]

    for signature in Signatures where image.matches(signature.offset, signature.magic) do
        return signature.name
    return ""
}
