#global private

// An indexed write reaches one element through the variable. It never proves that the
// whole aggregate is initialized, but it is not itself a use of uninitialized storage
// once every path has already initialized the variable it indexes.

struct IndexedInitItem
{
    value: s32
}

func indexedWriteThroughAssignedPointer(source: [*] s32, count: u64)
{
    var destination: [*] s32
    destination = source
    for i in count do
        destination[i] = 1
}

func indexedWriteAfterBranchMerge(condition: bool, first, second: [*] s32)
{
    var destination: [*] s32
    if condition do
        destination = first
    else do
        destination = second
    destination[0] = 1
}

func indexedWriteIntoAssignedArray(item: *IndexedInitItem)
{
    var slots: [3] *IndexedInitItem = [item, item, item]
    slots[1] = item
    discard slots[2]
}

// A nested write reaches one member of a field. Once the whole value is constructed there is
// nothing left to prove, so writing through it is an ordinary store.

struct IndexedInitPart
{
    marker: s32 = 7
    other:  s32
}

struct IndexedInitMixed
{
    required: *IndexedInitItem
    part:     IndexedInitPart
}

func nestedWriteAfterConstruction(item: *IndexedInitItem)
{
    var value = IndexedInitMixed{required: item}
    value.part.other = 1
    discard value.part.marker
}
