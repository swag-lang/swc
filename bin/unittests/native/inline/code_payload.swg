#global private

// A 'count' field on the host catches a receiver member resolved against the wrong object.
struct Host
{
    count: u32
    cells: InlineCodePayload.Store'u8
}

// The parameter order is chosen so that a callee 'index' leaking onto this frame lands on a
// value far beyond the bound, and a leaking 'value' on a different byte.
#[Swag.NoInline]
func fill(host: *Host, shift: u64, marker: u8, n: u64)
{
    var i = 0'u64
    for n
    {
        host.cells[i] = cast(u8) (i + shift)
        i += 1
    }
    Swag.assert(marker == 0xEE)
}

struct Table
{
    n:       u32
    entries: InlineCodePayload.Store'InlineCodePayload.Entry
}

impl Table
{
    // A struct literal stored through the receiver's member, from inside a method: the shape of
    // the LZW decoder's table growth.
    mtd add(length: u16, prefix: u16, suffix: u8)
    {
        .entries[.n] = {length, prefix, suffix}
        .n += 1
    }
}

#[Swag.NoInline]
func fillTable(table: *Table)
{
    // Unsized constants and a runtime field must all use the concrete element layout
    // when the implicit aggregate conversion is cloned into the indexed write.
    for i in 4 do
        table.entries[i] = {1, 0xFFF, cast(u8) i}
}

#test
{
    var raw: [8] u8
    // A zero 'count' on the host: a receiver member resolved against the host instead of the
    // container makes every bound check fail.
    var host = Host{0, {&raw[0], 8}}
    fill(&host, 100, 0xEE, 8)

    // Read back through the raw buffer, so a wrong store is not masked by an equally wrong read.
    for i in 8 do
        Swag.assert(raw[i] == cast(u8) (i + 100))

    var ents: [4] InlineCodePayload.Entry
    var table = Table{0, {&ents[0], 4}}
    table.add(1, 0xFFF, 7)
    table.add(2, 0, 9)
    Swag.assert(ents[0].length == 1 and ents[0].prefix == 0xFFF and ents[0].suffix == 7)
    Swag.assert(ents[1].length == 2 and ents[1].prefix == 0 and ents[1].suffix == 9)
    Swag.assert(table.n == 2)

    fillTable(&table)
    for i in 4
    {
        Swag.assert(ents[i].length == 1)
        Swag.assert(ents[i].prefix == 0xFFF)
        Swag.assert(ents[i].suffix == i)
    }

    Swag.assert(host.cells[3] == 103)
}
