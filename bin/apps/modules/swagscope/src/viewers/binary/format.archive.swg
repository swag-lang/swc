#global internal

using Core

// Bytes every archive begins with.
private const ArMagic = "!<arch>\n"

// Size of the fixed header in front of every member.
private const ArHeaderSize = 60'u64

// Returns whether the file is a `ar` archive, which is what a static or import library is.
func isArchive(image: *BinaryImage)->bool => image.matches(0, ArMagic)

// Adds every member of an archive, and what the members that are not objects are for.
//
// A library is a directory before it is a container: what a linker actually reads first is the
// symbol index, because that is what says which member has to be pulled in at all.
func reportArchive(image: *BinaryImage, report: *BinaryReport)
{
    image.bigEndian = false

    let s = binStrings()
    report.beginGroup(s.ar_Archive, ArMagic[0 until 7], "", offset: 0, length: 8, open: true)
    report.endGroup()

    // The members are counted first: the group above the list has to name how many there are, and
    // the chain has to be walked to know that.
    var offsets: Array'u64
    var scan     = 8'u64
    var complete = true
    while scan + ArHeaderSize <= image.bytes.count and offsets.count < BinaryListLimit
    {
        let size = arDecimalAt(image, scan + 48, 10)
        if !image.matches(scan + 58, "`\n")
        {
            complete = false
            break
        }

        offsets.add(scan)
        scan += ArHeaderSize + size + (size & 1)
    }

    if scan < image.fileSize and offsets.count < BinaryListLimit and complete and !image.isBounded() do
        complete = false

    let longNamesAt = arLongNamesAt(image, offsets.toSlice())
    let members     = countText(offsets.count, s.word_Member, s.word_Members)
    var objects     = 0'u64
    var imports     = 0'u64

    report.beginGroup(s.ar_Members, members.toString(), "", offset: 8, length: image.bytes.count - 8, open: true)

    for at in offsets
    {
        let rawName = image.fixedTextAt(at, 16)
        let size    = arDecimalAt(image, at + 48, 10)
        let dataAt  = at + ArHeaderSize
        let name    = arMemberName(image, rawName.toString(), longNamesAt)
        let stored  = StrConv.toDisplaySize(size)

        report.beginGroup(name.toString(), stored.toString(), "", offset: dataAt, length: size)
        arReportHeader(image, report, at, size)

        if rawName == "/" or rawName == "/SYM64/" do
            arReportLinkerMember(image, report, dataAt, size, rawName == "/" and at == offsets[0])
        elif rawName == "//" do
            report.derived(s.ar_LongNames, stored.toString())
        elif image.u16At(dataAt) == 0 and image.u16At(dataAt + 2) == 0xFFFF
        {
            arReportImportMember(image, report, dataAt)
            imports += 1
        }
        elif isCoffObject(image) or image.has(dataAt, PeFileHeaderSize)
        {
            let machine = image.u16At(dataAt)
            report.hexField(dataAt, 2, "Machine", cast(u64) machine, peMachineName(machine))
            report.numField(dataAt + 2, 2, "NumberOfSections", cast(u64) image.u16At(dataAt + 2))
            report.numField(dataAt + 12, 4, "NumberOfSymbols", cast(u64) image.u32At(dataAt + 12))
            objects += 1
        }

        report.endGroup()
    }

    if !complete do
        report.note(s.ar_Malformed)
    report.listCut(offsets.count, offsets.count)
    report.endGroup()

    let counted = countText(offsets.count, s.word_Member, s.word_Members)
    report.formatName = String.from(imports > objects ? "Import library" : "Static library")
    report.summary    = Format.toString("% · %", report.formatName, counted)
}

private func arReportHeader(image: *BinaryImage, report: *BinaryReport, at, size: u64)
{
    let s        = binStrings()
    let modified = epochText(arDecimalAt(image, at + 16, 12))
    let owner    = image.fixedTextAt(at + 28, 12)
    let mode     = image.fixedTextAt(at + 40, 8)

    report.field(at + 16, 12, s.ar_Modified, modified.toString())
    if !owner.isEmpty() do
        report.field(at + 28, 12, s.ar_Owner, owner.toString())
    if !mode.isEmpty() do
        report.field(at + 40, 8, s.ar_Mode, mode.toString())
    report.numField(at + 48, 10, "Size", size)
}

// Adds the symbol index a linker reads before anything else in the archive.
private func arReportLinkerMember(image: *BinaryImage, report: *BinaryReport, at, size: u64, first: bool)
{
    let s = binStrings()
    report.beginGroup(s.ar_Linker, "", s.ar_LinkerDesc, offset: at, length: size)

    // The first directory is written big endian whatever the target, and the second little endian.
    // They are two views of the same index, so only one of them is ever read.
    image.bigEndian = first
    defer image.bigEndian = false

    var count    = cast(u64) image.u32At(at)
    var namesAt  = at + 4 + count * 4
    var offsetAt = at + 4

    if !first
    {
        let memberCount = cast(u64) image.u32At(at)
        count    = cast(u64) image.u32At(at + 4 + memberCount * 4)
        offsetAt = at + 4 + memberCount * 4 + 4
        namesAt  = offsetAt + count * 2
        report.numField(at, 4, "NumberOfMembers", memberCount)
    }

    let symbols = countText(count, s.word_Symbol, s.word_Symbols)
    report.field(at, 4, "NumberOfSymbols", symbols.toString())

    let shown  = Math.min(count, BinaryListLimit)
    var nameAt = namesAt
    for index in shown
    {
        let name = image.cstringAt(nameAt)
        if name.isEmpty() do
            break
        let target = first ? cast(u64) image.u32At(offsetAt + index * 4) : cast(u64) image.u16At(offsetAt + index * 2)
        let value  = first ? hexText(target, 8) : Format.toString("%", target)
        report.field(nameAt, name.length + 1, name.toString(), value.toString())
        nameAt += name.length + 1
    }

    report.listCut(shown, count)
    report.endGroup()
}

// Adds one short import record, the member form a linker turns into a thunk rather than into code.
private func arReportImportMember(image: *BinaryImage, report: *BinaryReport, at: u64)
{
    let s       = binStrings()
    let machine = image.u16At(at + 6)
    let ordinal = image.u16At(at + 16)
    let flags   = image.u16At(at + 18)
    let symbol  = image.cstringAt(at + 20)
    let library = image.cstringAt(at + 20 + symbol.length + 1)
    let stamp   = epochText(cast(u64) image.u32At(at + 8))
    let origin  = Format.toString(s.ar_ImportDll, library)

    report.beginGroup(s.ar_Import, symbol.toString(), origin.toString(), offset: at, length: 20)
    report.hexField(at + 6, 2, "Machine", cast(u64) machine, peMachineName(machine))
    report.field(at + 8, 4, "TimeDateStamp", stamp.toString())
    report.sizeField(at + 12, 4, "SizeOfData", cast(u64) image.u32At(at + 12))
    report.numField(at + 16, 2, "OrdinalOrHint", cast(u64) ordinal)
    report.hexField(at + 18, 2, "Type", cast(u64) flags, arImportTypeName(flags))
    report.field(at + 20, symbol.length + 1, "Symbol", symbol.toString())
    report.field(at + 20 + symbol.length + 1, library.length + 1, "Library", library.toString())
    report.endGroup()
}

// Returns what a linker is being asked to generate for one imported symbol.
private func arImportTypeName(value: u16)->string
{
    // The low two bits say what the symbol is, and the next three how its name was decorated.
    switch value & 3
    {
    case 0: return "CODE"
    case 1: return "DATA"
    case 2: return "CONST"
    }

    return "?"
}

// Returns where the member holding the long file names starts, or `Swag.U64.Max`.
private func arLongNamesAt(image: *BinaryImage, offsets: const [..] u64)->u64
{
    for at in offsets
    {
        let name = image.fixedTextAt(at, 16)
        if name == "//" do
            return at + ArHeaderSize
    }

    return Swag.U64.Max
}

// Returns the real name of a member.
//
// Three conventions live in the same sixteen bytes: a plain name, a GNU name closed by a slash, and
// a slash followed by an offset into the member that holds the names too long to fit here.
private func arMemberName(image: *BinaryImage, raw: string, longNamesAt: u64)->String
{
    if @countof(raw) == 0 do
        return String.from(BinaryNoValue)

    if raw[0] == '/'u8 and @countof(raw) > 1 and raw[1] >= '0'u8 and raw[1] <= '9'u8
    {
        if longNamesAt == Swag.U64.Max do
            return String.from(raw)

        var offset = 0'u64
        for index in 1 until @countof(raw)
        {
            if raw[index] < '0'u8 or raw[index] > '9'u8 do
                break
            offset = offset * 10 + cast(u64) (raw[index] - '0'u8)
        }

        let name = image.cstringAt(longNamesAt + offset)
        return name.isEmpty() ? String.from(raw) : name
    }

    // GNU archives close a short name with a slash so a trailing blank cannot be part of it.
    if raw[@countof(raw) - 1] == '/'u8 and @countof(raw) > 1 do
        return String.from(raw[0 until @countof(raw) - 1])
    return String.from(raw)
}

// Returns the decimal number written in ASCII across `length` bytes, blanks ignored.
private func arDecimalAt(image: *BinaryImage, at, length: u64)->u64
{
    var result = 0'u64
    for index in length
    {
        let value = image.u8At(at + index)
        if value == ' 'u8 do
            continue
        if value < '0'u8 or value > '9'u8 do
            break
        result = result * 10 + cast(u64) (value - '0'u8)
    }

    return result
}
