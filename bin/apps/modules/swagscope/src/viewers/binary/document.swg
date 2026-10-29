#global internal
#global namespace Viewers.Binary

using Core

// Bytes an entropy estimate is taken over. Byte disorder is a property of the whole file, and a
// quarter of a megabyte says as much about it as ten do.
private const EntropySample = 256 * 1024'u64

// Formats this viewer takes apart rather than merely identifies.
enum FormatKind
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
    Midi           // A Standard MIDI File.
    Font           // An sfnt font or a collection of them.
    Scc            // A Swag Chunk Container.
    Icon           // A Windows icon containing one or more image resources.
    Png            // A PNG image, read as its chunk chain.
}

// One opened file and everything that could be extracted from it.
struct Document
{
    image:    BinaryImage
    report:   Report
    previews: Array'Preview
    kind:     FormatKind
    opened:   bool
}

impl Document
{
    // Reads `fileName`, recognizes it, and extracts everything its format allows.
    //
    // Returns false only when the file could not be read at all: a file no reader claims still
    // produces a report, because what a binary is can be worth as much as what it contains.
    mtd open(fileName: string)->bool
    {
        .report.rows.clear()
        .report.overview = {}
        .previews.clear()
        .report.level = 0
        .opened       = .image.load(fileName)
        if not .opened do
            return false

        // Recognition reads past the end of a short file on purpose, so what it learned about the
        // bytes is dropped before the chosen reader starts: only the reader's own short reads are
        // worth telling the reader about.
        .kind = detectFormat(&.image)
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
        case .Midi:       reportMidiFile(&.image, &.report)
        case .Font:       reportSfntFont(&.image, &.report)
        case .Scc:        reportSccContainer(&.image, &.report, fileName)
        case .Icon:       reportIconContainer(&.image, &.report, &.previews)
        case .Png:        reportPngImage(&.image, &.report)
        case .Unknown:    reportUnknown(&.image, &.report)
        }

        if .kind == .Scc do
            loadSccImagePreviews(fileName, &.previews)

        Swag.assert(.report.level == 0, "a format reader left a group open")
        .prependFileSummary()
        .report.overview.strings = .countStrings()

        // Reports and previews own everything they retain. Keep the mapping for offset-driven
        // inspection, but stop charging the complete scanned prefix to the process working set.
        File.MappedRegion.releasePages(.image.bytes)
        return true
    }

    // Puts what the file is in front of what it contains.
    //
    // The format readers name the format as they go, so the summary can only be written once they
    // are done — and it still has to be read first.
    private mtd prependFileSummary()
    {
        let texts = texts()

        var head: Report
        head.beginGroup(texts.rep_File, .report.formatName, .report.summary, offset: 0, length: .image.fileSize, open: true)

        let size = StrConv.toDisplaySize(.image.fileSize)
        head.derived(texts.rep_Size, size)

        if .image.isBounded()
        {
            let read = StrConv.toDisplaySize(.image.bytes.count)
            head.derived(texts.rep_Read, read, texts.rep_Bounded)
        }

        // The bytes and their printable rendering go in separate lanes: together they are wider
        // than any column, and a signature cut in half says nothing.
        let magic = .signatureText()
        if not magic.isEmpty()
        {
            let readable = .signatureAsText()
            head.field(0, Math.min(.image.bytes.count, 16'u64), texts.rep_FirstBytes, magic, readable)
        }

        if .image.bytes.count
        {
            let entropy = .entropy()
            let value   = Format.toString("%{f2} / 8", entropy)
            .report.overview.entropy = entropy
            var entropyLabel: string
            if entropy > 7.2 do
                entropyLabel = texts.rep_EntropyHigh
            elif entropy > 5 do
                entropyLabel = texts.rep_EntropyMid
            else do
                entropyLabel = texts.rep_EntropyLow
            head.derived(texts.rep_Entropy, value, entropyLabel)
        }

        if .image.truncated do
            head.note(texts.rep_Truncated)
        head.endGroup()

        .report.rows.insertAt(0, head.rows.toSlice())
    }

    // Returns the leading bytes as the hexadecimal a signature is quoted in.
    private mtd const signatureText()->String
    {
        let count = Math.min(.image.bytes.count, 16'u64)
        if not count do
            return {}

        var text: Array'u8
        text.reserve(count * 3)
        for index in count
        {
            let value  = .image.bytes[index]
            let digits = [cast(u8, value >> 4), value & 0xF]
            if index do
                text.add(' 'u8)
            for nibble in digits do
                text.add(nibble < 10 ? '0'u8 + nibble : 'A'u8 + nibble - 10)
        }

        return cast(string, text.toSlice())
    }

    // Returns the same leading bytes as the letters a reader recognizes them by.
    private mtd const signatureAsText()->String
    {
        let count = Math.min(.image.bytes.count, 16'u64)
        if not count do
            return {}

        var text: Array'u8
        text.reserve(count)
        for index in count
        {
            let value = .image.bytes[index]
            text.add(value >= 32 and value < 127 ? value : '.'u8)
        }

        return cast(string, text.toSlice())
    }

    // Returns how many runs of at least `StringLength` printable ASCII bytes the loaded bytes hold.
    //
    // It is the reading `strings` gives: names, messages and paths a binary carries in clear.
    private mtd const countStrings()->u64
    {
        const StringLength = 5'u64

        var result = 0'u64
        var run    = 0'u64
        for value in .image.bytes
        {
            if value >= 32 and value < 127
            {
                run += 1
                if run == StringLength do
                    result += 1
            }
            else
            {
                run = 0
            }
        }

        return result
    }

    // Returns the Shannon entropy of the beginning of the file, in bits per byte.
    //
    // It is the cheapest reading that separates a packed or encrypted payload from a structured
    // one, which is exactly the question a reader has about a binary nothing else explains.
    private mtd const entropy()->f32
    {
        let count = Math.min(.image.bytes.count, EntropySample)
        if not count do
            return 0

        var histogram: [256] u32
        for index in count do
            histogram[.image.bytes[index]] += 1

        var result = 0'f32
        for slot in 256 where histogram[slot]
        {
            let share = cast(f32, histogram[slot]) / cast(f32, count)
            result -= share * Math.log2(share)
        }

        return result
    }
}

// Returns which reader claims the file, by what it begins with rather than by how it is named.
//
// A viewer is opened on whatever the reader dropped on it, and an extension is a hint the file
// itself never agreed to. Content decides; the viewer index only decides which files are offered
// this view by default.
func detectFormat(image: *BinaryImage)->FormatKind
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
    if isMidiFile(image) do
        return .Midi
    if isSfntFont(image) do
        return .Font
    if isPngImage(image) do
        return .Png

    // A ZIP is recognized by the record at its end as well as by the one at its start, so it is
    // asked last: a file that begins with something more specific is that thing first.
    if isZipArchive(image) do
        return .Zip
    if isCoffObject(image) do
        return .CoffObject
    return .Unknown
}

// One file signature and the format it names.
private struct Signature
{
    offset: u64
    magic:  const [..] u8
    name:   string
}

// Signatures that hold bytes above 0x7F are written as bytes: in a string, such an escape names a
// code point, which is two bytes once encoded.
private const GzipMagic:     [2] u8 = [0x1F, 0x8B]
private const XzMagic:       [5] u8 = [0xFD, 0x37, 0x7A, 0x58, 0x5A]
private const ZstdMagic:     [4] u8 = [0x28, 0xB5, 0x2F, 0xFD]
private const SevenZipMagic: [6] u8 = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
private const OleMagic:      [4] u8 = [0xD0, 0xCF, 0x11, 0xE0]
private const JpegMagic:     [3] u8 = [0xFF, 0xD8, 0xFF]
private const MatroskaMagic: [4] u8 = [0x1A, 0x45, 0xDF, 0xA3]
private const JavaMagic:     [4] u8 = [0xCA, 0xFE, 0xBA, 0xBE]

// Adds what can be said about a file no reader takes apart.
//
// Identifying it is still worth doing: a reader who opened a `.bin` wants to know it is a ZIP
// before anything else, and the entropy above says whether looking further is even worth it.
func reportUnknown(image: *BinaryImage, report: *Report)
{
    let texts = texts()
    let name  = signatureName(image)
    if not name.isEmpty()
    {
        report.summary    = Format.toString("% · %", name, StrConv.toDisplaySize(image.fileSize))
        report.formatName = #move name
        return
    }

    report.formatName = texts.rep_Unknown
    report.summary    = image.fileSize ? texts.rep_UnknownDesc : texts.rep_Empty
}

// Returns the name, in the active language, of the format a file's leading bytes belong to, or an
// empty name.
//
// These are the containers a binary viewer is most often pointed at by mistake. Nothing here is
// taken apart; naming it is what lets a reader stop looking.
func signatureName(image: *BinaryImage)->String
{
    let texts      = texts()
    let signatures = [Signature{0, GzipMagic, texts.sig_Gzip},
                      Signature{0, "BZh", texts.sig_Bzip2},
                      Signature{0, XzMagic, texts.sig_Xz},
                      Signature{0, ZstdMagic, texts.sig_Zstd},
                      Signature{0, SevenZipMagic, texts.sig_SevenZip},
                      Signature{0, "Rar!", texts.sig_Rar},
                      Signature{0, "MSCF", texts.sig_Cabinet},
                      Signature{0, OleMagic, texts.sig_Ole},
                      Signature{257, "ustar", texts.sig_Tar},
                      Signature{0, "%PDF-", texts.sig_Pdf},
                      Signature{0, "%!PS", texts.sig_PostScript},
                      Signature{0, "GIF8", texts.sig_Gif},
                      Signature{0, JpegMagic, texts.sig_Jpeg},
                      Signature{0, "BM", texts.sig_Bmp},
                      Signature{0, "II*\0", texts.sig_Tiff},
                      Signature{0, "MM\0*", texts.sig_Tiff},
                      Signature{0, "OggS", texts.sig_Ogg},
                      Signature{0, "fLaC", texts.sig_Flac},
                      Signature{0, "ID3", texts.sig_Mp3},
                      Signature{0, MatroskaMagic, texts.sig_Matroska},
                      Signature{4, "ftyp", texts.sig_IsoMedia},
                      Signature{0, JavaMagic, texts.sig_JavaClass},
                      Signature{0, "dex\n", texts.sig_Dalvik},
                      Signature{0, "SQLite format 3", texts.sig_Sqlite},
                      Signature{0, "Microsoft C/C++ MSF 7.00", texts.sig_Pdb},
                      Signature{0, "wOF2", texts.sig_Woff2},
                      Signature{0, "wOFF", texts.sig_Woff}]

    for signature in signatures where image.matches(signature.offset, signature.magic) do
        return signature.name
    return {}
}
