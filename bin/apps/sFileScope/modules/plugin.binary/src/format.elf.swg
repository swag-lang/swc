#global internal

using Core

// Bytes every ELF file begins with.
private const ElfMagic = "\x7FELF"

// One section header, kept so the dynamic section can be reached and its strings resolved.
private struct ElfSection
{
    name:      String
    kind:      u32
    flags:     u64
    address:   u64
    offset:    u64
    size:      u64
    link:      u32
    entrySize: u64
}

// Returns whether the file begins with the ELF identity bytes.
func isElfImage(image: *BinaryImage)->bool => image.matches(0, ElfMagic)

// Returns what an ELF file is for.
func elfTypeName(value: u16)->string
{
    switch value
    {
    case 0: return "ET_NONE"
    case 1: return "ET_REL"
    case 2: return "ET_EXEC"
    case 3: return "ET_DYN"
    case 4: return "ET_CORE"
    }

    return "ET_OS"
}

// Returns the processor an ELF machine identifier names.
func elfMachineName(value: u16)->string
{
    switch value
    {
    case 2:   return "SPARC"
    case 3:   return "Intel 386"
    case 8:   return "MIPS"
    case 20:  return "PowerPC"
    case 21:  return "PowerPC 64"
    case 22:  return "IBM S/390"
    case 40:  return "ARM"
    case 42:  return "Hitachi SH"
    case 43:  return "SPARC v9"
    case 50:  return "Intel Itanium"
    case 62:  return "x86-64"
    case 183: return "AArch64"
    case 224: return "AMD GPU"
    case 243: return "RISC-V"
    case 258: return "LoongArch"
    }

    return "?"
}

// Returns the operating system whose conventions the file follows.
func elfOsAbiName(value: u8)->string
{
    switch value
    {
    case 0:  return "SYSV"
    case 1:  return "HPUX"
    case 2:  return "NETBSD"
    case 3:  return "LINUX"
    case 6:  return "SOLARIS"
    case 9:  return "FREEBSD"
    case 12: return "OPENBSD"
    case 64: return "ARM_AEABI"
    case 97: return "ARM"
    }

    return "?"
}

// Returns what one program header asks the loader to do.
func elfSegmentName(value: u32)->string
{
    switch value
    {
    case 0:          return "PT_NULL"
    case 1:          return "PT_LOAD"
    case 2:          return "PT_DYNAMIC"
    case 3:          return "PT_INTERP"
    case 4:          return "PT_NOTE"
    case 5:          return "PT_SHLIB"
    case 6:          return "PT_PHDR"
    case 7:          return "PT_TLS"
    case 0x6474E550: return "PT_GNU_EH_FRAME"
    case 0x6474E551: return "PT_GNU_STACK"
    case 0x6474E552: return "PT_GNU_RELRO"
    case 0x6474E553: return "PT_GNU_PROPERTY"
    }

    return "PT_OS"
}

// Returns what one section holds.
func elfSectionKindName(value: u32)->string
{
    switch value
    {
    case 0:          return "SHT_NULL"
    case 1:          return "SHT_PROGBITS"
    case 2:          return "SHT_SYMTAB"
    case 3:          return "SHT_STRTAB"
    case 4:          return "SHT_RELA"
    case 5:          return "SHT_HASH"
    case 6:          return "SHT_DYNAMIC"
    case 7:          return "SHT_NOTE"
    case 8:          return "SHT_NOBITS"
    case 9:          return "SHT_REL"
    case 11:         return "SHT_DYNSYM"
    case 14:         return "SHT_INIT_ARRAY"
    case 15:         return "SHT_FINI_ARRAY"
    case 16:         return "SHT_PREINIT_ARRAY"
    case 17:         return "SHT_GROUP"
    case 18:         return "SHT_SYMTAB_SHNDX"
    case 0x6FFFFFF6: return "SHT_GNU_HASH"
    case 0x6FFFFFFE: return "SHT_GNU_VERNEED"
    case 0x6FFFFFFF: return "SHT_GNU_VERSYM"
    }

    return "SHT_OS"
}

// Returns what one dynamic entry tells the dynamic loader.
func elfDynamicTagName(value: u64)->string
{
    switch value
    {
    case 0:          return "DT_NULL"
    case 1:          return "DT_NEEDED"
    case 2:          return "DT_PLTRELSZ"
    case 3:          return "DT_PLTGOT"
    case 4:          return "DT_HASH"
    case 5:          return "DT_STRTAB"
    case 6:          return "DT_SYMTAB"
    case 7:          return "DT_RELA"
    case 8:          return "DT_RELASZ"
    case 9:          return "DT_RELAENT"
    case 10:         return "DT_STRSZ"
    case 11:         return "DT_SYMENT"
    case 12:         return "DT_INIT"
    case 13:         return "DT_FINI"
    case 14:         return "DT_SONAME"
    case 15:         return "DT_RPATH"
    case 16:         return "DT_SYMBOLIC"
    case 17:         return "DT_REL"
    case 18:         return "DT_RELSZ"
    case 19:         return "DT_RELENT"
    case 20:         return "DT_PLTREL"
    case 21:         return "DT_DEBUG"
    case 22:         return "DT_TEXTREL"
    case 23:         return "DT_JMPREL"
    case 24:         return "DT_BIND_NOW"
    case 25:         return "DT_INIT_ARRAY"
    case 26:         return "DT_FINI_ARRAY"
    case 27:         return "DT_INIT_ARRAYSZ"
    case 28:         return "DT_FINI_ARRAYSZ"
    case 29:         return "DT_RUNPATH"
    case 30:         return "DT_FLAGS"
    case 0x6FFFFFFB: return "DT_FLAGS_1"
    case 0x6FFFFFFE: return "DT_VERNEED"
    case 0x6FFFFFFF: return "DT_VERNEEDNUM"
    case 0x6FFFFFF0: return "DT_VERSYM"
    case 0x6FFFFFFD: return "DT_VERDEFNUM"
    }

    return "DT_OS"
}

// Adds everything an ELF file says about itself: how it is loaded, how it is linked, and what it
// needs at run time.
func reportElfImage(image: *BinaryImage, report: *BinaryReport)
{
    let s     = binStrings()
    let is64  = image.u8At(4) == 2
    let order = image.u8At(5)
    image.bigEndian = order == 2

    let wide     = is64 ? 8'u64 : 4
    let headerAt = 16'u64
    let kind     = image.u16At(headerAt)
    let machine  = image.u16At(headerAt + 2)
    let entry    = image.scalarAt(headerAt + 8, wide)
    let phoff    = image.scalarAt(headerAt + 8 + wide, wide)
    let shoff    = image.scalarAt(headerAt + 8 + wide * 2, wide)
    let tailAt   = headerAt + 8 + wide * 3
    let phentsz  = cast(u64) image.u16At(tailAt + 6)
    let phnum    = cast(u64) image.u16At(tailAt + 8)
    let shentsz  = cast(u64) image.u16At(tailAt + 10)
    let shnum    = cast(u64) image.u16At(tailAt + 12)
    let shstrndx = cast(u64) image.u16At(tailAt + 14)

    report.beginGroup(s.elf_Header, "", "", offset: 0, length: tailAt + 16, open: true)
    report.beginGroup(s.elf_Identity, "ELF", "", offset: 0, length: 16)
    report.numField(4, 1, "EI_CLASS", cast(u64) image.u8At(4), is64 ? s.elf_Class64 : s.elf_Class32)
    report.numField(5, 1, "EI_DATA", cast(u64) order, order == 2 ? s.elf_Big : s.elf_Little)
    report.numField(6, 1, "EI_VERSION", cast(u64) image.u8At(6))
    report.numField(7, 1, "EI_OSABI", cast(u64) image.u8At(7), elfOsAbiName(image.u8At(7)))
    report.numField(8, 1, "EI_ABIVERSION", cast(u64) image.u8At(8))
    report.endGroup()

    report.hexField(headerAt, 2, "e_type", cast(u64) kind, elfTypeName(kind))
    report.hexField(headerAt + 2, 2, "e_machine", cast(u64) machine, elfMachineName(machine))
    report.numField(headerAt + 4, 4, "e_version", cast(u64) image.u32At(headerAt + 4))
    report.hexField(headerAt + 8, wide, "e_entry", entry)
    report.hexField(headerAt + 8 + wide, wide, "e_phoff", phoff)
    report.hexField(headerAt + 8 + wide * 2, wide, "e_shoff", shoff)
    report.hexField(tailAt, 4, "e_flags", cast(u64) image.u32At(tailAt))
    report.numField(tailAt + 4, 2, "e_ehsize", cast(u64) image.u16At(tailAt + 4))
    report.numField(tailAt + 6, 2, "e_phentsize", phentsz)
    report.numField(tailAt + 8, 2, "e_phnum", phnum)
    report.numField(tailAt + 10, 2, "e_shentsize", shentsz)
    report.numField(tailAt + 12, 2, "e_shnum", shnum)
    report.numField(tailAt + 14, 2, "e_shstrndx", shstrndx)
    report.endGroup()

    reportElfSegments(image, report, phoff, phentsz, phnum, is64)

    let sections = readElfSections(image, shoff, shentsz, shnum, shstrndx, is64)
    reportElfSections(image, report, sections.toSlice(), shoff, shentsz, is64)
    reportElfDynamic(image, report, sections.toSlice(), is64)
    reportElfNotes(image, report, sections.toSlice())

    let counted = countText(shnum, s.word_Section, s.word_Sections)
    report.formatName = String.from(is64 ? "ELF64" : "ELF32")
    report.summary    = Format.toString("% · % · % · %", report.formatName, elfTypeName(kind), elfMachineName(machine), counted)
}

private func reportElfSegments(image: *BinaryImage, report: *BinaryReport, at, entrySize, count: u64, is64: bool)
{
    if !at or !count do
        return

    let s     = binStrings()
    let shown = Math.min(count, BinaryListLimit)
    let total = countText(count, s.word_Entry, s.word_Entries)

    report.beginGroup(s.elf_Programs, total.toString(), s.elf_ProgramsDesc, offset: at, length: count * entrySize, open: true)

    for index in shown
    {
        let entryAt  = at + index * entrySize
        let kind     = image.u32At(entryAt)
        let flags    = is64 ? image.u32At(entryAt + 4) : image.u32At(entryAt + 24)
        let valuesAt = is64 ? entryAt + 8 : entryAt + 4
        let wide     = is64 ? 8'u64 : 4
        let fileSize = image.scalarAt(valuesAt + wide * 3, wide)
        let address  = hexText(image.scalarAt(valuesAt + wide, wide), is64 ? 16 : 8)
        let mapped   = elfSegmentFlagsText(flags)

        report.beginGroup(elfSegmentName(kind), address.toString(), mapped.toString(), offset: image.scalarAt(valuesAt, wide), length: fileSize)
        report.hexField(entryAt, 4, "p_type", cast(u64) kind, elfSegmentName(kind))
        report.hexField(is64 ? entryAt + 4 : entryAt + 24, 4, "p_flags", cast(u64) flags, mapped.toString())
        report.hexField(valuesAt, wide, "p_offset", image.scalarAt(valuesAt, wide))
        report.hexField(valuesAt + wide, wide, "p_vaddr", image.scalarAt(valuesAt + wide, wide))
        report.hexField(valuesAt + wide * 2, wide, "p_paddr", image.scalarAt(valuesAt + wide * 2, wide))
        report.sizeField(valuesAt + wide * 3, wide, "p_filesz", fileSize)
        report.sizeField(valuesAt + wide * 4, wide, "p_memsz", image.scalarAt(valuesAt + wide * 4, wide))
        report.hexField(valuesAt + wide * 5, wide, "p_align", image.scalarAt(valuesAt + wide * 5, wide))
        report.endGroup()
    }

    report.listCut(shown, count)
    report.endGroup()
}

private func elfSegmentFlagsText(value: u32)->String
{
    let names = [BinaryFlagName{1, "PF_X"}, BinaryFlagName{2, "PF_W"}, BinaryFlagName{4, "PF_R"}]
    return flagsText(cast(u64) value, names)
}

private func elfSectionFlagsText(value: u64)->String
{
    let names = [BinaryFlagName{0x001, "SHF_WRITE"},
                 BinaryFlagName{0x002, "SHF_ALLOC"},
                 BinaryFlagName{0x004, "SHF_EXECINSTR"},
                 BinaryFlagName{0x010, "SHF_MERGE"},
                 BinaryFlagName{0x020, "SHF_STRINGS"},
                 BinaryFlagName{0x040, "SHF_INFO_LINK"},
                 BinaryFlagName{0x080, "SHF_LINK_ORDER"},
                 BinaryFlagName{0x200, "SHF_GROUP"},
                 BinaryFlagName{0x400, "SHF_TLS"},
                 BinaryFlagName{0x800, "SHF_COMPRESSED"}]
    return flagsText(value, names)
}

// Reads the section table, resolving each name through the section that holds them.
private func readElfSections(image: *BinaryImage, at, entrySize, count, stringIndex: u64, is64: bool)->Array'ElfSection
{
    var result: retval
    if !at or !count do
        return result

    let wide      = is64 ? 8'u64 : 4
    let namesAt   = at + stringIndex * entrySize
    let stringsAt = stringIndex < count ? image.scalarAt(namesAt + 8 + wide * 2, wide) : 0

    for index in Math.min(count, BinaryListLimit)
    {
        let entryAt = at + index * entrySize

        var section: ElfSection
        section.kind      = image.u32At(entryAt + 4)
        section.flags     = image.scalarAt(entryAt + 8, wide)
        section.address   = image.scalarAt(entryAt + 8 + wide, wide)
        section.offset    = image.scalarAt(entryAt + 8 + wide * 2, wide)
        section.size      = image.scalarAt(entryAt + 8 + wide * 3, wide)
        section.link      = image.u32At(entryAt + 8 + wide * 4)
        section.entrySize = image.scalarAt(entryAt + 16 + wide * 5, wide)
        if stringsAt do
            section.name = image.cstringAt(stringsAt + cast(u64) image.u32At(entryAt), 128)
        result.add(#move section)
    }

    return result
}

private func reportElfSections(image: *BinaryImage, report: *BinaryReport, sections: const [..] ElfSection, at, entrySize: u64, is64: bool)
{
    let s = binStrings()
    if !at
    {
        report.note(s.elf_NoSections)
        return
    }

    let wide  = is64 ? 8'u64 : 4
    let total = countText(@countof(sections), s.word_Section, s.word_Sections)
    report.beginGroup(s.shr_Sections, total.toString(), s.elf_SectionsDesc, offset: at, length: @countof(sections) * entrySize, open: true)

    for section, index in sections
    {
        let entryAt = at + index * entrySize
        let names   = elfSectionFlagsText(section.flags)
        let stored  = StrConv.toDisplaySize(section.size)
        var label   = section.name
        if label.isEmpty() do
            label = Format.toString("[%]", index)

        // A `SHT_NOBITS` section is reserved in memory and stored nowhere, so it is given no range:
        // a search hit can never be inside bytes the file does not carry.
        let holds = section.kind != 8
        report.beginGroup(label.toString(), elfSectionKindName(section.kind), stored.toString(), offset: holds ? section.offset : Swag.U64.Max, length: holds ? section.size : 0)
        report.hexField(entryAt + 4, 4, "sh_type", cast(u64) section.kind, elfSectionKindName(section.kind))
        report.hexField(entryAt + 8, wide, "sh_flags", section.flags, names.toString())
        report.hexField(entryAt + 8 + wide, wide, "sh_addr", section.address)
        report.hexField(entryAt + 8 + wide * 2, wide, "sh_offset", section.offset)
        report.sizeField(entryAt + 8 + wide * 3, wide, "sh_size", section.size)
        report.numField(entryAt + 8 + wide * 4, 4, "sh_link", cast(u64) section.link)
        report.numField(entryAt + 12 + wide * 4, 4, "sh_info", cast(u64) image.u32At(entryAt + 12 + wide * 4))
        report.numField(entryAt + 16 + wide * 5, wide, "sh_entsize", section.entrySize)
        report.endGroup()
    }

    report.endGroup()
}

// Adds the dynamic section, which is the whole of what a shared library asks of its loader.
private func reportElfDynamic(image: *BinaryImage, report: *BinaryReport, sections: const [..] ElfSection, is64: bool)
{
    var dynamic: #null const *ElfSection
    for section in sections where section.kind == 6
    {
        dynamic = section
        break
    }

    if !dynamic do
        return

    // The strings a dynamic entry names live in the section it links to, which is `.dynstr`.
    let s         = binStrings()
    let wide      = is64 ? 8'u64 : 4
    let at        = dynamic!.offset
    var stringsAt = 0'u64
    if cast(u64) dynamic!.link < @countof(sections) do
        stringsAt = sections[dynamic!.link].offset

    var entries: Array'u64
    var needed:  Array'String
    while entries.count < BinaryListLimit
    {
        let entryAt = at + entries.count * wide * 2
        if !image.has(entryAt, wide * 2) do
            break
        entries.add(entryAt)
        if !image.scalarAt(entryAt, wide) do
            break
    }

    let total = countText(entries.count, s.word_Entry, s.word_Entries)
    report.beginGroup(s.elf_Dynamic, total.toString(), s.elf_DynamicDesc, offset: at, length: dynamic!.size, open: true)

    for entryAt in entries
    {
        let tag   = image.scalarAt(entryAt, wide)
        let value = image.scalarAt(entryAt + wide, wide)

        // A handful of tags name a string rather than an address, and those are the ones a reader
        // actually came for: what this file needs, and what it calls itself.
        if stringsAt and (tag == 1 or tag == 14 or tag == 15 or tag == 29)
        {
            let text = image.cstringAt(stringsAt + value, 512)
            report.field(entryAt, wide * 2, elfDynamicTagName(tag), text.toString())
            if tag == 1 do
                needed.add(text)
            continue
        }

        report.hexField(entryAt, wide * 2, elfDynamicTagName(tag), value)
    }

    report.endGroup()

    if !needed.isEmpty()
    {
        let count = countText(needed.count, s.word_Library, s.word_Libraries)
        report.beginGroup(s.shr_Libraries, count.toString(), "", open: true)
        for one in needed do
            report.derived(one.toString(), "")
        report.endGroup()
    }
}

// Adds the two notes worth naming: the interpreter a program is started by, and the build identity.
private func reportElfNotes(image: *BinaryImage, report: *BinaryReport, sections: const [..] ElfSection)
{
    let s = binStrings()
    for section in sections
    {
        if section.name == ".interp"
        {
            let path = image.cstringAt(section.offset, 512)
            report.field(section.offset, section.size, s.shr_Interpreter, path.toString())
            continue
        }

        if section.name != ".note.gnu.build-id" do
            continue

        // A note is a name length, a payload length, a kind, the padded name, then the payload.
        let nameSize    = cast(u64) image.u32At(section.offset)
        let payloadSize = cast(u64) image.u32At(section.offset + 4)
        let payloadAt   = section.offset + 12 + ((nameSize + 3) & ~3'u64)

        var text: Array'u8
        for index in Math.min(payloadSize, 64'u64)
        {
            let value  = image.u8At(payloadAt + index)
            let digits = [cast(u8) (value >> 4), value & 0xF]
            for nibble in digits do
                text.add(nibble < 10 ? '0'u8 + nibble : 'a'u8 + nibble - 10)
        }

        if text.isEmpty() do
            continue
        report.field(payloadAt, payloadSize, s.shr_BuildId, @mkstring(text.buffer!, text.count))
    }
}
