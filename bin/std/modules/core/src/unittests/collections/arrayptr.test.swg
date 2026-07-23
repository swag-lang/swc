#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertIntArrayPtr(values: &ArrayPtr's32, expected: const [..] s32)->bool
{
    if values.count != @countof(expected) do
        return false

    for value, index in values
    {
        if value == null do
            return false
        if dref value != expected[index] do
            return false
    }

    return true
}

#test
{
    var values: ArrayPtr's32
    dref values.addNewPtr() = 1
    dref values.addNewPtr() = 2
    dref values.addNewPtr() = 3

    var copy = values
    @assert(assertIntArrayPtr(&copy, [1, 2, 3]))

    for value, index in values
    {
        @assert(copy[index] != value)
        @assert(dref copy[index] == dref value)
    }

    dref copy[1] = 42
    @assert(dref values[1] == 2)
    @assert(dref copy[1] == 42)
}

#test
{
    var values: ArrayPtr's32
    dref values.addNewPtr() = 7
    values.add(cast(#null *s32) null)
    dref values.addNewPtr() = 9

    var copy = values

    @assert(copy.count == 3)
    @assert(copy[1] == null)
    @assert(copy[0] != null)
    @assert(copy[2] != null)
    @assert(copy[0] != values[0])
    @assert(copy[2] != values[2])
    @assert(dref copy[0] == 7)
    @assert(dref copy[2] == 9)
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
        let p = arr.addNewPtr()
        p.id = cast(s32) i
    }
    @assert(arr.count == 5)
    @assert(arr.getFirst().id == 0)
    @assert(arr.getLast().id == 4)

    let third = arr[2]
    @assert(arr.indexOf(third) == 2)
    @assert(arr.contains(third))
    @assert(arr.indexOf(cast(#null *ApTracked) null) == Swag.U64.Max)
    @assert(!arr.contains(cast(#null *ApTracked) null))

    // deleteAt keeps order and drops the object: [0,1,2,3,4] -> remove id 1 -> [0,2,3,4].
    arr.deleteAt(1)
    @assert(arr.count == 4 and g_ApDropCount == 1)
    let a0 = arr[0]; let a1 = arr[1]; let a2 = arr[2]; let a3 = arr[3]
    @assert(a0.id == 0 and a1.id == 2 and a2.id == 3 and a3.id == 4)

    // deleteBack drops the last: -> [0,2,3].
    arr.deleteBack()
    @assert(arr.count == 3 and g_ApDropCount == 2)
    @assert(arr.getLast().id == 3)

    // deleteAtUnordered swaps the last into the hole: remove index 0 (id 0) -> [3,2].
    arr.deleteAtUnordered(0)
    @assert(arr.count == 2 and g_ApDropCount == 3)
    let b0 = arr[0]; let b1 = arr[1]
    @assert(b0.id == 3 and b1.id == 2)

    // insertNewPtr allocates and inserts at the index.
    let ins = arr.insertNewPtr(1)
    ins.id = 99
    @assert(arr.count == 3)
    let c1 = arr[1]
    @assert(c1.id == 99)

// The 3 remaining elements are deallocated when 'arr' drops at scope end.
}
