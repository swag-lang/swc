#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

const MutationStressChunk   = "2333133121414131402"
const MutationFreeSpanId    = -1's64
const MutationStressRepeats = 512'u32

struct MutationSpan
{
    what: s64
    num:  s64
}

func compactMutationFor(text: string)->u64
{
    var map: Array'{ what, num: s64 }
    var nextId: s64
    for ch in text
    {
        let runLength = ch - '0'
        if @index & 1 do
            map.add({MutationFreeSpanId, runLength})
        else
        {
            map.add({nextId, runLength})
            nextId += 1
        }
    }

    var last = map.count - #wrap 1
    for i in @countof(map)
    {
        if map[i].what != MutationFreeSpanId do
            continue
        while map[last].what == MutationFreeSpanId do
            last -= 1
        if i >= last do
            break

        map[i].what = map[last].what
        if map[i].num == map[last].num
        {
            map[last].what = MutationFreeSpanId
            last -= 1
        }
        elif map[i].num > map[last].num
        {
            let rest = map[i].num - map[last].num
            map[i].num = map[last].num
            map[last].what = MutationFreeSpanId
            map.insertAt(i + 1, {what: MutationFreeSpanId, num: rest})
        }
        else do
            map[last].num -= map[i].num
    }

    var blockIndex, total: u64
    for span, visitIndex in map
    {
        if span.what == MutationFreeSpanId do
            break
        for span.num
        {
            total += blockIndex * span.what
            blockIndex += 1
        }
    }

    return total
}

func compactMutationWhile(text: string)->u64
{
    var map: Array'{ what, num: s64 }
    var nextId: s64
    for ch in text
    {
        let runLength = ch - '0'
        if @index & 1 do
            map.add({MutationFreeSpanId, runLength})
        else
        {
            map.add({nextId, runLength})
            nextId += 1
        }
    }

    var last = map.count - #wrap 1
    let bound = map.count
    var i = 0'u64
    while i < bound
    {
        if map[i].what != MutationFreeSpanId
        {
            i += 1
            continue
        }

        while map[last].what == MutationFreeSpanId do
            last -= 1
        if i >= last do
            break

        map[i].what = map[last].what
        if map[i].num == map[last].num
        {
            map[last].what = MutationFreeSpanId
            last -= 1
        }
        elif map[i].num > map[last].num
        {
            let rest = map[i].num - map[last].num
            map[i].num = map[last].num
            map[last].what = MutationFreeSpanId
            map.insertAt(i + 1, {what: MutationFreeSpanId, num: rest})
        }
        else do
            map[last].num -= map[i].num

        i += 1
    }

    var blockIndex, total: u64
    for span, visitIndex in map
    {
        if span.what == MutationFreeSpanId do
            break
        for span.num
        {
            total += blockIndex * span.what
            blockIndex += 1
        }
    }

    return total
}

func buildMutationStressInput(repeats: u32)->String
{
    var result: String
    for repeats do
        result += MutationStressChunk
    return result
}

#test
{
    @assert(compactMutationWhile(MutationStressChunk) == 1928'u64)
    @assert(compactMutationFor(MutationStressChunk) == 1928'u64)
}

#test
{
    let stress = buildMutationStressInput(MutationStressRepeats)
    @assert(compactMutationFor(stress) == compactMutationWhile(stress))
}
