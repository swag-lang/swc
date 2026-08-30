#global internal

using Core

// Written where a structure names a value the file does not hold.
const BinaryNoValue = "--"

// Longest run of repeated entries a report writes before it says how many were left out.
//
// An import table with twelve thousand symbols is a scroll bar, not information. Every list stops
// here and records the remainder, so a report stays readable whatever the file's size.
const BinaryListLimit = 512'u64

// Kinds of row a report is read in.
enum BinaryRowKind
{
    Group     // A named structure whose fields are the rows under it.
    Field     // One decoded value.
    Note      // A remark about what the file did not let the reader see.
}

// One row of an extracted report.
struct BinaryRow
{
    kind:   BinaryRowKind
    level:  u32                    // Depth in the structure tree.
    label:  String                 // Field or structure name.
    value:  String                 // The value, in the spelling its type is read in.
    detail: String                 // What the value means: a machine name, a flag list, a target.
    offset: u64 = Swag.U64.Max     // Absolute file offset the value was read at, when it has one.
    length: u64                    // Number of bytes the row covers.
    open:   bool                   // Whether a group starts expanded.
}

// Everything one file was made to say, as a flat sequence of levelled rows.
//
// A tree of owning nodes would carry the same information, but every consumer walks the rows in
// order — the view builds its lines in one pass, the clipboard writes them in one pass, and a
// search maps a byte offset by scanning them — so the depth is carried on the rows themselves.
struct BinaryReport
{
    formatName: String     // Short name of the format that was recognized.
    summary:    String     // One line for the host's information bar.
    rows:       Array'BinaryRow
    level:      u32     // Depth the next row is written at.
}

impl BinaryReport
{
    // Opens a structure. Every row added until the matching [[BinaryReport.endGroup]] sits under it.
    mtd beginGroup(label: string, value: string = "", detail: string = "", offset = Swag.U64.Max, length = 0'u64, open = false)
    {
        var row: BinaryRow
        row.kind   = .Group
        row.level  = .level
        row.label  = label
        row.value  = value
        row.detail = detail
        row.offset = offset
        row.length = length
        row.open   = open
        .rows.add(#move row)
        .level += 1
    }

    mtd endGroup()
    {
        Debug.assert(.level > 0, "a report closed a group it never opened")
        .level -= 1
    }

    // Adds one value and the byte range it was read from.
    //
    // The typed forms below exist because a call result handed straight to a parameter is a
    // temporary this compiler does not yet drop, so a report of a few thousand rows would leak one
    // buffer per row. Building the text inside the row is what keeps the call sites free of them.
    mtd field(offset, length: u64, label, value: string, detail: string = "")
    {
        var row: BinaryRow
        row.kind   = .Field
        row.level  = .level
        row.label  = label
        row.value  = value
        row.detail = detail
        row.offset = offset
        row.length = length
        .rows.add(#move row)
    }

    // Adds a value read as a hexadecimal number as wide as the field that holds it.
    mtd hexField(offset, length: u64, label: string, value: u64, detail: string = "")
    {
        var row: BinaryRow
        row.kind   = .Field
        row.level  = .level
        row.label  = label
        row.value  = hexText(value, Math.clamp(length, 1'u64, 8) * 2)
        row.detail = detail
        row.offset = offset
        row.length = length
        .rows.add(#move row)
    }

    // Adds a value read as a plain count.
    mtd numField(offset, length: u64, label: string, value: u64, detail: string = "")
    {
        var row: BinaryRow
        row.kind   = .Field
        row.level  = .level
        row.label  = label
        row.value  = Format.toString("%", value)
        row.detail = detail
        row.offset = offset
        row.length = length
        .rows.add(#move row)
    }

    // Adds a size or an address, in the two readings either is always wanted in at once.
    mtd sizeField(offset, length: u64, label: string, value: u64, detail: string = "")
    {
        var row: BinaryRow
        row.kind   = .Field
        row.level  = .level
        row.label  = label
        row.value  = hexAndDecimalText(value, Math.clamp(length, 1'u64, 8) * 2)
        row.detail = detail
        row.offset = offset
        row.length = length
        .rows.add(#move row)
    }

    // Adds one value that no single byte range produced, such as a total or a computed address.
    mtd derived(label, value: string, detail: string = "")
    {
        var row: BinaryRow
        row.kind   = .Field
        row.level  = .level
        row.label  = label
        row.value  = value
        row.detail = detail
        .rows.add(#move row)
    }

    // Records what the file did not let the reader see, where the reader would have looked.
    mtd note(text: string)
    {
        var row: BinaryRow
        row.kind  = .Note
        row.level = .level
        row.label = text
        .rows.add(#move row)
    }

    // Records that a list was cut, so a short report is never mistaken for a short file.
    mtd listCut(shown, total: u64)
    {
        if total <= shown do
            return
        let text = Format.toString(binStrings().rep_NotListed, total - shown)
        .note(text.toString())
    }

    // Returns the innermost row whose byte range contains `offset`, or `Swag.U64.Max`.
    //
    // This is how a match the host found in the raw bytes becomes a place in the structure: groups
    // carry the range they cover, so an offset inside a section's payload lands on that section
    // even though no field was ever decoded there.
    mtd const rowAt(offset: u64)->u64
    {
        var best      = Swag.U64.Max
        var bestLevel = 0'u32
        var bestSpan  = Swag.U64.Max

        for row, index in .rows
        {
            if row.offset == Swag.U64.Max or !row.length do
                continue
            if offset < row.offset or offset - row.offset >= row.length do
                continue
            if best != Swag.U64.Max and row.level < bestLevel do
                continue
            if best != Swag.U64.Max and row.level == bestLevel and row.length >= bestSpan do
                continue
            best      = index
            bestLevel = row.level
            bestSpan  = row.length
        }

        return best
    }

    // Returns the whole report as indented text, which is what a copy puts on the clipboard.
    mtd const toText()->String
    {
        var result: retval
        result.reserve(.rows.count * 48)

        for row in .rows
        {
            for row.level do
                result += "    "

            result += row.label.toString()
            if !row.value.isEmpty()
            {
                result += ": "
                result += row.value.toString()
            }

            if !row.detail.isEmpty()
            {
                result += "  "
                result += row.detail.toString()
            }

            if row.offset != Swag.U64.Max
            {
                result += "  @"
                result += hexText(row.offset, 8).toString()
            }

            result += "\n"
        }

        return result
    }
}

// One bit of a flags field and the name it carries.
struct BinaryFlagName
{
    bit:  u64
    name: string
}

// Returns `value` as a fixed-width hexadecimal number, in the `0x` form every offset is read in.
func hexText(value: u64, digits: u64)->String
{
    var text: Array'u8
    text.reserve(digits + 2)
    text.add('0'u8)
    text.add('x'u8)
    for index in digits
    {
        let nibble = cast(u8) ((value >> ((digits - 1 - index) * 4)) & 0xF)
        text.add(nibble < 10 ? '0'u8 + nibble : 'A'u8 + nibble - 10)
    }

    return String.from(Swag.makeString(text.buffer!, text.count))
}

// Returns a value in the two readings a size or an address is always wanted in at once.
func hexAndDecimalText(value: u64, digits: u64)->String
{
    return Format.toString("% (%)", hexText(value, digits), value)
}

// Returns the names of every set bit of `value`, and the bits no name accounted for.
func flagsText(value: u64, names: const [..] BinaryFlagName)->String
{
    var result: retval
    var rest = value

    for name in names where value & name.bit
    {
        if !result.isEmpty() do
            result += " | "
        result += name.name
        rest   &= ~name.bit
    }

    if rest
    {
        if !result.isEmpty() do
            result += " | "
        result += hexText(rest, 8)
    }

    return result
}

// Returns the calendar time a 32-bit seconds-since-1970 stamp names.
func epochText(seconds: u64)->String
{
    if !seconds do
        return String.from(binStrings().ui_NotSet)

    // A stamp beyond the calendar the runtime spells is a reproducible-build cookie or a corrupt
    // field. Either way it is a number, and saying so beats printing a year in the far future.
    if seconds > 253_370_764_800 do
        return String.from(binStrings().ui_NotDate)

    let epoch = Time.Timestamp.fromDateTime({1970, 1, 1})
    let stamp = Time.Timestamp.fromTicks(epoch.ticks + seconds * Time.TicksPerSecond)
    return Format.toString("% UTC", stamp.toDateTime().toString(.DateTimeIso))
}

// Returns the mixed-endian textual form Microsoft tools print a GUID in.
func guidText(image: *BinaryImage, offset: u64)->String
{
    if !image.has(offset, 16) do
        return String.from(BinaryNoValue)

    // The first three fields are stored little endian and the last two big endian, so the order the
    // bytes are printed in is not the order they are stored in.
    const Order = [3'u64, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15]

    var text: Array'u8
    for index in 16
    {
        if index == 4 or index == 6 or index == 8 or index == 10 do
            text.add('-'u8)
        let value  = image.bytes[offset + Order[index]]
        let digits = [cast(u8) (value >> 4), value & 0xF]
        for nibble in digits do
            text.add(nibble < 10 ? '0'u8 + nibble : 'A'u8 + nibble - 10)
    }

    return String.from(Swag.makeString(text.buffer!, text.count))
}
