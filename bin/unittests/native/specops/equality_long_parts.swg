#global private

// Long parts of an aggregate comparison are walked by a loop instead of being unrolled: a byte
// run past eight sixteen-byte chunks, and an array past four elements that are not plain bytes.
// A difference at any position, the last chunk and the tail included, must still be seen.

struct LongBytes
{
    head:  s32
    words: [40] u64
    tail:  [3] u8
}

struct NamedCell
{
    name:  string = ""
    value: s32
}

struct CellTable
{
    cells: [9] NamedCell
    count: s32
}

struct CountingEqual
{
    value: s32
}

var g_CountingEqualCalls: s32

impl CountingEqual
{
    mtd const opEquals(other: CountingEqual)->bool
    {
        g_CountingEqualCalls += 1
        return .value == other.value
    }
}

struct CountingTable
{
    items: [7] CountingEqual
}

#[Swag.NoInline]
func sameLongBytes(a, b: *LongBytes)->bool => a[] == b[]

#[Swag.NoInline]
func sameCellTable(a, b: *CellTable)->bool => a[] == b[]

#[Swag.NoInline]
func sameCountingTable(a, b: *CountingTable)->bool => a[] == b[]

#test
{
    var a, b: LongBytes
    for i in 40
    {
        a.words[i] = cast(u64, i) * 0x0101_0101
        b.words[i] = a.words[i]
    }

    Swag.assert(sameLongBytes(&a, &b))
    for i in 40
    {
        b.words[i] ^= 1
        Swag.assert(not sameLongBytes(&a, &b))
        b.words[i] ^= 1
    }

    b.tail[2] = 9
    Swag.assert(not sameLongBytes(&a, &b))
    b.tail[2] = 0
    Swag.assert(sameLongBytes(&a, &b))
}

#test
{
    var names: [9] string = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]

    var a, b: CellTable
    for i in 9
    {
        a.cells[i].name  = names[i]
        a.cells[i].value = cast(s32, i)
        b.cells[i].name  = names[i]
        b.cells[i].value = cast(s32, i)
    }

    Swag.assert(sameCellTable(&a, &b))
    b.cells[8].name = "z"
    Swag.assert(not sameCellTable(&a, &b))
    b.cells[8].name  = "i"
    b.cells[0].value = 7
    Swag.assert(not sameCellTable(&a, &b))
}

#test
{
    var a, b: CountingTable
    for i in 7
    {
        a.items[i].value = cast(s32, i)
        b.items[i].value = cast(s32, i)
    }

    g_CountingEqualCalls = 0
    Swag.assert(sameCountingTable(&a, &b))
    Swag.assert(g_CountingEqualCalls == 7)

    b.items[3].value     = 99
    g_CountingEqualCalls = 0
    Swag.assert(not sameCountingTable(&a, &b))
    Swag.assert(g_CountingEqualCalls == 4)
}
