#global fileprivate
#global skip

func pressCount(mask: u32)->u32
{
    var value = mask
    var result: u32

    while value != 0
    {
        result += value & 1'u32
        value >>= 1
    }

    return result
}

func minimumPresses(buttonMasks: const [..] u32, targetMask: u32)->u32
{
    var best = 255'u32
    let combinationCount = 1'u32 << cast(u32) @countof(buttonMasks)

    var combo: u32
    while combo < combinationCount
    {
        var state: u32
        var button: u32

        while button < @countof(buttonMasks)
        {
            if (combo & (1'u32 << button)) != 0
                do state ^= buttonMasks[button]

            button += 1
        }

        if state == targetMask
        {
            let presses = pressCount(combo)
            if presses < best
                do best = presses
        }

        combo += 1
    }

    return best
}

#test
{
    const masks: [6] u32 = [8, 10, 4, 12, 5, 3]
    @assert(minimumPresses(masks, 6'u32) == 2'u32)
}
