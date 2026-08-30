#global internal

using Core

// Where the DOS header records the file offset of the PE signature.
const PeLfanewOffset = 0x3C'u64

// Size of the file header a PE signature is followed by.
const PeFileHeaderSize = 20'u64

// Size of one section header.
const PeSectionHeaderSize = 40'u64

// Size of one symbol table record in a COFF object.
private const PeSymbolSize = 18'u64

// One section, kept for the address translation every data directory needs.
struct PeSection
{
    name:        String
    virtualSize: u32
    virtualAddr: u32
    rawSize:     u32
    rawOffset:   u32
}

// Address translation for one PE image.
//
// Everything a directory points at is a load-time address, and every byte the report reads is at a
// file offset. Sections are the only thing relating the two, so they are collected first and every
// later structure is reached through this.
struct PeLayout
{
    sections:      Array'PeSection
    sizeOfHeaders: u32
    imageBase:     u64
    is64:          bool
}

impl PeLayout
{
    // Returns the file offset an address holds its bytes at, or `Swag.U64.Max` when nothing does.
    mtd const offsetOf(rva: u32)->u64
    {
        if !rva do
            return Swag.U64.Max

        for section in .sections
        {
            let span = section.virtualSize ? section.virtualSize : section.rawSize
            if rva < section.virtualAddr or rva - section.virtualAddr >= span do
                continue

            // A section can declare more memory than it stores, and the excess is zero-filled at
            // load time. There is no byte in the file to point at, so the caller is told.
            let delta = cast(u64) (rva - section.virtualAddr)
            if delta >= cast(u64) section.rawSize do
                return Swag.U64.Max
            return cast(u64) section.rawOffset + delta
        }

        // The headers are mapped where they are stored, which is how a directory can address them.
        if rva < .sizeOfHeaders do
            return cast(u64) rva
        return Swag.U64.Max
    }

    // Returns the name of the section an address falls in, or an empty name when it falls outside.
    mtd const sectionNameOf(rva: u32)->string
    {
        for section in .sections
        {
            let span = section.virtualSize ? section.virtualSize : section.rawSize
            if rva >= section.virtualAddr and rva - section.virtualAddr < span do
                return section.name.toString()
        }

        return ""
    }

    // Returns the size of one address as it is stored in this image.
    mtd const pointerSize()->u64 => .is64 ? 8 : 4
}

// Returns the processor a COFF machine identifier names.
//
// These are proper names rather than prose, so they read the same in every language.
func peMachineName(value: u16)->string
{
    switch value
    {
    case 0x0000: return "any"
    case 0x014C: return "Intel 386"
    case 0x0162: return "MIPS R3000"
    case 0x0166: return "MIPS little endian"
    case 0x0169: return "MIPS WCE v2"
    case 0x01A2: return "Hitachi SH3"
    case 0x01A6: return "Hitachi SH4"
    case 0x01C0: return "ARM"
    case 0x01C2: return "ARM Thumb"
    case 0x01C4: return "ARM Thumb-2"
    case 0x01F0: return "PowerPC"
    case 0x0200: return "Intel Itanium"
    case 0x0266: return "MIPS16"
    case 0x0284: return "Alpha 64"
    case 0x5032: return "RISC-V 32"
    case 0x5064: return "RISC-V 64"
    case 0x6232: return "LoongArch 32"
    case 0x6264: return "LoongArch 64"
    case 0x8664: return "x64"
    case 0xA641: return "ARM64EC"
    case 0xA64E: return "ARM64X"
    case 0xAA64: return "ARM64"
    case 0xC0EE: return "CEE"
    }

    return "?"
}

// Returns the environment a subsystem identifier names.
func peSubsystemName(value: u16)->string
{
    switch value
    {
    case 1:  return "native"
    case 2:  return "Windows GUI"
    case 3:  return "Windows console"
    case 5:  return "OS/2 console"
    case 7:  return "POSIX console"
    case 8:  return "Windows 9x driver"
    case 9:  return "Windows CE GUI"
    case 10: return "EFI application"
    case 11: return "EFI boot service driver"
    case 12: return "EFI runtime driver"
    case 13: return "EFI ROM"
    case 14: return "Xbox"
    case 16: return "Windows boot application"
    }

    return "?"
}

// Returns the names of the image-wide properties a file header declares.
func peCharacteristicsText(value: u32)->String
{
    let names = [BinaryFlagName{0x0001, "RELOCS_STRIPPED"},
                 BinaryFlagName{0x0002, "EXECUTABLE_IMAGE"},
                 BinaryFlagName{0x0004, "LINE_NUMS_STRIPPED"},
                 BinaryFlagName{0x0008, "LOCAL_SYMS_STRIPPED"},
                 BinaryFlagName{0x0010, "AGGRESSIVE_WS_TRIM"},
                 BinaryFlagName{0x0020, "LARGE_ADDRESS_AWARE"},
                 BinaryFlagName{0x0080, "BYTES_REVERSED_LO"},
                 BinaryFlagName{0x0100, "32BIT_MACHINE"},
                 BinaryFlagName{0x0200, "DEBUG_STRIPPED"},
                 BinaryFlagName{0x0400, "REMOVABLE_RUN_FROM_SWAP"},
                 BinaryFlagName{0x0800, "NET_RUN_FROM_SWAP"},
                 BinaryFlagName{0x1000, "SYSTEM"},
                 BinaryFlagName{0x2000, "DLL"},
                 BinaryFlagName{0x4000, "UP_SYSTEM_ONLY"},
                 BinaryFlagName{0x8000, "BYTES_REVERSED_HI"}]
    return flagsText(cast(u64) value, names)
}

// Returns the names of the loader policies an optional header opts into.
func peDllCharacteristicsText(value: u16)->String
{
    let names = [BinaryFlagName{0x0020, "HIGH_ENTROPY_VA"},
                 BinaryFlagName{0x0040, "DYNAMIC_BASE"},
                 BinaryFlagName{0x0080, "FORCE_INTEGRITY"},
                 BinaryFlagName{0x0100, "NX_COMPAT"},
                 BinaryFlagName{0x0200, "NO_ISOLATION"},
                 BinaryFlagName{0x0400, "NO_SEH"},
                 BinaryFlagName{0x0800, "NO_BIND"},
                 BinaryFlagName{0x1000, "APPCONTAINER"},
                 BinaryFlagName{0x2000, "WDM_DRIVER"},
                 BinaryFlagName{0x4000, "GUARD_CF"},
                 BinaryFlagName{0x8000, "TERMINAL_SERVER_AWARE"}]
    return flagsText(cast(u64) value, names)
}

// Returns the names of the properties one section declares.
func peSectionFlagsText(value: u32)->String
{
    let names = [BinaryFlagName{0x00000008, "TYPE_NO_PAD"},
                 BinaryFlagName{0x00000020, "CNT_CODE"},
                 BinaryFlagName{0x00000040, "CNT_INITIALIZED_DATA"},
                 BinaryFlagName{0x00000080, "CNT_UNINITIALIZED_DATA"},
                 BinaryFlagName{0x00000200, "LNK_INFO"},
                 BinaryFlagName{0x00000800, "LNK_REMOVE"},
                 BinaryFlagName{0x00001000, "LNK_COMDAT"},
                 BinaryFlagName{0x00008000, "GPREL"},
                 BinaryFlagName{0x01000000, "LNK_NRELOC_OVFL"},
                 BinaryFlagName{0x02000000, "MEM_DISCARDABLE"},
                 BinaryFlagName{0x04000000, "MEM_NOT_CACHED"},
                 BinaryFlagName{0x08000000, "MEM_NOT_PAGED"},
                 BinaryFlagName{0x10000000, "MEM_SHARED"},
                 BinaryFlagName{0x20000000, "MEM_EXECUTE"},
                 BinaryFlagName{0x40000000, "MEM_READ"},
                 BinaryFlagName{0x80000000, "MEM_WRITE"}]

    // The alignment of a section is a small enumeration packed into four bits of the same field, so
    // it is read out before the rest is spelled as flags.
    var result = flagsText(cast(u64) value & ~0x00F00000'u64, names)
    let align  = (value >> 20) & 0xF
    if align
    {
        if !result.isEmpty() do
            result += " | "
        let text = Format.toString("ALIGN_%_BYTES", 1'u32 << (align - 1))
        result += text.toString()
    }

    return result
}

// Returns the name of the data directory stored at `index`, as the specification writes it.
func peDirectoryName(index: u64)->string
{
    const Names = ["Export", "Import", "Resource", "Exception", "Certificate", "BaseRelocation",
                   "Debug", "Architecture", "GlobalPtr", "TLS", "LoadConfig", "BoundImport",
                   "IAT", "DelayImport", "COMDescriptor", "Reserved"]
    if index >= Names.count do
        return "?"
    return Names[index]
}

// Returns what a debug directory entry carries.
func peDebugTypeName(value: u32)->string
{
    switch value
    {
    case 1:  return "COFF"
    case 2:  return "CODEVIEW"
    case 3:  return "FPO"
    case 4:  return "MISC"
    case 5:  return "EXCEPTION"
    case 6:  return "FIXUP"
    case 7:  return "OMAP_TO_SRC"
    case 8:  return "OMAP_FROM_SRC"
    case 9:  return "BORLAND"
    case 11: return "CLSID"
    case 12: return "VC_FEATURE"
    case 13: return "POGO"
    case 14: return "ILTCG"
    case 16: return "REPRO"
    case 17: return "EMBEDDED_PORTABLE_PDB"
    case 19: return "PDBCHECKSUM"
    case 20: return "EX_DLLCHARACTERISTICS"
    }

    return "UNKNOWN"
}

// Returns the standard name of a resource type, or an empty name for an application-defined one.
func peResourceTypeName(value: u32)->string
{
    switch value
    {
    case 1:  return "CURSOR"
    case 2:  return "BITMAP"
    case 3:  return "ICON"
    case 4:  return "MENU"
    case 5:  return "DIALOG"
    case 6:  return "STRING"
    case 7:  return "FONTDIR"
    case 8:  return "FONT"
    case 9:  return "ACCELERATOR"
    case 10: return "RCDATA"
    case 11: return "MESSAGETABLE"
    case 12: return "GROUP_CURSOR"
    case 14: return "GROUP_ICON"
    case 16: return "VERSION"
    case 17: return "DLGINCLUDE"
    case 19: return "PLUGPLAY"
    case 20: return "VXD"
    case 21: return "ANICURSOR"
    case 22: return "ANIICON"
    case 23: return "HTML"
    case 24: return "MANIFEST"
    }

    return ""
}

// Returns whether the file begins with a DOS header that leads to a PE signature.
func isPeImage(image: *BinaryImage)->bool
{
    if !image.matches(0, "MZ") do
        return false
    let peOffset = cast(u64) image.u32At(PeLfanewOffset)
    return image.matches(peOffset, "PE\0\0")
}

// Returns whether the file begins with a COFF file header rather than a complete image.
//
// An object file carries no signature, so it is recognized by a machine identifier its section
// count and header size agree with. Everything checked here is what a linker itself checks.
func isCoffObject(image: *BinaryImage)->bool
{
    if image.bytes.count < PeFileHeaderSize do
        return false

    let machine = image.u16At(0)
    if machine != 0x014C and machine != 0x8664 and machine != 0xAA64 and machine != 0x01C0 and machine != 0x01C4 and machine != 0xA641 do
        return false
    if image.u16At(16) != 0 do
        return false

    let sections = cast(u64) image.u16At(2)
    return sections != 0 and PeFileHeaderSize + sections * PeSectionHeaderSize <= image.bytes.count
}

// The parts of a file header the rest of the report needs.
private struct PeFileHeaderInfo
{
    machine:         u16
    sectionCount:    u16
    optionalSize:    u64
    characteristics: u32
    symbolTable:     u64
    symbolCount:     u64
}

// Adds everything a PE image says about itself, from its DOS header to its last data directory.
func reportPeImage(image: *BinaryImage, report: *BinaryReport)
{
    image.bigEndian = false

    let peOffset = cast(u64) image.u32At(PeLfanewOffset)
    reportPeDosHeader(image, report, peOffset)
    reportPeRichHeader(image, report, peOffset)

    let header   = reportPeFileHeader(image, report, peOffset + 4)
    let optional = peOffset + 4 + PeFileHeaderSize

    var layout: PeLayout
    reportPeOptionalHeader(image, report, optional, header.optionalSize, &layout)
    reportPeSections(image, report, optional + header.optionalSize, header.sectionCount, &layout)

    reportPeExports(image, report, &layout)
    reportPeImports(image, report, &layout)
    reportPeDelayImports(image, report, &layout)
    reportPeResources(image, report, &layout)
    reportPeDebug(image, report, &layout)
    reportPeExceptions(image, report, &layout)
    reportPeRelocations(image, report, &layout)
    reportPeTls(image, report, &layout)
    reportPeLoadConfig(image, report, &layout)
    reportPeClr(image, report, &layout)
    reportPeCertificates(image, report, &layout)

    let s        = binStrings()
    let kind     = header.characteristics & 0x2000 ? "DLL" : (header.characteristics & 0x1000 ? "SYS" : "EXE")
    let sections = countText(cast(u64) header.sectionCount, s.word_Section, s.word_Sections)
    report.formatName = String.from(layout.is64 ? "PE32+" : "PE32")
    report.summary    = Format.toString("% · % · % · %", report.formatName, kind, peMachineName(header.machine), sections)
}

// Adds the sections and symbols of a COFF object, which carries no image header of its own.
func reportCoffObject(image: *BinaryImage, report: *BinaryReport)
{
    image.bigEndian = false

    let header = reportPeFileHeader(image, report, 0)

    var layout: PeLayout
    layout.is64 = header.machine == 0x8664 or header.machine == 0xAA64 or header.machine == 0xA641
    reportPeSections(image, report, PeFileHeaderSize + header.optionalSize, header.sectionCount, &layout)
    reportCoffSymbols(image, report, header.symbolTable, header.symbolCount)

    let s        = binStrings()
    let sections = countText(cast(u64) header.sectionCount, s.word_Section, s.word_Sections)
    report.formatName = String.from("COFF")
    report.summary    = Format.toString("COFF · % · %", peMachineName(header.machine), sections)
}

private func reportPeDosHeader(image: *BinaryImage, report: *BinaryReport, peOffset: u64)
{
    let s     = binStrings()
    let magic = image.fixedTextAt(0, 2)

    report.beginGroup(s.pe_DosHeader, magic.toString(), s.pe_DosSignature, offset: 0, length: 64, open: true)
    report.numField(2, 2, "e_cblp", cast(u64) image.u16At(2))
    report.numField(4, 2, "e_cp", cast(u64) image.u16At(4))
    report.numField(6, 2, "e_crlc", cast(u64) image.u16At(6))
    report.numField(8, 2, "e_cparhdr", cast(u64) image.u16At(8))
    report.hexField(10, 2, "e_minalloc", cast(u64) image.u16At(10))
    report.hexField(12, 2, "e_maxalloc", cast(u64) image.u16At(12))

    let stack = Format.toString("%:%", hexText(cast(u64) image.u16At(14), 4), hexText(cast(u64) image.u16At(16), 4))
    report.field(14, 4, "e_ss:e_sp", stack.toString())
    report.hexField(18, 2, "e_csum", cast(u64) image.u16At(18))

    let entry = Format.toString("%:%", hexText(cast(u64) image.u16At(22), 4), hexText(cast(u64) image.u16At(20), 4))
    report.field(20, 4, "e_cs:e_ip", entry.toString())
    report.hexField(24, 2, "e_lfarlc", cast(u64) image.u16At(24))
    report.numField(26, 2, "e_ovno", cast(u64) image.u16At(26))
    report.hexField(36, 2, "e_oemid", cast(u64) image.u16At(36))
    report.hexField(38, 2, "e_oeminfo", cast(u64) image.u16At(38))
    report.hexField(PeLfanewOffset, 4, "e_lfanew", peOffset, s.pe_DosLfanew)

    // The stub is the program a DOS box would have run, and in every modern image it exists only to
    // print one sentence. That sentence is the readable part, so it is what the report shows.
    let stub = peDosStubText(image, peOffset)
    if !stub.isEmpty() do
        report.field(64, peOffset > 64 ? peOffset - 64 : 0, s.pe_DosStub, stub.toString(), s.pe_DosStubDesc)
    report.endGroup()
}

// Returns the sentence the DOS stub prints, found by the `$` its printing service stops at.
private func peDosStubText(image: *BinaryImage, peOffset: u64)->String
{
    let limit = Math.min(peOffset, image.bytes.count)
    var start = Swag.U64.Max

    for index in 64 until limit
    {
        let value = image.bytes[index]
        if value >= 'A'u8 and value <= 'Z'u8
        {
            start = index
            break
        }
    }

    if start == Swag.U64.Max do
        return {}

    var end = start
    while end < limit and image.bytes[end] != '$'u8 and image.bytes[end] >= 9 do
        end += 1
    if end - start < 8 do
        return {}

    var text: Array'u8
    for index in start until end
    {
        let value = image.bytes[index]
        text.add(value >= 32 and value < 127 ? value : ' 'u8)
    }

    return String.from(Latin1.trim(Swag.makeString(text.buffer!, text.count)))
}

// Adds the toolchain fingerprint Microsoft linkers leave between the DOS stub and the PE signature.
//
// Nothing reads this at run time and no tool writes it down, yet it records every compiler, linker
// and assembler version that contributed to the image, and how many objects each of them produced.
// It is the single most telling thing an executable carries about how it was built.
private func reportPeRichHeader(image: *BinaryImage, report: *BinaryReport, peOffset: u64)
{
    let limit  = Math.min(peOffset, image.bytes.count)
    var richAt = Swag.U64.Max
    var scan   = 64'u64

    while scan + 8 <= limit
    {
        if image.matches(scan, "Rich")
        {
            richAt = scan
            break
        }

        scan += 4
    }

    if richAt == Swag.U64.Max do
        return

    // The block is written backwards from `Rich`, and its start is the only place where the stored
    // word decodes to `DanS`, so the key is what finds it.
    let key     = image.u32At(richAt + 4)
    var startAt = Swag.U64.Max
    scan = 64
    while scan + 4 <= richAt
    {
        if (image.u32At(scan) ^ key) == 0x536E6144
        {
            startAt = scan
            break
        }

        scan += 4
    }

    if startAt == Swag.U64.Max do
        return

    let s     = binStrings()
    let first = startAt + 16
    let count = first < richAt ? (richAt - first) / 8 : 0
    let tools = countText(count, s.word_Entry, s.word_Entries)

    report.beginGroup(s.pe_Rich, tools.toString(), s.pe_RichDesc, offset: startAt, length: richAt + 8 - startAt)
    report.hexField(richAt + 4, 4, "checksum", cast(u64) key, s.pe_RichKey)

    let shown = Math.min(count, BinaryListLimit)
    for index in shown
    {
        let at      = first + index * 8
        let comp    = image.u32At(at) ^ key
        let uses    = image.u32At(at + 4) ^ key
        let label   = Format.toString(s.pe_RichTool, comp >> 16, comp & 0xFFFF)
        let objects = countText(cast(u64) uses, s.word_Object, s.word_Objects)
        report.field(at, 8, label.toString(), objects.toString())
    }

    report.listCut(shown, count)
    report.endGroup()
}

private func reportPeFileHeader(image: *BinaryImage, report: *BinaryReport, at: u64)->PeFileHeaderInfo
{
    var result: retval
    result.machine         = image.u16At(at)
    result.sectionCount    = image.u16At(at + 2)
    result.symbolTable     = cast(u64) image.u32At(at + 8)
    result.symbolCount     = cast(u64) image.u32At(at + 12)
    result.optionalSize    = cast(u64) image.u16At(at + 16)
    result.characteristics = cast(u32) image.u16At(at + 18)

    let s     = binStrings()
    let stamp = epochText(cast(u64) image.u32At(at + 4))
    let flags = peCharacteristicsText(result.characteristics)

    report.beginGroup(s.pe_FileHeader, "", "", offset: at, length: PeFileHeaderSize, open: true)
    report.hexField(at, 2, "Machine", cast(u64) result.machine, peMachineName(result.machine))
    report.numField(at + 2, 2, "NumberOfSections", cast(u64) result.sectionCount)
    report.hexField(at + 4, 4, "TimeDateStamp", cast(u64) image.u32At(at + 4), stamp.toString())
    report.hexField(at + 8, 4, "PointerToSymbolTable", result.symbolTable)
    report.numField(at + 12, 4, "NumberOfSymbols", result.symbolCount)
    report.numField(at + 16, 2, "SizeOfOptionalHeader", result.optionalSize)
    report.hexField(at + 18, 2, "Characteristics", cast(u64) result.characteristics, flags.toString())
    report.endGroup()
    return result
}

private func reportPeOptionalHeader(image: *BinaryImage, report: *BinaryReport, at, size: u64, layout: *PeLayout)
{
    let s = binStrings()
    if !size
    {
        report.note(s.pe_NoOptional)
        return
    }

    let magic = image.u16At(at)
    layout.is64 = magic == 0x20B

    report.beginGroup(s.pe_Optional, layout.is64 ? "PE32+" : "PE32", "", offset: at, length: size, open: true)
    report.hexField(at, 2, "Magic", cast(u64) magic, magic == 0x20B ? s.pe_Image64 : (magic == 0x10B ? s.pe_Image32 : s.pe_ImageRom))

    let linker = Format.toString("%.%", image.u8At(at + 2), image.u8At(at + 3))
    report.field(at + 2, 2, "LinkerVersion", linker.toString())
    report.sizeField(at + 4, 4, "SizeOfCode", cast(u64) image.u32At(at + 4))
    report.sizeField(at + 8, 4, "SizeOfInitializedData", cast(u64) image.u32At(at + 8))
    report.sizeField(at + 12, 4, "SizeOfUninitializedData", cast(u64) image.u32At(at + 12))

    let entry = image.u32At(at + 16)
    report.hexField(at + 16, 4, "AddressOfEntryPoint", cast(u64) entry, entry ? "" : s.pe_NoEntry)
    report.hexField(at + 20, 4, "BaseOfCode", cast(u64) image.u32At(at + 20))

    if !layout.is64
    {
        report.hexField(at + 24, 4, "BaseOfData", cast(u64) image.u32At(at + 24))
        layout.imageBase = cast(u64) image.u32At(at + 28)
        report.hexField(at + 28, 4, "ImageBase", layout.imageBase, s.pe_PreferredBase)
    }
    else
    {
        layout.imageBase = image.u64At(at + 24)
        report.hexField(at + 24, 8, "ImageBase", layout.imageBase, s.pe_PreferredBase)
    }

    // From here the two forms agree again, until the four stack and heap sizes.
    let windowsAt = at + 32
    report.sizeField(windowsAt, 4, "SectionAlignment", cast(u64) image.u32At(windowsAt), s.pe_InMemory)
    report.sizeField(windowsAt + 4, 4, "FileAlignment", cast(u64) image.u32At(windowsAt + 4), s.pe_OnDisk)

    let osVersion = Format.toString("%.%", image.u16At(windowsAt + 8), image.u16At(windowsAt + 10))
    report.field(windowsAt + 8, 4, "OperatingSystemVersion", osVersion.toString())
    let imageVersion = Format.toString("%.%", image.u16At(windowsAt + 12), image.u16At(windowsAt + 14))
    report.field(windowsAt + 12, 4, "ImageVersion", imageVersion.toString())
    let subsystemVersion = Format.toString("%.%", image.u16At(windowsAt + 16), image.u16At(windowsAt + 18))
    report.field(windowsAt + 16, 4, "SubsystemVersion", subsystemVersion.toString())
    report.hexField(windowsAt + 20, 4, "Win32VersionValue", cast(u64) image.u32At(windowsAt + 20))

    layout.sizeOfHeaders = image.u32At(windowsAt + 28)
    report.sizeField(windowsAt + 24, 4, "SizeOfImage", cast(u64) image.u32At(windowsAt + 24), s.pe_Reserved)
    report.sizeField(windowsAt + 28, 4, "SizeOfHeaders", cast(u64) layout.sizeOfHeaders)

    let checksum = image.u32At(windowsAt + 32)
    report.hexField(windowsAt + 32, 4, "CheckSum", cast(u64) checksum, checksum ? "" : s.pe_NoChecksum)

    let subsystem = image.u16At(windowsAt + 36)
    let dllFlags  = image.u16At(windowsAt + 38)
    let dllText   = peDllCharacteristicsText(dllFlags)
    report.numField(windowsAt + 36, 2, "Subsystem", cast(u64) subsystem, peSubsystemName(subsystem))
    report.hexField(windowsAt + 38, 2, "DllCharacteristics", cast(u64) dllFlags, dllText.toString())

    let wide    = layout.pointerSize()
    let stackAt = windowsAt + 40
    report.sizeField(stackAt, wide, "SizeOfStackReserve", image.scalarAt(stackAt, wide))
    report.sizeField(stackAt + wide, wide, "SizeOfStackCommit", image.scalarAt(stackAt + wide, wide))
    report.sizeField(stackAt + wide * 2, wide, "SizeOfHeapReserve", image.scalarAt(stackAt + wide * 2, wide))
    report.sizeField(stackAt + wide * 3, wide, "SizeOfHeapCommit", image.scalarAt(stackAt + wide * 3, wide))

    let tailAt = stackAt + wide * 4
    report.hexField(tailAt, 4, "LoaderFlags", cast(u64) image.u32At(tailAt))

    let directoryCount = cast(u64) image.u32At(tailAt + 4)
    report.numField(tailAt + 4, 4, "NumberOfRvaAndSizes", directoryCount)
    reportPeDirectories(image, report, tailAt + 8, directoryCount, layout)
    report.endGroup()
}

private func reportPeDirectories(image: *BinaryImage, report: *BinaryReport, at, count: u64, layout: *PeLayout)
{
    let s       = binStrings()
    let shown   = Math.min(count, 16'u64)
    let entries = countText(shown, s.word_Entry, s.word_Entries)

    report.beginGroup(s.pe_Directories, entries.toString(), "", offset: at, length: shown * 8)

    for index in shown
    {
        let entryAt = at + index * 8
        let rva     = image.u32At(entryAt)
        let size    = image.u32At(entryAt + 4)
        let value   = rva ? Format.toString("% · %", hexText(cast(u64) rva, 8), StrConv.toDisplaySize(cast(u64) size)) : String.from(s.pe_DirEmpty)
        report.field(entryAt, 8, peDirectoryName(index), value.toString(), rva ? layout.sectionNameOf(rva) : "")
    }

    report.endGroup()
}

private func reportPeSections(image: *BinaryImage, report: *BinaryReport, at: u64, count: u16, layout: *PeLayout)
{
    let s        = binStrings()
    let total    = Math.min(cast(u64) count, BinaryListLimit)
    let sections = countText(cast(u64) count, s.word_Section, s.word_Sections)

    report.beginGroup(s.shr_Sections, sections.toString(), "", offset: at, length: total * PeSectionHeaderSize, open: true)

    for index in total
    {
        let entryAt = at + index * PeSectionHeaderSize

        var section: PeSection
        section.name        = image.fixedTextAt(entryAt, 8)
        section.virtualSize = image.u32At(entryAt + 8)
        section.virtualAddr = image.u32At(entryAt + 12)
        section.rawSize     = image.u32At(entryAt + 16)
        section.rawOffset   = image.u32At(entryAt + 20)

        let flags   = image.u32At(entryAt + 36)
        let names   = peSectionFlagsText(flags)
        let address = hexText(cast(u64) section.virtualAddr, 8)
        let stored  = StrConv.toDisplaySize(cast(u64) section.rawSize)

        // The group covers the bytes the section stores rather than its header, so a search hit
        // anywhere inside a payload lands on the section that owns it.
        report.beginGroup(section.name.toString(), address.toString(), stored.toString(), offset: cast(u64) section.rawOffset, length: cast(u64) section.rawSize)
        report.sizeField(entryAt + 8, 4, "VirtualSize", cast(u64) section.virtualSize)
        report.hexField(entryAt + 12, 4, "VirtualAddress", cast(u64) section.virtualAddr)
        report.sizeField(entryAt + 16, 4, "SizeOfRawData", cast(u64) section.rawSize)
        report.hexField(entryAt + 20, 4, "PointerToRawData", cast(u64) section.rawOffset)
        report.hexField(entryAt + 24, 4, "PointerToRelocations", cast(u64) image.u32At(entryAt + 24))
        report.hexField(entryAt + 28, 4, "PointerToLinenumbers", cast(u64) image.u32At(entryAt + 28))
        report.numField(entryAt + 32, 2, "NumberOfRelocations", cast(u64) image.u16At(entryAt + 32))
        report.numField(entryAt + 34, 2, "NumberOfLinenumbers", cast(u64) image.u16At(entryAt + 34))
        report.hexField(entryAt + 36, 4, "Characteristics", cast(u64) flags, names.toString())
        report.endGroup()

        layout.sections.add(#move section)
    }

    report.listCut(total, cast(u64) count)
    report.endGroup()
}

// Returns the address and size one data directory holds, or zeros when the image has no such entry.
private func peDirectory(image: *BinaryImage, layout: *PeLayout, index: u64)->{ rva: u32, size: u32 }
{
    // The directories are read back out of the optional header rather than carried along: the
    // layout is what every caller already holds, and it is what says where the table starts.
    let peOffset  = cast(u64) image.u32At(PeLfanewOffset)
    let optional  = peOffset + 4 + PeFileHeaderSize
    let available = cast(u64) image.u32At(optional + (layout.is64 ? 108'u64 : 92))
    if index >= available do
        return {0, 0}

    let entryAt = optional + (layout.is64 ? 112'u64 : 96) + index * 8
    return {image.u32At(entryAt), image.u32At(entryAt + 4)}
}

private func reportPeExports(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 0)
    if !rva do
        return

    let s  = binStrings()
    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max
    {
        report.note(s.pe_ExportOutside)
        return
    }

    let base       = cast(u64) image.u32At(at + 16)
    let funcCount  = cast(u64) image.u32At(at + 20)
    let nameCount  = cast(u64) image.u32At(at + 24)
    let funcAt     = layout.offsetOf(image.u32At(at + 28))
    let nameAt     = layout.offsetOf(image.u32At(at + 32))
    let ordinalAt  = layout.offsetOf(image.u32At(at + 36))
    let moduleName = peStringAt(image, layout, image.u32At(at + 12))
    let entries    = countText(funcCount, s.word_Entry, s.word_Entries)
    let stamp      = epochText(cast(u64) image.u32At(at + 4))
    let version    = Format.toString("%.%", image.u16At(at + 8), image.u16At(at + 10))

    report.beginGroup(s.shr_Exports, moduleName.toString(), entries.toString(), offset: at, length: cast(u64) size, open: true)
    report.hexField(at, 4, "Characteristics", cast(u64) image.u32At(at))
    report.field(at + 4, 4, "TimeDateStamp", stamp.toString())
    report.field(at + 8, 4, "Version", version.toString())
    report.field(at + 12, 4, "Name", moduleName.toString(), s.pe_ExportName)
    report.numField(at + 16, 4, "Base", base, s.pe_ExportBase)
    report.numField(at + 20, 4, "NumberOfFunctions", funcCount)
    report.numField(at + 24, 4, "NumberOfNames", nameCount)

    if funcAt == Swag.U64.Max
    {
        report.note(s.pe_ExportTableOut)
        report.endGroup()
        return
    }

    // A name is what a linker binds against, so the named entries come first and in their own
    // order; the ordinal-only ones follow, because nothing can reach them by name.
    var named: HashSet'u32
    let shown = Math.min(nameCount, BinaryListLimit)
    if nameAt != Swag.U64.Max and ordinalAt != Swag.U64.Max
    {
        let symbols = countText(nameCount, s.word_Symbol, s.word_Symbols)
        report.beginGroup(s.pe_ByName, symbols.toString(), "", offset: nameAt, length: nameCount * 4, open: true)

        for index in shown
        {
            let ordinal = image.u16At(ordinalAt + index * 2)
            named.add(cast(u32) ordinal)
            let symbol = peStringAt(image, layout, image.u32At(nameAt + index * 4))
            let target = peExportTarget(image, layout, image.u32At(funcAt + cast(u64) ordinal * 4), rva, size)
            let value  = Format.toString(s.pe_Ordinal, cast(u64) ordinal + base)
            report.field(nameAt + index * 4, 4, symbol.toString(), value.toString(), target.toString())
        }

        report.listCut(shown, nameCount)
        report.endGroup()
    }

    var anonymous = 0'u64
    for index in Math.min(funcCount, BinaryListLimit) where !named.contains(cast(u32) index)
    {
        let address = image.u32At(funcAt + index * 4)
        if !address do
            continue
        if !anonymous do
            report.beginGroup(s.pe_ByOrdinal, "", s.pe_ByOrdinalDesc)

        anonymous += 1
        let label  = Format.toString(s.pe_Ordinal, index + base)
        let value  = hexText(cast(u64) address, 8)
        let target = peExportTarget(image, layout, address, rva, size)
        report.field(funcAt + index * 4, 4, label.toString(), value.toString(), target.toString())
    }

    if anonymous do
        report.endGroup()
    report.endGroup()
}

// Returns what an export address points at: another module's symbol, or a place in this image.
private func peExportTarget(image: *BinaryImage, layout: *PeLayout, target, directoryRva, directorySize: u32)->String
{
    let s = binStrings()
    if !target do
        return String.from(s.pe_NotExported)

    // An address inside the export directory itself is not code: it is the name of the symbol
    // another module is expected to answer with.
    if target >= directoryRva and target - directoryRva < directorySize
    {
        let forward = peStringAt(image, layout, target)
        return Format.toString(s.pe_Forwarded, forward)
    }

    return String.from(layout.sectionNameOf(target))
}

private func reportPeImports(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 1)
    if !rva do
        return

    let s  = binStrings()
    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max
    {
        report.note(s.pe_ImportOutside)
        return
    }

    // The table ends at an all-zero descriptor, so its length is counted before the first module is
    // written: the group has to name how many there are before it holds any of them.
    var entries: Array'u64
    while entries.count < BinaryListLimit
    {
        let entryAt = at + entries.count * 20
        if !image.has(entryAt, 20) do
            break
        if !image.u32At(entryAt) and !image.u32At(entryAt + 12) and !image.u32At(entryAt + 16) do
            break
        entries.add(entryAt)
    }

    let modules = countText(entries.count, s.word_Module, s.word_Modules)
    report.beginGroup(s.shr_Imports, modules.toString(), "", offset: at, length: cast(u64) size, open: true)

    var symbols = 0'u64
    for entryAt in entries
    {
        let lookup = image.u32At(entryAt)
        let thunks = image.u32At(entryAt + 16)
        let name   = peStringAt(image, layout, image.u32At(entryAt + 12))

        // A bound image drops its lookup table and keeps only the address table, so the names are
        // read from whichever of the two the image still carries.
        let table = lookup ? lookup : thunks
        symbols += reportPeThunks(image, report, layout, cast(u32) table, name.toString(), entryAt, thunks)
    }

    let total = Format.toString("% %", symbols, s.pe_ImportSymbols)
    report.derived(s.pe_ImportTotal, total.toString())
    report.endGroup()
}

// Adds one imported module and the symbols its thunk table names, and returns how many there were.
private func reportPeThunks(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout, tableRva: u32, moduleName: string, entryAt: u64, iat: u32)->u64
{
    let s       = binStrings()
    let tableAt = layout.offsetOf(tableRva)
    let wide    = layout.pointerSize()
    let ordinal = wide == 8 ? 0x8000000000000000'u64 : 0x80000000'u64

    var count = 0'u64
    if tableAt != Swag.U64.Max
    {
        while count < BinaryListLimit and image.scalarAt(tableAt + count * wide, wide) do
            count += 1
    }

    let stamp   = image.u32At(entryAt + 4)
    let symbols = countText(count, s.word_Symbol, s.word_Symbols)

    report.beginGroup(moduleName, symbols.toString(), "", offset: entryAt, length: 20)
    report.hexField(entryAt, 4, "OriginalFirstThunk", cast(u64) image.u32At(entryAt), s.pe_ImportLookup)
    report.hexField(entryAt + 4, 4, "TimeDateStamp", cast(u64) stamp, stamp ? s.pe_Bound : s.pe_Unbound)
    report.hexField(entryAt + 8, 4, "ForwarderChain", cast(u64) image.u32At(entryAt + 8))
    report.hexField(entryAt + 16, 4, "FirstThunk", cast(u64) iat, s.pe_ImportAddress)

    if tableAt == Swag.U64.Max
    {
        report.note(s.pe_ThunkOutside)
        report.endGroup()
        return 0
    }

    for index in count
    {
        let thunkAt = tableAt + index * wide
        let value   = image.scalarAt(thunkAt, wide)
        if value & ordinal
        {
            let label = Format.toString(s.pe_Ordinal, value & 0xFFFF)
            report.field(thunkAt, wide, label.toString(), "", s.pe_ByOrdinalBind)
            continue
        }

        let hintAt = layout.offsetOf(cast(u32) value)
        if hintAt == Swag.U64.Max
        {
            let label = hexText(value, 8)
            report.field(thunkAt, wide, label.toString(), "", s.pe_Outside)
            continue
        }

        let symbol = image.cstringAt(hintAt + 2)
        let hint   = Format.toString(s.pe_Hint, image.u16At(hintAt))
        report.field(thunkAt, wide, symbol.toString(), "", hint.toString())
    }

    report.endGroup()
    return count
}

private func reportPeDelayImports(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 13)
    if !rva do
        return

    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return

    let s       = binStrings()
    var modules = 0'u64
    report.beginGroup(s.pe_Delayed, "", s.pe_DelayedDesc, offset: at, length: cast(u64) size)

    while modules < BinaryListLimit
    {
        let entryAt = at + modules * 32
        if !image.has(entryAt, 32) or !image.u32At(entryAt + 4) do
            break

        // The first delay-load format stored virtual addresses; the current one stores addresses
        // relative to the image, and its attributes say which.
        let relative = image.u32At(entryAt) & 1
        let stored   = cast(u64) image.u32At(entryAt + 4)
        let nameRva  = relative ? stored : (stored > layout.imageBase ? stored - layout.imageBase : stored)
        let name     = peStringAt(image, layout, cast(u32) nameRva)
        let stamp    = epochText(cast(u64) image.u32At(entryAt + 28))

        report.beginGroup(name.toString(), "", "", offset: entryAt, length: 32)
        report.hexField(entryAt, 4, "Attributes", cast(u64) image.u32At(entryAt), relative ? s.pe_DelayRelative : s.pe_DelayAbsolute)
        report.hexField(entryAt + 8, 4, "ModuleHandle", cast(u64) image.u32At(entryAt + 8))
        report.hexField(entryAt + 12, 4, "ImportAddressTable", cast(u64) image.u32At(entryAt + 12))
        report.hexField(entryAt + 16, 4, "ImportNameTable", cast(u64) image.u32At(entryAt + 16))
        report.field(entryAt + 28, 4, "TimeDateStamp", stamp.toString())
        report.endGroup()
        modules += 1
    }

    report.endGroup()
}

private func reportPeResources(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 2)
    if !rva do
        return

    let s  = binStrings()
    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max
    {
        report.note(s.pe_ResourceOut)
        return
    }

    report.beginGroup(s.pe_Resources, "", "", offset: at, length: cast(u64) size, open: true)
    reportPeVersionResource(image, report, layout, at)
    reportPeResourceLevel(image, report, layout, at, at, 0)
    report.endGroup()
}

// Walks one level of the resource tree: types, then names, then languages.
private func reportPeResourceLevel(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout, base, at: u64, depth: u32)
{
    if depth > 2 or !image.has(at, 16) do
        return

    let s        = binStrings()
    let declared = cast(u64) image.u16At(at + 12) + cast(u64) image.u16At(at + 14)
    let total    = Math.min(declared, BinaryListLimit)

    for index in total
    {
        let entryAt = at + 16 + index * 8
        let nameId  = image.u32At(entryAt)
        let child   = image.u32At(entryAt + 4)
        let label   = peResourceLabel(image, base, nameId, depth)

        if child & 0x80000000
        {
            report.beginGroup(label.toString(), "", "", offset: entryAt, length: 8)
            reportPeResourceLevel(image, report, layout, base, base + cast(u64) (child & 0x7FFFFFFF), depth + 1)
            report.endGroup()
            continue
        }

        // A leaf names its bytes rather than holding them, and those bytes are addressed the way
        // everything else in the image is.
        let leafAt  = base + cast(u64) child
        let dataRva = image.u32At(leafAt)
        let dataAt  = layout.offsetOf(dataRva)
        let dataLen = cast(u64) image.u32At(leafAt + 4)
        let value   = StrConv.toDisplaySize(dataLen)
        let detail  = Format.toString(s.pe_ResourceWhere, image.u32At(leafAt + 8), hexText(cast(u64) dataRva, 8))
        report.field(dataAt == Swag.U64.Max ? leafAt : dataAt, dataAt == Swag.U64.Max ? 16 : dataLen, label.toString(), value.toString(), detail.toString())
    }

    report.listCut(total, declared)
}

// Returns how one resource entry is named at its level of the tree.
private func peResourceLabel(image: *BinaryImage, base: u64, nameId: u32, depth: u32)->String
{
    let s = binStrings()
    if nameId & 0x80000000
    {
        let stringAt = base + cast(u64) (nameId & 0x7FFFFFFF)
        let length   = cast(u64) image.u16At(stringAt)
        var text     = image.wideTextAt(stringAt + 2, Math.min(length, 128'u64))
        if text.isEmpty() do
            text = String.from(s.pe_Unnamed)
        return text
    }

    if !depth
    {
        let standard = peResourceTypeName(nameId)
        if standard.count do
            return Format.toString("% (%)", standard, nameId)
        return Format.toString(s.pe_ResourceType, nameId)
    }

    if depth == 1 do
        return Format.toString(s.pe_ResourceId, nameId)
    return Format.toString(s.pe_ResourceLang, hexText(cast(u64) nameId, 4))
}

// Adds the version block Windows shows in a file's property page.
//
// It is the one resource whose content is meant to be read by a person, so it is decoded rather
// than merely located: product and file version, company, description, and copyright.
private func reportPeVersionResource(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout, base: u64)
{
    let dataAt = peFindResourceData(image, layout, base, 16)
    if dataAt == Swag.U64.Max do
        return

    // VS_VERSIONINFO is a length, a value length, a type, the key `VS_VERSION_INFO`, then the fixed
    // block on the next four-byte boundary.
    let s           = binStrings()
    let valueLength = cast(u64) image.u16At(dataAt + 2)
    let fixedAt     = peAlign4(dataAt + 6 + 32, dataAt)
    if !valueLength or image.u32At(fixedAt) != 0xFEEF04BD
    {
        report.note(s.pe_VersionMissing)
        return
    }

    let fileVersion    = peVersionText(image.u32At(fixedAt + 8), image.u32At(fixedAt + 12))
    let productVersion = peVersionText(image.u32At(fixedAt + 16), image.u32At(fixedAt + 20))
    let flags          = image.u32At(fixedAt + 28) & image.u32At(fixedAt + 24)
    let names          = peVersionFlagsText(flags)
    let fileType       = image.u32At(fixedAt + 36)

    report.beginGroup(s.pe_Version, "", s.pe_VersionDesc, offset: dataAt, length: cast(u64) image.u16At(dataAt), open: true)
    report.field(fixedAt + 8, 8, "FileVersion", fileVersion.toString())
    report.field(fixedAt + 16, 8, "ProductVersion", productVersion.toString())
    report.hexField(fixedAt + 28, 4, "FileFlags", cast(u64) flags, names.toString())
    report.hexField(fixedAt + 32, 4, "FileOS", cast(u64) image.u32At(fixedAt + 32))
    report.numField(fixedAt + 36, 4, "FileType", cast(u64) fileType, peVersionFileTypeName(fileType))
    reportPeVersionStrings(image, report, dataAt, fixedAt + 52)
    report.endGroup()
}

// Adds every `name = value` pair the version resource's string tables carry.
private func reportPeVersionStrings(image: *BinaryImage, report: *BinaryReport, blockAt, childAt: u64)
{
    let blockEnd = blockAt + cast(u64) image.u16At(blockAt)
    var at       = peAlign4(childAt, blockAt)
    var written  = 0'u64

    while at + 6 <= blockEnd and written < BinaryListLimit
    {
        let length = cast(u64) image.u16At(at)
        if length < 6 do
            break

        let key = image.wideTextAt(at + 6, 64)
        if key == "StringFileInfo"
        {
            // A string block is a language and a code page, and under it the pairs themselves.
            var tableAt = peAlign4(at + 6 + (key.length + 1) * 2, blockAt)
            while tableAt + 6 <= at + length
            {
                let tableLength = cast(u64) image.u16At(tableAt)
                if tableLength < 6 do
                    break

                let language = image.wideTextAt(tableAt + 6, 32)
                var pairAt   = peAlign4(tableAt + 6 + (language.length + 1) * 2, blockAt)
                while pairAt + 6 <= tableAt + tableLength and written < BinaryListLimit
                {
                    let pairLength = cast(u64) image.u16At(pairAt)
                    if pairLength < 6 do
                        break

                    let name    = image.wideTextAt(pairAt + 6, 128)
                    let valueAt = peAlign4(pairAt + 6 + (name.length + 1) * 2, blockAt)
                    let value   = image.wideTextAt(valueAt, Math.min(cast(u64) image.u16At(pairAt + 2), 512'u64))
                    if !name.isEmpty()
                    {
                        report.field(pairAt, pairLength, name.toString(), value.toString(), language.toString())
                        written += 1
                    }

                    pairAt = peAlign4(pairAt + pairLength, blockAt)
                }

                tableAt = peAlign4(tableAt + tableLength, blockAt)
            }
        }

        at = peAlign4(at + length, blockAt)
    }
}

// Rounds `value` up to the four-byte boundary the version format aligns every block on.
private func peAlign4(value, base: u64)->u64
{
    return base + ((value - base + 3) & ~3'u64)
}

private func peVersionText(high, low: u32)->String
{
    return Format.toString("%.%.%.%", high >> 16, high & 0xFFFF, low >> 16, low & 0xFFFF)
}

private func peVersionFlagsText(value: u32)->String
{
    let names = [BinaryFlagName{0x01, "DEBUG"},
                 BinaryFlagName{0x02, "PRERELEASE"},
                 BinaryFlagName{0x04, "PATCHED"},
                 BinaryFlagName{0x08, "PRIVATEBUILD"},
                 BinaryFlagName{0x10, "INFOINFERRED"},
                 BinaryFlagName{0x20, "SPECIALBUILD"}]
    return flagsText(cast(u64) value, names)
}

private func peVersionFileTypeName(value: u32)->string
{
    switch value
    {
    case 1: return "VFT_APP"
    case 2: return "VFT_DLL"
    case 3: return "VFT_DRV"
    case 4: return "VFT_FONT"
    case 5: return "VFT_VXD"
    case 7: return "VFT_STATIC_LIB"
    }

    return "VFT_UNKNOWN"
}

// Returns the file offset of the first leaf of resource type `wanted`.
private func peFindResourceData(image: *BinaryImage, layout: *PeLayout, base: u64, wanted: u32)->u64
{
    if !image.has(base, 16) do
        return Swag.U64.Max

    let typeCount = cast(u64) image.u16At(base + 12) + cast(u64) image.u16At(base + 14)
    for index in Math.min(typeCount, BinaryListLimit)
    {
        let entryAt = base + 16 + index * 8
        if image.u32At(entryAt) != wanted do
            continue

        let nameDir = image.u32At(entryAt + 4)
        if !(nameDir & 0x80000000) do
            return Swag.U64.Max

        let nameAt = base + cast(u64) (nameDir & 0x7FFFFFFF)
        if !image.has(nameAt, 24) do
            return Swag.U64.Max

        let langDir = image.u32At(nameAt + 20)
        if !(langDir & 0x80000000) do
            return Swag.U64.Max

        let langAt = base + cast(u64) (langDir & 0x7FFFFFFF)
        if !image.has(langAt, 24) do
            return Swag.U64.Max

        let leafAt = base + cast(u64) image.u32At(langAt + 20)
        return layout.offsetOf(image.u32At(leafAt))
    }

    return Swag.U64.Max
}

private func reportPeDebug(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 6)
    if !rva do
        return

    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return

    let s       = binStrings()
    let count   = Math.min(cast(u64) size / 28, BinaryListLimit)
    let entries = countText(count, s.word_Entry, s.word_Entries)

    report.beginGroup(s.pe_Debug, entries.toString(), "", offset: at, length: cast(u64) size, open: true)

    for index in count
    {
        let entryAt = at + index * 28
        let kind    = image.u32At(entryAt + 12)
        let dataLen = cast(u64) image.u32At(entryAt + 16)
        let dataAt  = cast(u64) image.u32At(entryAt + 24)
        let stamp   = epochText(cast(u64) image.u32At(entryAt + 4))
        let version = Format.toString("%.%", image.u16At(entryAt + 8), image.u16At(entryAt + 10))
        let stored  = StrConv.toDisplaySize(dataLen)

        report.beginGroup(peDebugTypeName(kind), "", "", offset: entryAt, length: 28, open: kind == 2)
        report.field(entryAt + 4, 4, "TimeDateStamp", stamp.toString())
        report.field(entryAt + 8, 4, "Version", version.toString())
        report.numField(entryAt + 12, 4, "Type", cast(u64) kind, peDebugTypeName(kind))
        report.field(entryAt + 16, 4, "SizeOfData", stored.toString())
        report.hexField(entryAt + 20, 4, "AddressOfRawData", cast(u64) image.u32At(entryAt + 20))
        report.hexField(entryAt + 24, 4, "PointerToRawData", dataAt)

        // A CodeView record is what pairs the image with its symbol file, and the pair only holds
        // when the identity and the age both match.
        if kind == 2 and image.matches(dataAt, "RSDS")
        {
            let identity = guidText(image, dataAt + 4)
            let path     = image.cstringAt(dataAt + 24)
            report.field(dataAt + 4, 16, "GUID", identity.toString(), s.pe_DebugIdentity)
            report.numField(dataAt + 20, 4, "Age", cast(u64) image.u32At(dataAt + 20))
            report.field(dataAt + 24, dataLen > 24 ? dataLen - 24 : 0, "PDB", path.toString())
        }

        report.endGroup()
    }

    report.endGroup()
}

private func reportPeExceptions(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 3)
    if !rva do
        return

    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return

    // Each record covers one function, so the count is how many functions the image can unwind.
    let s       = binStrings()
    let records = countText(cast(u64) size / 12, s.word_Record, s.word_Records)

    report.beginGroup(s.pe_Exception, records.toString(), "", offset: at, length: cast(u64) size)
    report.hexField(at, 4, "Address", cast(u64) rva, layout.sectionNameOf(rva))
    report.derived(s.pe_Coverage, records.toString(), s.pe_ExceptionDesc)
    report.endGroup()
}

private func reportPeRelocations(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 5)
    if !rva do
        return

    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return

    let end    = at + cast(u64) size
    var blocks = 0'u64
    var fixups = 0'u64
    var scan   = at

    while scan + 8 <= end and blocks < BinaryListLimit
    {
        let blockSize = cast(u64) image.u32At(scan + 4)
        if blockSize < 8 do
            break
        fixups += (Math.min(blockSize, end - scan) - 8) / 2
        blocks += 1
        scan   += blockSize
    }

    let s       = binStrings()
    let pages   = countText(blocks, s.word_Page, s.word_Pages)
    let entries = countText(fixups, s.word_Fixup, s.word_Fixups)

    report.beginGroup(s.pe_Relocations, pages.toString(), entries.toString(), offset: at, length: cast(u64) size)
    report.hexField(at, 4, "Address", cast(u64) rva, layout.sectionNameOf(rva))
    report.derived(s.pe_Pages, pages.toString())
    report.derived(s.pe_Fixups, entries.toString())
    report.endGroup()
}

private func reportPeTls(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 9)
    if !rva do
        return

    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return

    let wide = layout.pointerSize()
    report.beginGroup(binStrings().pe_Tls, "", "", offset: at, length: cast(u64) size)
    report.hexField(at, wide, "StartAddressOfRawData", image.scalarAt(at, wide))
    report.hexField(at + wide, wide, "EndAddressOfRawData", image.scalarAt(at + wide, wide))
    report.hexField(at + wide * 2, wide, "AddressOfIndex", image.scalarAt(at + wide * 2, wide))
    report.hexField(at + wide * 3, wide, "AddressOfCallBacks", image.scalarAt(at + wide * 3, wide))
    report.sizeField(at + wide * 4, 4, "SizeOfZeroFill", cast(u64) image.u32At(at + wide * 4))
    report.hexField(at + wide * 4 + 4, 4, "Characteristics", cast(u64) image.u32At(at + wide * 4 + 4))
    report.endGroup()
}

private func reportPeLoadConfig(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 10)
    if !rva do
        return

    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return

    let s        = binStrings()
    let declared = cast(u64) image.u32At(at)
    let wide     = layout.pointerSize()
    let cookieAt = at + (layout.is64 ? 88'u64 : 60)
    let guardAt  = at + (layout.is64 ? 144'u64 : 88)
    let stamp    = epochText(cast(u64) image.u32At(at + 4))
    let version  = Format.toString("%.%", image.u16At(at + 8), image.u16At(at + 10))
    let stored   = StrConv.toDisplaySize(declared)

    report.beginGroup(s.pe_LoadConfig, stored.toString(), "", offset: at, length: Math.max(declared, cast(u64) size))
    report.numField(at, 4, "Size", declared)
    report.field(at + 4, 4, "TimeDateStamp", stamp.toString())
    report.field(at + 8, 4, "Version", version.toString())
    report.hexField(at + 12, 4, "GlobalFlagsClear", cast(u64) image.u32At(at + 12))
    report.hexField(at + 16, 4, "GlobalFlagsSet", cast(u64) image.u32At(at + 16))

    if declared > cookieAt - at do
        report.hexField(cookieAt, wide, "SecurityCookie", image.scalarAt(cookieAt, wide), s.pe_Cookie)

    if declared > guardAt + 4 - at
    {
        let guard = image.u32At(guardAt)
        let names = peGuardFlagsText(guard)
        report.hexField(guardAt, 4, "GuardFlags", cast(u64) guard, names.toString())
    }

    report.endGroup()
}

private func peGuardFlagsText(value: u32)->String
{
    let names = [BinaryFlagName{0x00000100, "CF_INSTRUMENTED"},
                 BinaryFlagName{0x00000200, "CFW_INSTRUMENTED"},
                 BinaryFlagName{0x00000400, "CF_FUNCTION_TABLE_PRESENT"},
                 BinaryFlagName{0x00000800, "SECURITY_COOKIE_UNUSED"},
                 BinaryFlagName{0x00001000, "PROTECT_DELAYLOAD_IAT"},
                 BinaryFlagName{0x00002000, "DELAYLOAD_IAT_IN_ITS_OWN_SECTION"},
                 BinaryFlagName{0x00004000, "CF_EXPORT_SUPPRESSION_INFO_PRESENT"},
                 BinaryFlagName{0x00008000, "CF_ENABLE_EXPORT_SUPPRESSION"},
                 BinaryFlagName{0x00010000, "CF_LONGJUMP_TABLE_PRESENT"},
                 BinaryFlagName{0x00020000, "EH_CONTINUATION_TABLE_PRESENT"},
                 BinaryFlagName{0x00040000, "RETPOLINE_PRESENT"},
                 BinaryFlagName{0x00400000, "XFG_ENABLED"}]
    return flagsText(cast(u64) value, names)
}

private func reportPeClr(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 14)
    if !rva do
        return

    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return

    let s       = binStrings()
    let metaRva = image.u32At(at + 8)
    let metaAt  = layout.offsetOf(metaRva)
    let runtime = Format.toString("%.%", image.u16At(at + 4), image.u16At(at + 6))
    let meta    = Format.toString("% · %", hexText(cast(u64) metaRva, 8), StrConv.toDisplaySize(cast(u64) image.u32At(at + 12)))
    let flags   = image.u32At(at + 16)
    let names   = peClrFlagsText(flags)

    report.beginGroup(s.pe_Clr, s.pe_ClrManaged, "", offset: at, length: cast(u64) size, open: true)
    report.field(at + 4, 4, "RuntimeVersion", runtime.toString())
    report.field(at + 8, 8, "MetaData", meta.toString())
    report.hexField(at + 16, 4, "Flags", cast(u64) flags, names.toString())
    report.hexField(at + 20, 4, "EntryPointToken", cast(u64) image.u32At(at + 20))

    // The metadata root records which runtime built the assembly, in a length-prefixed name.
    if metaAt != Swag.U64.Max and image.matches(metaAt, "BSJB")
    {
        let target = image.cstringAt(metaAt + 16, 64)
        report.field(metaAt + 16, cast(u64) image.u32At(metaAt + 12), "Version", target.toString(), s.pe_ClrRuntime)
    }

    report.endGroup()
}

private func peClrFlagsText(value: u32)->String
{
    let names = [BinaryFlagName{0x00000001, "ILONLY"},
                 BinaryFlagName{0x00000002, "32BITREQUIRED"},
                 BinaryFlagName{0x00000004, "IL_LIBRARY"},
                 BinaryFlagName{0x00000008, "STRONGNAMESIGNED"},
                 BinaryFlagName{0x00000010, "NATIVE_ENTRYPOINT"},
                 BinaryFlagName{0x00010000, "TRACKDEBUGDATA"},
                 BinaryFlagName{0x00020000, "32BITPREFERRED"}]
    return flagsText(cast(u64) value, names)
}

// Adds the signature block, the one directory addressed by a file offset rather than an address:
// it is appended after the image and is deliberately not mapped at load time.
private func reportPeCertificates(image: *BinaryImage, report: *BinaryReport, layout: *PeLayout)
{
    let {rva, size} = peDirectory(image, layout, 4)
    if !rva or !size do
        return

    let s      = binStrings()
    let at     = cast(u64) rva
    let end    = at + cast(u64) size
    let stored = StrConv.toDisplaySize(cast(u64) size)
    var scan   = at
    var count  = 0'u64

    report.beginGroup(s.pe_Certificates, stored.toString(), s.pe_CertificateAt, offset: at, length: cast(u64) size)

    while scan + 8 <= end and count < BinaryListLimit
    {
        let length = cast(u64) image.u32At(scan)
        if length < 8 do
            break

        let label = Format.toString(s.pe_Certificate, count)
        let value = StrConv.toDisplaySize(length)
        report.field(scan, length, label.toString(), value.toString(), peCertificateTypeName(image.u16At(scan + 6)))
        count += 1
        scan  += (length + 7) & ~7'u64
    }

    if !count do
        report.note(s.pe_CertificateNo)
    report.endGroup()
}

private func peCertificateTypeName(value: u16)->string
{
    switch value
    {
    case 1: return "X.509"
    case 2: return "PKCS#7"
    case 4: return "PKCS#1"
    }

    return "?"
}

// Returns the text an address points at, or a placeholder when nothing in the file holds it.
private func peStringAt(image: *BinaryImage, layout: *PeLayout, rva: u32)->String
{
    let at = layout.offsetOf(rva)
    if at == Swag.U64.Max do
        return String.from(BinaryNoValue)
    return image.cstringAt(at)
}

// Adds the symbols of a COFF object, which is the only part of it a linker actually matches on.
private func reportCoffSymbols(image: *BinaryImage, report: *BinaryReport, at, count: u64)
{
    if !at or !count do
        return

    // The string table sits right after the symbols and opens with its own total size, which is how
    // a name longer than eight bytes is reached.
    let s         = binStrings()
    let stringsAt = at + count * PeSymbolSize
    let shown     = Math.min(count, BinaryListLimit)
    let symbols   = countText(count, s.word_Symbol, s.word_Symbols)
    let strings   = StrConv.toDisplaySize(cast(u64) image.u32At(stringsAt))

    report.beginGroup(s.pe_Symbols, symbols.toString(), "", offset: at, length: count * PeSymbolSize)
    report.field(stringsAt, 4, s.pe_StringTable, strings.toString())

    var index = 0'u64
    while index < shown
    {
        let entryAt = at + index * PeSymbolSize
        var name    = image.fixedTextAt(entryAt, 8)
        if !image.u32At(entryAt) do
            name = image.cstringAt(stringsAt + cast(u64) image.u32At(entryAt + 4))

        let section = cast #bit (s16) image.u16At(entryAt + 12)
        let value   = hexText(cast(u64) image.u32At(entryAt + 8), 8)
        let detail  = Format.toString(s.pe_SymbolWhere, coffStorageClassName(image.u8At(entryAt + 16)), section)
        report.field(entryAt, PeSymbolSize, name.toString(), value.toString(), detail.toString())

        // Auxiliary records belong to the symbol before them and carry no name of their own.
        index += 1 + cast(u64) image.u8At(entryAt + 17)
    }

    report.listCut(index, count)
    report.endGroup()
}

private func coffStorageClassName(value: u8)->string
{
    switch value
    {
    case 2:   return "EXTERNAL"
    case 3:   return "STATIC"
    case 4:   return "REGISTER"
    case 5:   return "EXTERNAL_DEF"
    case 6:   return "LABEL"
    case 100: return "BLOCK"
    case 101: return "FUNCTION"
    case 103: return "FILE"
    case 104: return "SECTION"
    case 105: return "WEAK_EXTERNAL"
    }

    return "CLASS"
}
