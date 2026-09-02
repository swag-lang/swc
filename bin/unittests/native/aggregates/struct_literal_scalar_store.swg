#global private     //

const MutationFreeSpanId = -1's64

struct MutationSpan
{
    what: s64
    num:  s64
}

func buildMutationMap(text: string)->[3] MutationSpan
{
    var nextId: s64
    var map:    [3] MutationSpan
    for ch, index in text
    {
        let runLength = ch - '0'
        if index & 1 do
            map[index] = {MutationFreeSpanId, runLength}
        else
        {
            map[index] = {nextId, runLength}
            nextId          += 1
        }
    }

    return map
}

#test
{
    let map = buildMutationMap("233")
    Swag.assert(map[0].what == 0)
    Swag.assert(map[0].num == 2)
    Swag.assert(map[1].what == -1)
    Swag.assert(map[1].num == 3)
    Swag.assert(map[2].what == 1)
    Swag.assert(map[2].num == 3)
}
