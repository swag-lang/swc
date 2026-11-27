#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

const MutationStressChunk   = "2333133121414131402"
const MutationFreeSpanId    = -1_s64
const MutationStressRepeats = 512_u32

struct MutationSpan
{
    what: s64
    num:  s64
}

func compactMutationFor(text: string)->u64
{
    var map:    Array!{{ what, num: s64 }}
    var nextId: s64
    for ch, index in text
    {
        let runLength = ch - '0'
        if index & 1
        {
            map.add({what: MutationFreeSpanId, num: runLength})
        }
        else
        {
            map.add({what: nextId, num: runLength})
            nextId += 1
        }
    }

    var last = map.count - #wrap 1
    for i in map.count
    {
        if map[i].what != MutationFreeSpanId
        {
            continue
        }

        while map[last].what == MutationFreeSpanId
        {
            last -= 1
        }

        if i >= last
        {
            break
        }

        map[i].what = map[last].what
        if map[i].num == map[last].num
        {
            map[last].what = MutationFreeSpanId
            last -= 1
        }
        else if map[i].num > map[last].num
        {
            let rest = map[i].num - map[last].num
            map[i].num     = map[last].num
            map[last].what = MutationFreeSpanId
            map.insertAt(i + 1, {what: MutationFreeSpanId, num: rest})
        }
        else
        {
            map[last].num -= map[i].num
        }
    }

    var blockIndex, total: u64
    for span in map
    {
        if span.what == MutationFreeSpanId
        {
            break
        }

        for span.num
        {
            total      += blockIndex * span.what
            blockIndex += 1
        }
    }

    return total
}

func compactMutationWhile(text: string)->u64
{
    var map:    Array!{{ what, num: s64 }}
    var nextId: s64
    for ch, index in text
    {
        let runLength = ch - '0'
        if index & 1
        {
            map.add({what: MutationFreeSpanId, num: runLength})
        }
        else
        {
            map.add({what: nextId, num: runLength})
            nextId += 1
        }
    }

    var last  = map.count - #wrap 1
    let bound = map.count
    var i     = 0_u64
    while i < bound
    {
        if map[i].what != MutationFreeSpanId
        {
            i += 1
            continue
        }

        while map[last].what == MutationFreeSpanId
        {
            last -= 1
        }

        if i >= last
        {
            break
        }

        map[i].what = map[last].what
        if map[i].num == map[last].num
        {
            map[last].what = MutationFreeSpanId
            last -= 1
        }
        else if map[i].num > map[last].num
        {
            let rest = map[i].num - map[last].num
            map[i].num     = map[last].num
            map[last].what = MutationFreeSpanId
            map.insertAt(i + 1, {what: MutationFreeSpanId, num: rest})
        }
        else
        {
            map[last].num -= map[i].num
        }

        i += 1
    }

    var blockIndex, total: u64
    for span in map
    {
        if span.what == MutationFreeSpanId
        {
            break
        }

        for span.num
        {
            total      += blockIndex * span.what
            blockIndex += 1
        }
    }

    return total
}

func buildMutationStressInput(repeats: u32)->String
{
    var result: String
    for repeats
    {
        result += MutationStressChunk
    }

    return result
}

#test
{
    Swag.require(compactMutationWhile(MutationStressChunk) == 1928_u64)
    Swag.require(compactMutationFor(MutationStressChunk) == 1928_u64)
}

#test
{
    let stress = buildMutationStressInput(MutationStressRepeats)
    Swag.require(compactMutationFor(stress) == compactMutationWhile(stress))
}

// An element of the array can be added or inserted back into it: growing moves the storage the
// argument lives in, and shifting rewrites it, so the value is taken before either happens.
#test
{
    var a: Array!{String}
    a.add("one")
    a.add("two")
    Swag.require(a.capacity == a.count)
    a.addBorrowed(&a[0])
    Swag.require(a.count == 3 and a[0] == "one" and a[1] == "two" and a[2] == "one")
    a.insertBorrowedAt(0, &a[1])
    Swag.require(a.count == 4 and a[0] == "two" and a[1] == "one" and a[2] == "two" and a[3] == "one")
    a.insertBorrowedAt(2, &a[3])
    Swag.require(a.count == 5 and a[2] == "one" and a[3] == "two" and a[4] == "one")
}
