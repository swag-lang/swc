#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Returns the path of one immutable fixture of this test suite.
func binaryFixturePath(name: string)->String => Path.combine(scopeTestDataDirectory(), name)

// Total size of the synthesized image. Two sections of one file-alignment unit each, behind a
// header block of the same size.
internal const FixtureSize = 0x800'u64

// Where the synthesized image puts each of its parts. A fixture whose offsets are named is a
// fixture whose assertions can name them too.
const FixturePeAt   = 0x80'u64
internal const FixtureTextAt = 0x400'u64
const FixtureDataAt = 0x600'u64

// Writes `value` as `size` little-endian bytes at `at`.
func poke(bytes: *Array'u8, at, value, size: u64)
{
    for index in size do
        bytes[at + index] = cast(u8, ((value >> (index * 8)) & 0xFF))
}

// Writes `value` as `size` big-endian bytes at `at`, for the formats written that way round.
func pokeBig(bytes: *Array'u8, at, value, size: u64)
{
    for index in size do
        bytes[at + index] = cast(u8, ((value >> ((size - 1 - index) * 8)) & 0xFF))
}

// Writes `text` at `at`, leaving the byte after it as the zero the buffer already holds.
func pokeText(bytes: *Array'u8, at: u64, text: string)
{
    for index in text.count do
        bytes[at + index] = text[index]
}

// Builds a complete, self-consistent PE32+ library: two sections, one export, one import.
//
// A checked-in binary would say nothing about which byte an assertion is reading, and could not be
// changed to probe one field. Every offset here is computed from the same constants the reader
// walks, so a mistake in either shows up as a failing assertion rather than as a silent skip.
internal func buildPeFixture()->Array'u8
{
    var bytes: #returntype
    bytes.resize(FixtureSize)

    pokeText(&bytes, 0, "MZ")
    pokeText(&bytes, 0x40, "This program cannot be run in DOS mode.$")
    poke(&bytes, 0x3C, FixturePeAt, 4)

    pokeText(&bytes, FixturePeAt, "PE")
    let fileAt = FixturePeAt + 4
    poke(&bytes, fileAt, 0x8664, 2)                // Machine: x64.
    poke(&bytes, fileAt + 2, 2, 2)                 // NumberOfSections.
    poke(&bytes, fileAt + 4, 1_600_000_000, 4)     // TimeDateStamp.
    poke(&bytes, fileAt + 16, 240, 2)              // SizeOfOptionalHeader.
    poke(&bytes, fileAt + 18, 0x2022, 2)           // EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE | DLL.

    let optAt = fileAt + 20
    poke(&bytes, optAt, 0x20B, 2)                  // PE32+.
    poke(&bytes, optAt + 2, 14, 1)                 // Linker major.
    poke(&bytes, optAt + 4, 0x200, 4)              // SizeOfCode.
    poke(&bytes, optAt + 16, 0x1000, 4)            // AddressOfEntryPoint.
    poke(&bytes, optAt + 20, 0x1000, 4)            // BaseOfCode.
    poke(&bytes, optAt + 24, 0x180000000, 8)       // ImageBase.
    poke(&bytes, optAt + 32, 0x1000, 4)            // SectionAlignment.
    poke(&bytes, optAt + 36, 0x200, 4)             // FileAlignment.
    poke(&bytes, optAt + 40, 6, 2)                 // OperatingSystemVersion major.
    poke(&bytes, optAt + 48, 6, 2)                 // SubsystemVersion major.
    poke(&bytes, optAt + 56, 0x3000, 4)            // SizeOfImage.
    poke(&bytes, optAt + 60, FixtureTextAt, 4)     // SizeOfHeaders.
    poke(&bytes, optAt + 68, 3, 2)                 // Subsystem: Windows console.
    poke(&bytes, optAt + 70, 0x0160, 2)            // DYNAMIC_BASE | NX_COMPAT | HIGH_ENTROPY_VA.
    poke(&bytes, optAt + 72, 0x100000, 8)          // SizeOfStackReserve.
    poke(&bytes, optAt + 108, 16, 4)               // NumberOfRvaAndSizes.

    let dirAt = optAt + 112
    poke(&bytes, dirAt, 0x2000, 4)          // Export directory address.
    poke(&bytes, dirAt + 4, 0x80, 4)        // Export directory size.
    poke(&bytes, dirAt + 8, 0x2100, 4)      // Import directory address.
    poke(&bytes, dirAt + 12, 0x28, 4)       // Import directory size.
    poke(&bytes, dirAt + 48, 0x2180, 4)     // Debug directory address.
    poke(&bytes, dirAt + 52, 28, 4)         // Debug directory size.

    let sectionAt = optAt + 240
    pokeText(&bytes, sectionAt, ".text")
    poke(&bytes, sectionAt + 8, 0x100, 4)              // VirtualSize.
    poke(&bytes, sectionAt + 12, 0x1000, 4)            // VirtualAddress.
    poke(&bytes, sectionAt + 16, 0x200, 4)             // SizeOfRawData.
    poke(&bytes, sectionAt + 20, FixtureTextAt, 4)     // PointerToRawData.
    poke(&bytes, sectionAt + 36, 0x60000020, 4)        // CNT_CODE | MEM_EXECUTE | MEM_READ.

    pokeText(&bytes, sectionAt + 40, ".rdata")
    poke(&bytes, sectionAt + 48, 0x200, 4)
    poke(&bytes, sectionAt + 52, 0x2000, 4)
    poke(&bytes, sectionAt + 56, 0x200, 4)
    poke(&bytes, sectionAt + 60, FixtureDataAt, 4)
    poke(&bytes, sectionAt + 76, 0x40000040, 4)     // CNT_INITIALIZED_DATA | MEM_READ.

    // `.rdata` starts at file offset 0x600 and is mapped at 0x2000, so an address in it is its file
    // offset plus 0x1A00.
    poke(&bytes, FixtureDataAt + 12, 0x2060, 4)     // Export Name.
    poke(&bytes, FixtureDataAt + 16, 1, 4)          // Export Base.
    poke(&bytes, FixtureDataAt + 20, 1, 4)          // NumberOfFunctions.
    poke(&bytes, FixtureDataAt + 24, 1, 4)          // NumberOfNames.
    poke(&bytes, FixtureDataAt + 28, 0x2028, 4)     // AddressOfFunctions.
    poke(&bytes, FixtureDataAt + 32, 0x202C, 4)     // AddressOfNames.
    poke(&bytes, FixtureDataAt + 36, 0x2030, 4)     // AddressOfNameOrdinals.
    poke(&bytes, FixtureDataAt + 40, 0x1000, 4)     // The one exported address.
    poke(&bytes, FixtureDataAt + 44, 0x2040, 4)     // Address of its name.
    poke(&bytes, FixtureDataAt + 48, 0, 2)          // Its ordinal, biased by Base.
    pokeText(&bytes, FixtureDataAt + 64, "swagExport")
    pokeText(&bytes, FixtureDataAt + 96, "fixture.dll")

    let importAt = FixtureDataAt + 0x100
    poke(&bytes, importAt, 0x2120, 4)                  // OriginalFirstThunk.
    poke(&bytes, importAt + 12, 0x2140, 4)             // Name.
    poke(&bytes, importAt + 16, 0x2160, 4)             // FirstThunk.
    poke(&bytes, FixtureDataAt + 0x120, 0x2150, 8)     // One lookup entry, then the zero after it.
    pokeText(&bytes, FixtureDataAt + 0x140, "KERNEL32.dll")
    poke(&bytes, FixtureDataAt + 0x150, 7, 2)     // Hint.
    pokeText(&bytes, FixtureDataAt + 0x152, "ExitProcess")
    poke(&bytes, FixtureDataAt + 0x160, 0x2150, 8)     // The bound address table.

    // One debug entry pointing at a CodeView record, which is what pairs an image with its symbol
    // file. The four fields between the version and the payload are the ones easiest to misplace,
    // so the fixture carries values that make a shift by one field visible.
    let debugAt = FixtureDataAt + 0x180
    poke(&bytes, debugAt + 4, 1_600_000_000, 4)     // TimeDateStamp.
    poke(&bytes, debugAt + 12, 2, 4)                // Type: CODEVIEW.
    poke(&bytes, debugAt + 16, 36, 4)               // SizeOfData.
    poke(&bytes, debugAt + 20, 0x21A0, 4)           // AddressOfRawData.
    poke(&bytes, debugAt + 24, FixtureDataAt + 0x1A0, 4)

    let codeViewAt = FixtureDataAt + 0x1A0
    pokeText(&bytes, codeViewAt, "RSDS")
    for index in 16 do
        bytes[codeViewAt + 4 + index] = cast(u8, index + 1)
    poke(&bytes, codeViewAt + 20, 1, 4)     // Age.
    pokeText(&bytes, codeViewAt + 24, "fixture.pdb")

    return bytes
}

// Writes `bytes` to a uniquely named temporary file and returns its path.
internal func writeFixture(name: string, bytes: const [..] u8)->String
{
    let prefix   = Format.toString("viewer_binary_%_", name)
    let fileName = Testing.tempFilePath(prefix, ".bin")
    discard expect File.writeAllBytes(fileName, bytes)
    return fileName
}

// Returns the first row carrying `label`, or `null` when the report never wrote one.
func findRow(report: const *Binary.Report, label: string)->const *Binary.Row?
{
    for row in report.rows where row.label == label do
        return row
    return null
}

func rowValue(report: const *Binary.Report, label: string)->string
{
    let row = findRow(report, label)
    return row ? row.value.toString() : ""
}

func rowDetail(report: const *Binary.Report, label: string)->string
{
    let row = findRow(report, label)
    return row ? row.detail.toString() : ""
}

func fixtureGuid(text: string)->Guid128 => expect Guid128.parse(text)

// A synthesized library is taken apart down to the symbol it imports and the one it exports.
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .PeImage)
    Swag.require(doc.report.formatName == "PE32+")
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "x64"))
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "DLL"))
    Swag.require(not doc.image.truncated)

    // The header block, read field by field.
    Swag.require(rowDetail(&doc.report, "Machine") == "x64")
    Swag.require(rowValue(&doc.report, "NumberOfSections") == "2")
    Swag.require(rowValue(&doc.report, "AddressOfEntryPoint") == "0x00001000")
    Swag.require(rowValue(&doc.report, "ImageBase") == "0x0000000180000000")
    Swag.require(rowDetail(&doc.report, "Subsystem") == "Windows console")
    Swag.require(Utf8.contains(rowDetail(&doc.report, "DllCharacteristics"), "NX_COMPAT"))
    Swag.require(Utf8.contains(rowDetail(&doc.report, "Characteristics"), "DLL"))
    Swag.require(Utf8.contains(rowDetail(&doc.report, "TimeDateStamp"), "2020-09-13"))

    // The two sections, and the one directory each of them carries.
    let text = findRow(&doc.report, ".text")
    Swag.require(text != null)
    Swag.require(text.offset == FixtureTextAt and text.length == 0x200)
    Swag.require(findRow(&doc.report, ".rdata") != null)

    let exported = findRow(&doc.report, "swagExport")
    Swag.require(exported != null)
    Swag.require(exported.value == "ordinal 1")

    let module = findRow(&doc.report, "KERNEL32.dll")
    Swag.require(module != null)
    Swag.require(module.value == "1 symbol")

    let imported = findRow(&doc.report, "ExitProcess")
    Swag.require(imported != null)
    Swag.require(imported.detail == "hint 7")

    // The debug entry names the symbol file, and the pair only holds when the identity and the age
    // both match. Reading either from the wrong field would still print something plausible.
    Swag.require(findRow(&doc.report, "CODEVIEW") != null)
    Swag.require(rowValue(&doc.report, "Type") == "2")
    Swag.require(rowValue(&doc.report, "GUID") == "04030201-0605-0807-090A-0B0C0D0E0F10")
    Swag.require(rowValue(&doc.report, "Age") == "1")
    Swag.require(rowValue(&doc.report, "PDB") == "fixture.pdb")
}

// The binary view exposes every image in an ICO instead of silently keeping only its largest one.
#test
{
    let fileName = binaryFixturePath("appicon.ico")

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Icon)
    Swag.require(doc.previews.count > 1)
    Swag.require(doc.previews[0].image.isValid())
    Swag.require(rowValue(&doc.report, "ImageCount") == "9")

    var host: Testing.HeadlessHost
    host.setup(860, 520)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 36, 36})
    var viewerSession = openTestViewer(Binary.viewerPlugin(), &host.root, fileName, actionParent: commands)
    let view          = assume cast(*Binary.Panel, viewerSession.view)
    finishBinaryViewer(&host, view)
    view.resize(860, 520)
    view.applyLayout()
    view.layoutPreviews()
    Swag.require(view.previewBand != null)
    Swag.require(view.previewBand.children.count == view.doc.previews.count)
    Swag.require(view.list.position.y >= view.previewBand.position.bottom())
    Testing.assertContentFits(view)
}

// Swag Capture's preview role is decoded after SCC deflate, using only the public container contract.
#test
{
    let pngPath = binaryFixturePath("appicon.png")
    let png     = expect File.readAllBytes(pngPath)

    let fileName = Testing.tempFilePath("viewer_binary_capture_", ".scc")
    defer discard catch File.delete(fileName)

    var writer: Scc.Writer
    writer.initialize(fixtureGuid("4a67acc2-5930-4e81-81dc-d12675bc6deb"))
    var options: Scc.ChunkOptions
    options.roleId  = fixtureGuid("9b5e375d-e615-4a80-8680-6c7c37f94ceb")
    options.codecId = Scc.deflateCodecId()
    discard expect writer.addChunk(png.toSlice(), options)
    expect writer.saveAtomic(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Scc and doc.previews.count == 1)
    Swag.require(doc.previews[0].label == "Preview" and doc.previews[0].image.isValid())
}

// A byte anywhere in the file maps back onto the innermost structure that covers it.
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_map", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)

    // A hit inside a section's payload lands on that section even though no field was decoded
    // there, because a group carries the range it covers.
    let inText = doc.report.rowAt(FixtureTextAt + 0x40)
    Swag.require(inText != Swag.U64.Max)
    Swag.require(doc.report.rows[inText].label == ".text")

    // A hit on a decoded field lands on the field rather than on the header around it.
    let onMachine = doc.report.rowAt(FixturePeAt + 4)
    Swag.require(onMachine != Swag.U64.Max)
    Swag.require(doc.report.rows[onMachine].label == "Machine")

    Swag.require(doc.report.rowAt(FixtureSize + 16) == Swag.U64.Max)
}

// The whole report leaves as text, one indented line per row.
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_text", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)

    let text = doc.report.toText()
    Swag.require(Utf8.contains(text.toSlice(), "Machine: 0x8664"))
    Swag.require(Utf8.contains(text.toSlice(), "    .text"))
    Swag.require(Utf8.contains(text.toSlice(), "ExitProcess"))
}

// An object file has no image header, and is recognized by the header it does have.
#test
{
    var bytes: Array'u8
    bytes.resize(0x100)
    poke(&bytes, 0, 0x8664, 2)     // Machine.
    poke(&bytes, 2, 1, 2)          // NumberOfSections.
    poke(&bytes, 8, 0x60, 4)       // PointerToSymbolTable.
    poke(&bytes, 12, 1, 4)         // NumberOfSymbols.
    pokeText(&bytes, 20, ".text")
    poke(&bytes, 20 + 16, 0x20, 4)     // SizeOfRawData.
    pokeText(&bytes, 0x60, "main")
    poke(&bytes, 0x60 + 16, 2, 1)     // Storage class: external.

    let fileName = writeFixture("obj", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .CoffObject)
    Swag.require(doc.report.formatName == "COFF")
    Swag.require(rowDetail(&doc.report, "Machine") == "x64")
    Swag.require(findRow(&doc.report, ".text") != null)

    let symbol = findRow(&doc.report, "main")
    Swag.require(symbol != null)
    Swag.require(Utf8.contains(symbol.detail.toSlice(), "EXTERNAL"))
}

// An archive is a directory of members before it is a container of objects.
#test
{
    var bytes: Array'u8
    bytes.resize(0x100)
    pokeText(&bytes, 0, "!<arch>\n")

    // One member of sixteen bytes, with the fixed sixty-byte header every member carries.
    pokeText(&bytes, 8, "greeting.o      ")
    pokeText(&bytes, 8 + 16, "1600000000  ")
    pokeText(&bytes, 8 + 40, "100644  ")
    pokeText(&bytes, 8 + 48, "16        ")
    pokeText(&bytes, 8 + 58, "`\n")
    pokeText(&bytes, 8 + 60, "0123456789abcde")
    bytes.resize(8 + 60 + 16)

    let fileName = writeFixture("lib", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Archive)

    let member = findRow(&doc.report, "greeting.o")
    Swag.require(member != null)
    Swag.require(member.offset == 68 and member.length == 16)
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "1 member"))
}

// A container written by the standard writer is read back through its own reader.
#test
{
    let fileName = Testing.tempFilePath("viewer_binary_scc_", ".scc")
    defer discard catch File.delete(fileName)

    var writer: Scc.Writer
    writer.initialize(Guid128.random())
    writer.manifest().name = "fixture container"
    writer.manifest().tags.add("probe")

    let payload = [1'u8, 2, 3, 4, 5, 6, 7, 8]
    discard expect writer.addChunk(payload, {})
    expect writer.saveAtomic(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Scc)
    Swag.require(doc.report.formatName == "SCC")
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "1 chunk"))
    Swag.require(rowValue(&doc.report, "FormatMajor") == "1")
    Swag.require(rowValue(&doc.report, Binary.texts().scc_Manifest) == "fixture container")
    Swag.require(rowValue(&doc.report, "StoredSize") == "0x0000000000000008 (8)")
    Swag.require(rowValue(&doc.report, Binary.texts().scc_Tags) == "probe")
}

// A Mach-O image is read down to the segment it maps and the library it needs.
#test
{
    var bytes: Array'u8
    bytes.resize(0x200)

    let segmentSize = 72 + 80'u64
    let dylibSize   = 56'u64
    poke(&bytes, 0, 0xFEEDFACF, 4)      // MH_MAGIC_64.
    poke(&bytes, 4, 0x01000007, 4)      // cputype: x86-64.
    poke(&bytes, 12, 2, 4)              // filetype: MH_EXECUTE.
    poke(&bytes, 16, 2, 4)              // ncmds.
    poke(&bytes, 20, segmentSize + dylibSize, 4)     // sizeofcmds.
    poke(&bytes, 24, 0x00200085, 4)     // NOUNDEFS | DYLDLINK | TWOLEVEL | PIE.

    let segmentAt = 32'u64
    poke(&bytes, segmentAt, 0x19, 4)     // LC_SEGMENT_64.
    poke(&bytes, segmentAt + 4, segmentSize, 4)
    pokeText(&bytes, segmentAt + 8, "__TEXT")
    poke(&bytes, segmentAt + 24, 0x100000000, 8)     // vmaddr.
    poke(&bytes, segmentAt + 32, 0x1000, 8)          // vmsize.
    poke(&bytes, segmentAt + 48, 0x1000, 8)          // filesize.
    poke(&bytes, segmentAt + 56, 5, 4)               // maxprot: READ | EXECUTE.
    poke(&bytes, segmentAt + 60, 5, 4)               // initprot.
    poke(&bytes, segmentAt + 64, 1, 4)               // nsects.

    let sectionAt = segmentAt + 72
    pokeText(&bytes, sectionAt, "__text")
    pokeText(&bytes, sectionAt + 16, "__TEXT")
    poke(&bytes, sectionAt + 32, 0x100000F00, 8)     // addr.
    poke(&bytes, sectionAt + 40, 0x40, 8)            // size.
    poke(&bytes, sectionAt + 48, 0xF00, 4)           // offset.
    poke(&bytes, sectionAt + 64, 0x80000400, 4)      // flags.

    let dylibAt = segmentAt + segmentSize
    poke(&bytes, dylibAt, 0x0C, 4)     // LC_LOAD_DYLIB.
    poke(&bytes, dylibAt + 4, dylibSize, 4)
    poke(&bytes, dylibAt + 8, 24, 4)     // Offset of the name inside the command.
    poke(&bytes, dylibAt + 16, 0x00010203, 4)     // current_version 1.2.3.
    pokeText(&bytes, dylibAt + 24, "/usr/lib/libSystem.B.dylib")

    let fileName = writeFixture("macho", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .MachO)
    Swag.require(doc.report.formatName == "Mach-O 64")
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "x86-64"))
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "MH_EXECUTE"))
    Swag.require(Utf8.contains(rowDetail(&doc.report, "flags"), "PIE"))

    let segment = findRow(&doc.report, "segname")
    Swag.require(segment != null)
    Swag.require(segment.value == "__TEXT")
    Swag.require(Utf8.contains(segment.detail.toSlice(), "EXECUTE"))

    let section = findRow(&doc.report, "__text")
    Swag.require(section != null)
    Swag.require(section.offset == 0xF00 and section.length == 0x40)

    let library = findRow(&doc.report, "name")
    Swag.require(library != null)
    Swag.require(library.value == "/usr/lib/libSystem.B.dylib")
    Swag.require(rowValue(&doc.report, "current_version") == "1.2.3")
    Swag.require(findRow(&doc.report, Binary.texts().shr_Libraries) != null)
}

// A ZIP archive is read through the index it keeps of itself, without decompressing anything.
#test
{
    let entryAt = 51'u64
    let endAt   = 106'u64

    var bytes: Array'u8
    bytes.resize(128)

    pokeText(&bytes, 0, "PK\x03\x04")
    pokeText(&bytes, 30, "hello.txt")
    pokeText(&bytes, 39, "hello world!")

    pokeText(&bytes, entryAt, "PK\x01\x02")
    poke(&bytes, entryAt + 10, 0, 2)         // Method: store.
    poke(&bytes, entryAt + 12, 25536, 2)     // 12:30:00.
    poke(&bytes, entryAt + 14, 20687, 2)     // 2020-06-15.
    poke(&bytes, entryAt + 16, 0x1C291CA3, 4)
    poke(&bytes, entryAt + 20, 12, 4)     // CompressedSize.
    poke(&bytes, entryAt + 24, 12, 4)     // UncompressedSize.
    poke(&bytes, entryAt + 28, 9, 2)      // NameLength.
    pokeText(&bytes, entryAt + 46, "hello.txt")

    pokeText(&bytes, endAt, "PK\x05\x06")
    poke(&bytes, endAt + 8, 1, 2)            // Entries on this disk.
    poke(&bytes, endAt + 10, 1, 2)           // Total entries.
    poke(&bytes, endAt + 12, 55, 4)          // DirectorySize.
    poke(&bytes, endAt + 16, entryAt, 4)     // DirectoryOffset.

    let fileName = writeFixture("zip", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Zip)
    Swag.require(doc.report.formatName == "ZIP")
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "1 entry"))

    let entry = findRow(&doc.report, "hello.txt")
    Swag.require(entry != null)
    Swag.require(entry.detail == "store")
    Swag.require(rowValue(&doc.report, "Modified") == "2020-06-15 12:30:00")
    Swag.require(rowValue(&doc.report, "UncompressedSize") == "0x0000000C (12)")
    Swag.require(rowValue(&doc.report, "TotalEntries") == "1")
}

// A WebAssembly module is a chain of sections, and the two that name things are decoded.
#test
{
    var bytes: Array'u8
    bytes.resize(64)

    pokeText(&bytes, 0, "\0asm")
    poke(&bytes, 4, 1, 4)

    // One import of `env.puts`, then one export of `memory`.
    poke(&bytes, 8, 2, 1)
    poke(&bytes, 9, 12, 1)
    poke(&bytes, 10, 1, 1)
    poke(&bytes, 11, 3, 1)
    pokeText(&bytes, 12, "env")
    poke(&bytes, 15, 4, 1)
    pokeText(&bytes, 16, "puts")
    poke(&bytes, 20, 0, 1)
    poke(&bytes, 21, 0, 1)

    poke(&bytes, 22, 7, 1)
    poke(&bytes, 23, 10, 1)
    poke(&bytes, 24, 1, 1)
    poke(&bytes, 25, 6, 1)
    pokeText(&bytes, 26, "memory")
    poke(&bytes, 32, 2, 1)
    poke(&bytes, 33, 0, 1)
    bytes.resize(34)

    let fileName = writeFixture("wasm", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Wasm)
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "2 sections"))
    Swag.require(findRow(&doc.report, "import") != null)
    Swag.require(findRow(&doc.report, "export") != null)

    let imported = findRow(&doc.report, "env.puts")
    Swag.require(imported != null)
    Swag.require(imported.detail == Binary.texts().wasm_Function)

    let exported = findRow(&doc.report, "memory")
    Swag.require(exported != null)
    Swag.require(exported.detail == Binary.texts().wasm_Memory)
}

// A RIFF container is one chunk chain, and the header chunks inside it are read as headers.
#test
{
    var bytes: Array'u8
    bytes.resize(52)

    pokeText(&bytes, 0, "RIFF")
    poke(&bytes, 4, 44, 4)
    pokeText(&bytes, 8, "WAVE")

    pokeText(&bytes, 12, "fmt ")
    poke(&bytes, 16, 16, 4)
    poke(&bytes, 20, 1, 2)         // PCM.
    poke(&bytes, 22, 2, 2)         // Channels.
    poke(&bytes, 24, 44100, 4)     // Sample rate.
    poke(&bytes, 28, 176400, 4)
    poke(&bytes, 32, 4, 2)
    poke(&bytes, 34, 16, 2)     // Bits per sample.

    pokeText(&bytes, 36, "data")
    poke(&bytes, 40, 8, 4)

    let fileName = writeFixture("riff", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Riff)
    Swag.require(doc.report.formatName == "RIFF WAVE")
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "2 chunks"))
    Swag.require(rowDetail(&doc.report, "wFormatTag") == "PCM")
    Swag.require(rowValue(&doc.report, "nChannels") == "2")
    Swag.require(rowValue(&doc.report, "nSamplesPerSec") == "44100")

    let data = findRow(&doc.report, "data")
    Swag.require(data != null)
    Swag.require(data.offset == 44 and data.length == 8)
}

// A Standard MIDI File exposes its timing, track metadata, and running-status channel events.
#test
{
    var bytes: Array'u8
    bytes.resize(22)

    pokeText(&bytes, 0, "MThd")
    pokeBig(&bytes, 4, 6, 4)
    pokeBig(&bytes, 8, 1, 2)        // Format 1.
    pokeBig(&bytes, 10, 1, 2)       // One track.
    pokeBig(&bytes, 12, 480, 2)     // Ticks per quarter note.
    pokeText(&bytes, 14, "MTrk")

    const Track = [0'u8, 0xFF, 0x03, 5, 'P'u8, 'i'u8, 'a'u8, 'n'u8, 'o'u8,
                   0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20,
                   0, 0xFF, 0x58, 4, 4, 2, 24, 8,
                   0, 0xFF, 0x59, 2, 0xFD, 1,
                   0, 0xF0, 3, 1, 2, 0xF7,
                   0, 0xC0, 40,
                   0, 0x90, 60, 96,
                   0x83, 0x60, 60, 0,
                   0, 0xFF, 0x2F, 0]
    pokeBig(&bytes, 18, Track.count, 4)
    bytes.add(Track)

    let fileName = writeFixture("midi", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Midi)
    Swag.require(doc.report.formatName == Binary.texts().midi_File)
    Swag.require(rowDetail(&doc.report, "Division") == "480 ticks per quarter note")
    Swag.require(rowValue(&doc.report, "Sequence/Track Name") == "Piano")
    Swag.require(rowValue(&doc.report, "Set Tempo") == "120 BPM")
    Swag.require(rowValue(&doc.report, "Time Signature") == "4/4")
    Swag.require(rowValue(&doc.report, "Key Signature") == "E-flat minor")
    Swag.require(findRow(&doc.report, "System Exclusive") != null)
    Swag.require(rowValue(&doc.report, "Program Change") == "40")

    let note = findRow(&doc.report, "Note On")
    Swag.require(note != null and note.value == "60 · velocity 96")
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "9 events"))
    Swag.require(not doc.image.truncated)
}

// A font is read through the directory of tables it is assembled from.
#test
{
    let headAt = 44'u64
    let nameAt = 100'u64

    var bytes: Array'u8
    bytes.resize(128)

    pokeBig(&bytes, 0, 0x00010000, 4)
    pokeBig(&bytes, 4, 2, 2)     // numTables.

    pokeText(&bytes, 12, "head")
    pokeBig(&bytes, 20, headAt, 4)
    pokeBig(&bytes, 24, 54, 4)
    pokeText(&bytes, 28, "name")
    pokeBig(&bytes, 36, nameAt, 4)
    pokeBig(&bytes, 40, 26, 4)

    pokeBig(&bytes, headAt + 18, 2048, 2)     // unitsPerEm.

    pokeBig(&bytes, nameAt + 2, 1, 2)      // One naming record.
    pokeBig(&bytes, nameAt + 4, 18, 2)     // Where the strings begin.
    pokeBig(&bytes, nameAt + 6, 1, 2)      // Platform: Macintosh, so the name is one byte per letter.
    pokeBig(&bytes, nameAt + 12, 1, 2)     // nameID: family.
    pokeBig(&bytes, nameAt + 14, 7, 2)     // Length.
    pokeBig(&bytes, nameAt + 16, 0, 2)     // Offset within the strings.
    pokeText(&bytes, nameAt + 18, "Fixtura")

    let fileName = writeFixture("font", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Font)
    Swag.require(Utf8.contains(doc.report.summary.toSlice(), "Fixtura"))
    Swag.require(rowValue(&doc.report, Binary.texts().font_UnitsPerEm) == "2048")
    Swag.require(rowValue(&doc.report, Binary.texts().font_Family) == "Fixtura")

    let table = findRow(&doc.report, "head")
    Swag.require(table != null)
    Swag.require(table.offset == headAt and table.length == 54)
}

// A file no reader claims is still named, measured, and weighed.
#test
{
    var bytes: Array'u8
    bytes.resize(64)
    pokeText(&bytes, 0, "GIF89a")

    let fileName = writeFixture("gif", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    let documentOpened = doc.open(fileName)
    Swag.require(documentOpened)
    Swag.require(doc.kind == .Unknown)
    Swag.require(doc.report.formatName == "GIF image")
    Swag.require(doc.image.region.isOpen() and doc.image.bytes.count == bytes.count)

    // A run of zeros carries no information at all, and the reading says so.
    let entropy = findRow(&doc.report, Binary.texts().rep_Entropy)
    Swag.require(entropy != null)
    Swag.require(entropy.detail == Binary.texts().rep_EntropyLow)
    Swag.require(findRow(&doc.report, Binary.texts().rep_FirstBytes) != null)
}

// A signature is compared byte for byte, those above 0x7F included.
#test
{
    var bytes: Array'u8
    bytes.resize(32)
    for value, index in [0xFF'u8, 0xD8, 0xFF] do
        bytes[index] = value

    let fileName = writeFixture("jpg", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var doc: Binary.Document
    Swag.require(doc.open(fileName) and doc.report.formatName == "JPEG image")
}

// A PNG is read as its chunk chain: each chunk a structure of its own, the image header decoded.
#test
{
    let fileName = scopeTestDataPath("title.png")

    var doc: Binary.Document
    Swag.require(doc.open(fileName) and doc.kind == .Png and doc.image.bigEndian)
    Swag.require(doc.report.formatName == "PNG" and Utf8.contains(doc.report.summary.toSlice(), "5000 × 367"))

    let header = findRow(&doc.report, "IHDR")
    Swag.require(header != null and header.offset == 8 and header.length == 25)
    Swag.require(rowValue(&doc.report, "Width") == "5000" and rowValue(&doc.report, "Colour type") == "6")
    Swag.require(findRow(&doc.report, "IEND") != null and findRow(&doc.report, Binary.texts().png_Malformed) == null)
}

// A file the reader cannot open crosses the viewer boundary without a local error view.
#test
{
    var doc: Binary.Document
    let documentOpened = doc.open("this-file-does-not-exist.bin")
    Swag.require(not documentOpened)
    Swag.require(not doc.image.failureReason.isEmpty())

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Binary.viewerPlugin(), &host.root, "this-file-does-not-exist.bin", commandParent: &host.root, actionParent: &host.root)
    Swag.require(result.view != null and
                 result.actions == null and
                 result.commands != null and
                 result.collectMatches != null and
                 result.isLoading != null)
    let view = assume cast(*Binary.Panel, result.view)
    finishBinaryViewer(&host, view)
    Swag.require(not view.failureReason.isEmpty())
}

internal func binaryCellText(line: *ListLine, column: Binary.Column)->String => RichString.plainText(line.itemAt(cast(u32, column)).name.raw)

// What leaves through the clipboard is the report a reader is looking at.
#test
{
    if not Clipboard.isFake() do
        return

    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_copy", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1100, 640)

    let view = binaryTestViewer(&host, fileName, 1100, 600)
    view.copyReport()
    let all = Clipboard.getString()
    Swag.require(Utf8.contains(all.toSlice(), "swagExport"))

    view.setExpandedAll(true)
    let revealed = view.revealOffset(FixtureTextAt)
    Swag.require(revealed)
    view.copySelectedLine()
    let one = Clipboard.getString()
    Swag.require(Utf8.contains(one.toSlice(), ".text"))
    Swag.require(not Utf8.contains(one.toSlice(), "swagExport"))
}

// Search indexes the decoded report, outlines the exact text, and reaches folded structures.
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_search", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1100, 640)

    let view = binaryTestViewer(&host, fileName, 1100, 600)
    var matches: Array'Viewer.SearchMatch
    view.collectMatches("file offset of the PE signature", {}, &matches)
    Swag.require(matches.count == 1)
    Swag.require(matches[0].minor == cast(u64, Binary.Column.Detail))
    let revealed = view.revealMatch(matches[0], "")
    Swag.require(revealed)
    Swag.require(view.list.selectedLine() != null)
    Swag.require(binaryCellText(unwrap view.list.selectedLine(), .Field) == "e_lfanew")
    let item = view.list.selectedLine()!.itemAt(cast(u32, Binary.Column.Detail))
    Swag.require(item.name.raw == "file offset of the PE signature")
    Swag.require(not item.colorBk.a)

    var bounds: Math.Rectangle
    let bounded = view.searchBounds(&bounds)
    Swag.require(bounded)
    let rowWidth = view.list.listView.clientRect().width
    Swag.require(bounds.width > 0 and bounds.width < rowWidth * 0.5)

    view.clearSearch()
    Swag.require(view.list.selectedLine() == null)
}

// Filtering reuses the report search semantics, retains the ancestry of nested matches, and does
// not remove the ordinary occurrence index from the rows that remain visible.
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_filter", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1100, 640)

    let view = binaryTestViewer(&host, fileName, 1100, 600)
    view.applyFilter("file offset of the PE signature", {})
    while view.filterTimer do
        host.pump()

    var matched = Swag.U64.Max
    for row, index in view.doc.report.rows where row.label == "e_lfanew" do
        matched = index
    Swag.require(matched != Swag.U64.Max and view.rowLines[matched] != null)
    Swag.require(view.rowLines[matched]!.parent != null)
    Swag.require(view.list.lineCount() < view.doc.report.rows.count)

    var matches: Array'Viewer.SearchMatch
    view.collectMatches("e_lfanew", {}, &matches)
    Swag.require(matches.count == 1 and matches[0].major == matched)

    view.applyFilter("", {})
    while view.filterTimer do
        host.pump()
    for line in view.rowLines do
        Swag.require(line != null)
}

// The report, its headings, and its controls all follow a live language change.
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_language", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1100, 640)
    defer expect host.app.setLanguage(ReferenceLanguage)

    let view = binaryTestViewer(&host, fileName, 1100, 600)
    Swag.require(findRow(&view.doc.report, "File") != null)
    let revealed = view.revealOffset(FixtureTextAt)
    Swag.require(revealed)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    finishBinaryViewer(&host, view)

    Swag.require(findRow(&view.doc.report, "Fichier") != null)
    Swag.require(findRow(&view.doc.report, "En-tête DOS") != null)
    Swag.require(view.list.header.itemAt(cast(u32, Binary.Column.Detail)).name.raw == "Signification")
    Swag.require(view.list.selectedLine() != null)
    Swag.require(binaryCellText(unwrap view.list.selectedLine(), .Field) == ".text")
}

// File-offset jumps and row history make a large report navigable without flattening its tree.
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_navigation", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1100, 640)

    let view    = binaryTestViewer(&host, fileName, 1100, 600)
    var reached = view.goToTypedOffset("400")
    Swag.require(reached)
    Swag.require(binaryCellText(unwrap view.list.selectedLine(), .Field) == ".text")
    reached = view.goToTypedOffset("7F0")
    Swag.require(reached)
    Swag.require(binaryCellText(unwrap view.list.selectedLine(), .Field) == ".rdata")

    // The hexadecimal viewer's go-to grammar holds here too: `0d` is decimal, not hexadecimal 0xD1024.
    reached = view.goToTypedOffset("0d1024")
    Swag.require(reached)
    Swag.require(binaryCellText(unwrap view.list.selectedLine(), .Field) == ".text")
    reached = view.goToTypedOffset("7F0")
    Swag.require(reached)
    var navigated = view.navigateHistory(-1)
    Swag.require(navigated)
    Swag.require(binaryCellText(unwrap view.list.selectedLine(), .Field) == ".text")
    navigated = view.navigateHistory(1)
    Swag.require(navigated)
    Swag.require(binaryCellText(unwrap view.list.selectedLine(), .Field) == ".rdata")
}
