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
// jump maps a file offset by scanning them — so the depth is carried on the rows themselves.
struct BinaryReport
{
    formatName: String     // Short name of the format that was recognized.
    summary:    String     // One line for the host's information bar.
    rows:       Array'BinaryRow
    level:      u32     // Depth the next row is written at.
}

impl BinaryReport
{
    // Opens a structure that every row added until the matching [[BinaryReport.endGroup]] sits under.
    mtd beginGroup(label: string, value: string = "", detail: string = "", offset = Swag.U64.Max, length = 0'u64, open = false)
    {
        with var row: BinaryRow
        {
            .kind   = .Group
            .level  = me.level
            .label  = label
            .value  = value
            .detail = detail
            .offset = offset
            .length = length
            .open   = open
        }

        .rows.add(#move row)
        .level += 1
    }

    // Closes the structure the last unmatched [[BinaryReport.beginGroup]] opened.
    mtd endGroup()
    {
        Swag.assert(.level > 0, "a report closed a group it never opened")
        .level -= 1
    }

    // Adds one value and the byte range it was read from.
    //
    // The typed forms below format each value directly into its owning row, keeping numeric
    // formatting consistent across readers.
    mtd field(offset, length: u64, label, value: string, detail: string = "")
    {
        with var row: BinaryRow
        {
            .kind   = .Field
            .level  = me.level
            .label  = label
            .value  = value
            .detail = detail
            .offset = offset
            .length = length
        }

        .rows.add(#move row)
    }

    // Adds a value read as a hexadecimal number as wide as the field that holds it.
    mtd hexField(offset, length: u64, label: string, value: u64, detail: string = "")
    {
        with var row: BinaryRow
        {
            .kind   = .Field
            .level  = me.level
            .label  = label
            .value  = hexText(value, Math.clamp(length, 1'u64, 8) * 2)
            .detail = detail
            .offset = offset
            .length = length
        }

        .rows.add(#move row)
    }

    // Adds a value read as a plain count.
    mtd numField(offset, length: u64, label: string, value: u64, detail: string = "")
    {
        with var row: BinaryRow
        {
            .kind   = .Field
            .level  = me.level
            .label  = label
            .value  = Format.toString("%", value)
            .detail = detail
            .offset = offset
            .length = length
        }

        .rows.add(#move row)
    }

    // Adds a size or an address, in the two readings either is always wanted in at once.
    mtd sizeField(offset, length: u64, label: string, value: u64, detail: string = "")
    {
        with var row: BinaryRow
        {
            .kind   = .Field
            .level  = me.level
            .label  = label
            .value  = hexAndDecimalText(value, Math.clamp(length, 1'u64, 8) * 2)
            .detail = detail
            .offset = offset
            .length = length
        }

        .rows.add(#move row)
    }

    // Adds one value that no single byte range produced, such as a total or a computed address.
    mtd derived(label, value: string, detail: string = "")
    {
        with var row: BinaryRow
        {
            .kind   = .Field
            .level  = me.level
            .label  = label
            .value  = value
            .detail = detail
        }

        .rows.add(#move row)
    }

    // Records what the file did not let the reader see, where the reader would have looked.
    mtd note(text: string)
    {
        with var row: BinaryRow
        {
            .kind  = .Note
            .level = me.level
            .label = text
        }

        .rows.add(#move row)
    }

    // Records that a list was cut, so a short report is never mistaken for a short file.
    mtd listCut(shown, total: u64)
    {
        if total <= shown do
            return
        let text = Format.toString(binaryStrings().rep_NotListed, total - shown)
        .note(text.toString())
    }

    // Returns the innermost row whose byte range contains `offset`, or `Swag.U64.Max`.
    //
    // This is how a file offset becomes a place in the structure: groups carry the range they cover,
    // so an offset inside a section's payload lands on that section even though no field was ever
    // decoded there.
    mtd const rowAt(offset: u64)->u64
    {
        var best      = Swag.U64.Max
        var bestLevel = 0'u32
        var bestSpan  = Swag.U64.Max

        for row, index in .rows
        {
            if row.offset == Swag.U64.Max or not row.length do
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
            if not row.value.isEmpty()
            {
                result += ": "
                result += row.value.toString()
            }

            if not row.detail.isEmpty()
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

    return String.from(cast(string) text.toSlice())
}

// Returns a value in the two readings a size or an address is always wanted in at once.
func hexAndDecimalText(value: u64, digits: u64)->String => Format.toString("% (%)", hexText(value, digits), value)

// Returns the names of every set bit of `value`, and the bits no name accounted for.
func flagsText(value: u64, names: const [..] BinaryFlagName)->String
{
    var result: retval
    var rest = value

    for name in names where value & name.bit
    {
        if not result.isEmpty() do
            result += " | "
        result += name.name
        rest   &= ~name.bit
    }

    if rest
    {
        if not result.isEmpty() do
            result += " | "
        result += hexText(rest, 8)
    }

    return result
}

// Returns the calendar time a 32-bit seconds-since-1970 stamp names.
func epochText(seconds: u64)->String
{
    if not seconds do
        return String.from(binaryStrings().ui_NotSet)

    // A stamp beyond the calendar the runtime spells is a reproducible-build cookie or a corrupt
    // field. Either way it is a number, and saying so beats printing a year in the far future.
    if seconds > 253_370_764_800 do
        return String.from(binaryStrings().ui_NotDate)

    let epoch = Time.Timestamp.fromDateTime({1970, 1, 1})
    let stamp = Time.Timestamp.fromTicks(epoch.ticks + seconds * Time.TicksPerSecond)
    return Format.toString("% UTC", stamp.toDateTime().toString(.DateTimeIso))
}
