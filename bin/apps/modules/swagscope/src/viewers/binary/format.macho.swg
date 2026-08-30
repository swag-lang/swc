#global internal

using Core

// Header signatures a Mach-O file can begin with. The `CIGAM` spellings are the same words read by
// a machine of the other byte order, which is how a file says its own order without a flag.
private const MachMagic32    = 0xFEEDFACE'u32
private const MachMagic64    = 0xFEEDFACF'u32
private const MachCigam32    = 0xCEFAEDFE'u32
private const MachCigam64    = 0xCFFAEDFE'u32
private const MachFatMagic   = 0xCAFEBABE'u32
private const MachFatMagic64 = 0xCAFEBABF'u32

// Returns the processor a Mach-O CPU type names.
func machCpuName(value: u32)->string
{
    switch value
    {
    case 7:          return "Intel 386"
    case 0x01000007: return "x86-64"
    case 12:         return "ARM"
    case 0x0100000C: return "ARM64"
    case 0x0200000C: return "ARM64_32"
    case 18:         return "PowerPC"
    case 0x01000012: return "PowerPC 64"
    }

    return "?"
}

// Returns what a Mach-O file is for.
func machFileTypeName(value: u32)->string
{
    switch value
    {
    case 1:  return "MH_OBJECT"
    case 2:  return "MH_EXECUTE"
    case 3:  return "MH_FVMLIB"
    case 4:  return "MH_CORE"
    case 5:  return "MH_PRELOAD"
    case 6:  return "MH_DYLIB"
    case 7:  return "MH_DYLINKER"
    case 8:  return "MH_BUNDLE"
    case 9:  return "MH_DYLIB_STUB"
    case 10: return "MH_DSYM"
    case 11: return "MH_KEXT_BUNDLE"
    }

    return "MH_UNKNOWN"
}

// Returns what one load command asks of the loader.
func machCommandName(value: u32)->string
{
    // The high bit says the loader must fail rather than skip a command it does not know, so it is
    // masked off before the command itself is named.
    switch value & 0x7FFFFFFF
    {
    case 0x01: return "LC_SEGMENT"
    case 0x02: return "LC_SYMTAB"
    case 0x04: return "LC_THREAD"
    case 0x05: return "LC_UNIXTHREAD"
    case 0x0B: return "LC_DYSYMTAB"
    case 0x0C: return "LC_LOAD_DYLIB"
    case 0x0D: return "LC_ID_DYLIB"
    case 0x0E: return "LC_LOAD_DYLINKER"
    case 0x0F: return "LC_ID_DYLINKER"
    case 0x18: return "LC_LOAD_WEAK_DYLIB"
    case 0x19: return "LC_SEGMENT_64"
    case 0x1B: return "LC_UUID"
    case 0x1C: return "LC_RPATH"
    case 0x1D: return "LC_CODE_SIGNATURE"
    case 0x1F: return "LC_REEXPORT_DYLIB"
    case 0x22: return "LC_DYLD_INFO"
    case 0x24: return "LC_VERSION_MIN_MACOSX"
    case 0x25: return "LC_VERSION_MIN_IPHONEOS"
    case 0x26: return "LC_FUNCTION_STARTS"
    case 0x28: return "LC_MAIN"
    case 0x29: return "LC_DATA_IN_CODE"
    case 0x2B: return "LC_SOURCE_VERSION"
    case 0x32: return "LC_BUILD_VERSION"
    case 0x33: return "LC_DYLD_EXPORTS_TRIE"
    case 0x34: return "LC_DYLD_CHAINED_FIXUPS"
    }

    return "LC_UNKNOWN"
}

// Returns whether the file begins with a Mach-O image or a universal wrapper around several.
func isMachO(image: *BinaryImage)->bool
{
    image.bigEndian = false
    let magic = image.u32At(0)
    if magic == MachMagic32 or magic == MachMagic64 or magic == MachCigam32 or magic == MachCigam64 do
        return true
    return isMachFat(image)
}

// Returns whether the file is a universal binary rather than the Java class file that shares its
// signature.
//
// Both begin with `CAFEBABE`. What follows is a small count of architectures in one and a pair of
// version numbers in the other, so the file is claimed only when the first slice names a processor
// Mach-O actually has a number for.
private func isMachFat(image: *BinaryImage)->bool
{
    image.bigEndian = false
    let magic = image.u32At(0)
    if magic != MachFatMagic and magic != MachFatMagic64 do
        return false

    image.bigEndian = true
    let count = image.u32At(4)
    if !count or count > 32 do
        return false
    return machCpuName(image.u32At(8)) != "?"
}

// Adds everything a Mach-O image says about itself, one slice at a time when it carries several.
func reportMachO(image: *BinaryImage, report: *BinaryReport)
{
    image.bigEndian = false
    let magic = image.u32At(0)
    if magic == MachFatMagic or magic == MachFatMagic64
    {
        reportMachFat(image, report, magic == MachFatMagic64)
        return
    }

    let summary = reportMachImage(image, report, 0, open: true)
    report.formatName = String.from(summary.wide ? "Mach-O 64" : "Mach-O 32")
    report.summary    = Format.toString("% · % · %", report.formatName, machFileTypeName(summary.kind), machCpuName(summary.cpu))
}

// What one slice turned out to be, so the file above it can be summarized.
private struct MachImageInfo
{
    cpu:  u32
    kind: u32
    wide: bool
}

private func reportMachFat(image: *BinaryImage, report: *BinaryReport, wide: bool)
{
    // The wrapper itself is always big endian, whatever the slices inside it are.
    image.bigEndian = true

    let s     = binStrings()
    let count = cast(u64) image.u32At(4)
    let step  = wide ? 32'u64 : 20
    let shown = Math.min(count, BinaryListLimit)
    let total = countText(count, s.word_Entry, s.word_Entries)

    report.beginGroup(s.mo_Fat, total.toString(), s.mo_FatDesc, offset: 0, length: 8 + count * step, open: true)

    var names: String
    for index in shown
    {
        let entryAt = 8 + index * step
        let cpu     = image.u32At(entryAt)
        let sliceAt = wide ? image.u64At(entryAt + 8) : cast(u64) image.u32At(entryAt + 8)
        let size    = wide ? image.u64At(entryAt + 16) : cast(u64) image.u32At(entryAt + 12)
        let label   = Format.toString(s.mo_Slice, index)
        let stored  = StrConv.toDisplaySize(size)

        if !names.isEmpty() do
            names += ", "
        names += machCpuName(cpu)

        report.beginGroup(label.toString(), machCpuName(cpu), stored.toString(), offset: sliceAt, length: size, open: true)
        report.hexField(entryAt, 4, "cputype", cast(u64) cpu, machCpuName(cpu))
        report.hexField(entryAt + 4, 4, "cpusubtype", cast(u64) image.u32At(entryAt + 4))
        report.hexField(entryAt + 8, wide ? 8 : 4, "offset", sliceAt)
        report.sizeField(wide ? entryAt + 16 : entryAt + 12, wide ? 8 : 4, "size", size)

        // Each slice is a complete image, so it is read exactly as a lone one would be — including
        // its own byte order, which the wrapper says nothing about.
        discard reportMachImage(image, report, sliceAt, open: false)
        image.bigEndian = true
        report.endGroup()
    }

    report.listCut(shown, count)
    report.endGroup()

    report.formatName = String.from("Mach-O universal")
    report.summary    = Format.toString("% · %", report.formatName, names)
}

// Adds one complete Mach-O image found at `at`.
private func reportMachImage(image: *BinaryImage, report: *BinaryReport, at: u64, open: bool)->MachImageInfo
{
    var result: retval

    image.bigEndian = false
    let magic = image.u32At(at)
    image.bigEndian = magic == MachCigam32 or magic == MachCigam64
    result.wide     = magic == MachMagic64 or magic == MachCigam64

    let s        = binStrings()
    let headerAt = at
    result.cpu  = image.u32At(headerAt + 4)
    result.kind = image.u32At(headerAt + 12)
    let count   = cast(u64) image.u32At(headerAt + 16)
    let cmdSize = cast(u64) image.u32At(headerAt + 20)
    let flags   = image.u32At(headerAt + 24)
    let names   = machFlagsText(flags)

    report.beginGroup(s.mo_Header, machFileTypeName(result.kind), machCpuName(result.cpu), offset: headerAt, length: result.wide ? 32 : 28, open: open)
    report.hexField(headerAt, 4, "magic", cast(u64) magic, result.wide ? s.pe_Image64 : s.pe_Image32)
    report.hexField(headerAt + 4, 4, "cputype", cast(u64) result.cpu, machCpuName(result.cpu))
    report.hexField(headerAt + 8, 4, "cpusubtype", cast(u64) image.u32At(headerAt + 8))
    report.hexField(headerAt + 12, 4, "filetype", cast(u64) result.kind, machFileTypeName(result.kind))
    report.numField(headerAt + 16, 4, "ncmds", count)
    report.sizeField(headerAt + 20, 4, "sizeofcmds", cmdSize)
    report.hexField(headerAt + 24, 4, "flags", cast(u64) flags, names.toString())
    report.endGroup()

    reportMachCommands(image, report, at, headerAt + (result.wide ? 32'u64 : 28), count, cmdSize, result.wide, open)
    return result
}

private func reportMachCommands(image: *BinaryImage, report: *BinaryReport, imageAt, at, count, totalSize: u64, wide, open: bool)
{
    let s     = binStrings()
    let shown = Math.min(count, BinaryListLimit)
    let total = countText(count, s.word_Entry, s.word_Entries)

    report.beginGroup(s.mo_Commands, total.toString(), s.mo_CommandsDesc, offset: at, length: totalSize, open: open)

    var libraries: Array'String
    var scan = at
    for shown
    {
        if !image.has(scan, 8) do
            break

        let command = image.u32At(scan)
        let size    = cast(u64) image.u32At(scan + 4)
        if size < 8 do
            break

        report.beginGroup(machCommandName(command), "", "", offset: scan, length: size)
        report.hexField(scan, 4, "cmd", cast(u64) command, machCommandName(command))
        report.sizeField(scan + 4, 4, "cmdsize", size)
        reportMachCommandBody(image, report, imageAt, scan, size, command, wide, &libraries)
        report.endGroup()
        scan += size
    }

    report.listCut(shown, count)
    report.endGroup()

    if !libraries.isEmpty()
    {
        let counted = countText(libraries.count, s.word_Library, s.word_Libraries)
        report.beginGroup(s.shr_Libraries, counted.toString(), "", open: open)
        for one in libraries do
            report.derived(one.toString(), "")
        report.endGroup()
    }
}

// Adds the payload of one load command, for the commands that carry something a reader wants.
private func reportMachCommandBody(image: *BinaryImage, report: *BinaryReport, imageAt, at, size: u64, command: u32, wide: bool, libraries: *Array'String)
{
    let s    = binStrings()
    let kind = command & 0x7FFFFFFF

    switch kind
    {
    case 0x01, 0x19:

        // A segment is a run of pages the loader maps, and the sections inside it are how a linker
        // divided that run. Both are worth naming, so both are.
        let name     = image.fixedTextAt(at + 8, 16)
        let valueAt  = at + 24
        let step     = wide ? 8'u64 : 4
        let fileAt   = image.scalarAt(valueAt + step * 2, step)
        let fileLen  = image.scalarAt(valueAt + step * 3, step)
        let maxProt  = image.u32At(valueAt + step * 4)
        let initial  = image.u32At(valueAt + step * 4 + 4)
        let sections = cast(u64) image.u32At(valueAt + step * 4 + 8)
        let maxText  = machProtectionText(maxProt)
        let iniText  = machProtectionText(initial)
        let guard    = Format.toString(s.mo_Protection, maxText, iniText)

        report.field(at + 8, 16, "segname", name.toString(), guard.toString())
        report.hexField(valueAt, step, "vmaddr", image.scalarAt(valueAt, step))
        report.sizeField(valueAt + step, step, "vmsize", image.scalarAt(valueAt + step, step))
        report.hexField(valueAt + step * 2, step, "fileoff", fileAt)
        report.sizeField(valueAt + step * 3, step, "filesize", fileLen)
        report.numField(valueAt + step * 4 + 8, 4, "nsects", sections)
        reportMachSections(image, report, imageAt, at + (wide ? 72'u64 : 56), sections, wide)

    case 0x0C, 0x0D, 0x18, 0x1F:
        let offset  = cast(u64) image.u32At(at + 8)
        let path    = image.cstringAt(at + offset, size > offset ? size - offset : 0)
        let current = machVersionText(image.u32At(at + 16))
        report.field(at + offset, path.length, "name", path.toString())
        report.field(at + 16, 4, "current_version", current.toString())
        if kind == 0x0C or kind == 0x18 do
            libraries.add(path)

    case 0x0E, 0x0F, 0x1C:
        let offset = cast(u64) image.u32At(at + 8)
        let path   = image.cstringAt(at + offset, size > offset ? size - offset : 0)
        report.field(at + offset, path.length, kind == 0x1C ? "path" : "name", path.toString(), kind == 0x1C ? "" : s.shr_Interpreter)

    case 0x1B:
        let identity = machUuidText(image, at + 8)
        report.field(at + 8, 16, "uuid", identity.toString(), s.shr_BuildId)

    case 0x28:
        report.hexField(at + 8, 8, "entryoff", image.u64At(at + 8), s.shr_Entry)
        report.sizeField(at + 16, 8, "stacksize", image.u64At(at + 16))

    case 0x02:
        report.hexField(at + 8, 4, "symoff", cast(u64) image.u32At(at + 8))
        report.numField(at + 12, 4, "nsyms", cast(u64) image.u32At(at + 12))
        report.hexField(at + 16, 4, "stroff", cast(u64) image.u32At(at + 16))
        report.sizeField(at + 20, 4, "strsize", cast(u64) image.u32At(at + 20))

    case 0x32:
        let minimum = machVersionText(image.u32At(at + 12))
        let sdk     = machVersionText(image.u32At(at + 16))
        report.numField(at + 8, 4, "platform", cast(u64) image.u32At(at + 8))
        report.field(at + 12, 4, "minos", minimum.toString())
        report.field(at + 16, 4, "sdk", sdk.toString())
    }
}

private func reportMachSections(image: *BinaryImage, report: *BinaryReport, imageAt, at, count: u64, wide: bool)
{
    if !count do
        return

    let s     = binStrings()
    let step  = wide ? 80'u64 : 68
    let shown = Math.min(count, BinaryListLimit)
    let total = countText(count, s.word_Section, s.word_Sections)

    report.beginGroup(s.shr_Sections, total.toString(), "", offset: at, length: count * step)

    for index in shown
    {
        let entryAt  = at + index * step
        let name     = image.fixedTextAt(entryAt, 16)
        let segment  = image.fixedTextAt(entryAt + 16, 16)
        let valueAt  = entryAt + 32
        let wideStep = wide ? 8'u64 : 4
        let size     = image.scalarAt(valueAt + wideStep, wideStep)
        let fileAt   = cast(u64) image.u32At(valueAt + wideStep * 2)
        let stored   = StrConv.toDisplaySize(size)

        report.beginGroup(name.toString(), segment.toString(), stored.toString(), offset: imageAt + fileAt, length: size)
        report.hexField(valueAt, wideStep, "addr", image.scalarAt(valueAt, wideStep))
        report.sizeField(valueAt + wideStep, wideStep, "size", size)
        report.hexField(valueAt + wideStep * 2, 4, "offset", fileAt)

        // Four words separate the file offset from the flags in both forms: the alignment, the
        // relocation offset, the relocation count, and then the flags themselves.
        report.hexField(valueAt + wideStep * 2 + 16, 4, "flags", cast(u64) image.u32At(valueAt + wideStep * 2 + 16))
        report.endGroup()
    }

    report.listCut(shown, count)
    report.endGroup()
}

private func machFlagsText(value: u32)->String
{
    let names = [BinaryFlagName{0x000001, "NOUNDEFS"},
                 BinaryFlagName{0x000002, "INCRLINK"},
                 BinaryFlagName{0x000004, "DYLDLINK"},
                 BinaryFlagName{0x000008, "BINDATLOAD"},
                 BinaryFlagName{0x000010, "PREBOUND"},
                 BinaryFlagName{0x000020, "SPLIT_SEGS"},
                 BinaryFlagName{0x000080, "NOFIXPREBINDING"},
                 BinaryFlagName{0x000100, "PREBINDABLE"},
                 BinaryFlagName{0x000200, "ALLMODSBOUND"},
                 BinaryFlagName{0x000800, "CANONICAL"},
                 BinaryFlagName{0x001000, "WEAK_DEFINES"},
                 BinaryFlagName{0x002000, "BINDS_TO_WEAK"},
                 BinaryFlagName{0x008000, "TWOLEVEL"},
                 BinaryFlagName{0x200000, "PIE"},
                 BinaryFlagName{0x800000, "HAS_TLV_DESCRIPTORS"}]
    return flagsText(cast(u64) value, names)
}

private func machProtectionText(value: u32)->String
{
    let names = [BinaryFlagName{1, "READ"}, BinaryFlagName{2, "WRITE"}, BinaryFlagName{4, "EXECUTE"}]
    return flagsText(cast(u64) value, names)
}

// Returns the three-part version packed into one word.
private func machVersionText(value: u32)->String
{
    return Format.toString("%.%.%", value >> 16, (value >> 8) & 0xFF, value & 0xFF)
}

// Returns the build identity, in the plain hexadecimal grouping Apple's tools print.
private func machUuidText(image: *BinaryImage, at: u64)->String
{
    if !image.has(at, 16) do
        return String.from(BinaryNoValue)

    var text: Array'u8
    for index in 16
    {
        if index == 4 or index == 6 or index == 8 or index == 10 do
            text.add('-'u8)
        let value  = image.bytes[at + index]
        let digits = [cast(u8) (value >> 4), value & 0xF]
        for nibble in digits do
            text.add(nibble < 10 ? '0'u8 + nibble : 'A'u8 + nibble - 10)
    }

    return String.from(Swag.makeString(text.buffer!, text.count))
}
