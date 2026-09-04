#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertIntArrayPtr(values: *ArrayPtr's32, expected: const [..] s32)->bool
{
    if values.count != expected.count do
        return false

    for value, index in values[]
    {
        if value == null do
            return false
        if value[] != expected[index] do
            return false
    }

    return true
}

#test
{
    var values: ArrayPtr's32
    values.addNew()[] = 1
    values.addNew()[] = 2
    values.addNew()[] = 3

    var copy = values
    Swag.assert(assertIntArrayPtr(&copy, [1, 2, 3]))

    for value, index in values
    {
        let src = value!
        let dup = copy[index]!
        Swag.assert(dup != src)
        Swag.assert(dup[] == src[])
    }

    let slot1 = copy[1]!
    slot1[] = 42
    Swag.assert(values[1]![] == 2)
    Swag.assert(copy[1]![] == 42)
}

#test
{
    var values: ArrayPtr's32
    values.addNew()[] = 7
    values.add(cast(*s32?) null)
    values.addNew()[] = 9

    var copy = values

    Swag.assert(copy.count == 3)
    Swag.assert(copy[1] == null)
    Swag.assert(copy[0] != null)
    Swag.assert(copy[2] != null)
    Swag.assert(copy[0] != values[0])
    Swag.assert(copy[2] != values[2])
    Swag.assert(copy[0]![] == 7)
    Swag.assert(copy[2]![] == 9)
}

var g_ApDropCount: s32

struct ApTracked
{
    id: s32 = 0
}

impl ApTracked
{
    mtd opDrop()
    {
        g_ApDropCount += 1
    }
}

// getFirst/getLast, indexOf/contains, insertNewPtr, and the delete* helpers (which must
// deallocate the pointed-to object, verified via opDrop).
#test
{
    g_ApDropCount = 0

    var arr: ArrayPtr'ApTracked
    for i in 5
    {
        let p = arr.addNew()
        p.id = cast(s32) i
    }

    Swag.assert(arr.count == 5)
    Swag.assert(arr.first()!.id == 0)
    Swag.assert(arr.last()!.id == 4)

    let third = arr[2]
    Swag.assert(arr.indexOf(third) == 2)
    Swag.assert(arr.contains(third))
    Swag.assert(arr.indexOf(cast(*ApTracked?) null) == Swag.U64.Max)
    Swag.assert(!arr.contains(cast(*ApTracked?) null))

    // deleteAt keeps order and drops the object: [0,1,2,3,4] -> remove id 1 -> [0,2,3,4].
    arr.deleteAt(1)
    Swag.assert(arr.count == 4 and g_ApDropCount == 1)
    let a0 = arr[0]!
    let a1 = arr[1]!
    let a2 = arr[2]!
    let a3 = arr[3]!
    Swag.assert(a0.id == 0 and a1.id == 2 and a2.id == 3 and a3.id == 4)

    // deleteBack drops the last: -> [0,2,3].
    arr.deleteBack()
    Swag.assert(arr.count == 3 and g_ApDropCount == 2)
    Swag.assert(arr.last()!.id == 3)

    // deleteAtUnordered swaps the last into the hole: remove index 0 (id 0) -> [3,2].
    arr.deleteAtUnordered(0)
    Swag.assert(arr.count == 2 and g_ApDropCount == 3)
    let b0 = arr[0]!
    let b1 = arr[1]!
    Swag.assert(b0.id == 3 and b1.id == 2)

    // insertNewPtr allocates and inserts at the index.
    let ins = arr.insertNew(1)
    ins.id = 99
    Swag.assert(arr.count == 3)
    let c1 = arr[1]!
    Swag.assert(c1.id == 99)

// The 3 remaining elements are deallocated when 'arr' drops at scope end.
}

var g_ApTotal: u64

struct ApFlagged
{
    hidden: u8
    tag:    u64
}

impl ApFlagged
{
    #[Swag.Inline]
    mtd isShown() => .hidden == 0
}

// An indexed element with a bang as the receiver of a SHORT, non-const inline method:
// the direct-substitution clone of the receiver must carry the index's spec-op
// selection, or codegen lowers the resolved clone through the raw-index fallback.
#test
{
    var arr: ArrayPtr'ApFlagged
    let a = arr.addNew()
    a.tag = 7

    var shown = 0
    var i     = 0'u64
    while i < arr.count
    {
        if arr[i]!.isShown() do
            shown += 1
        i += 1
    }

    Swag.assert(shown == 1)
}

func apCountByValue(values: Array'rune)->u64
{
    var total = 0'u64
    for i in values.count do
        total += cast(u64) values[i]
    return total
}

// '.count' on a by-value Array parameter goes through the receiver-only spec-op
// fallback: the pointer-world receiver must pass the operand's ADDRESS, not load its
// first field bytes as the receiver pointer.
#test
{
    var runes: Array'rune
    runes.add('X')
    Swag.assert(apCountByValue(runes) == cast(u64) 'X')

    var holder: ArrayPtr'ApFlagged
    discard holder.addNew()
    let first = holder[0]!
    first.tag = 2
    g_ApTotal = apCountByValue(runes) + first.tag
    Swag.assert(g_ApTotal == cast(u64) 'X' + 2)
}
