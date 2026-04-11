#global fileprivate

struct CountedLoop
{
    count: u64
}

struct FixedCountedLoop
{
}

impl CountedLoop
{
    mtd opCount() => me.count
}

impl FixedCountedLoop
{
    mtd opCount() => 4'u64
}

#test
{
    func countedLoop()->s32
    {
        var acc: s32 = 0
        for 10 do
            acc += 6
        return acc
    }

    const V = #run countedLoop()
    #assert(V == 60)
}

#test
{
    func rangeLoopWithControl()->s32
    {
        var acc: s32 = 0
        for i in 0 to 10
        {
            if i == 2 do
                continue
            if i == 7 do
                break
            acc += cast(s32) i
        }

        return acc
    }

    const V = #run rangeLoopWithControl()
    #assert(V == 19)
}

#test
{
    func arrayCountLoop()->s32
    {
        var arr: [4] s32 = [2, 4, 6, 8]
        var acc: s32     = 0
        for arr
        {
            acc += arr[@index] * cast(s32) (@index + 1)
        }

        return acc
    }

    const V = #run arrayCountLoop()
    #assert(V == 60)
}

#test
{
    func reverseRangeLoop()->s32
    {
        var acc: s32 = 0
        for #reverse i in 1 to 4
        {
            acc = acc * 10 + cast(s32) i
        }

        return acc
    }

    const V = #run reverseRangeLoop()
    #assert(V == 4321)
}

#test
{
    func loopIndexVisibleThroughSwitch()->s32
    {
        var acc: s32 = 0
        for i in 1 to 3
        {
            switch i
            {
                case 1:
                    acc += cast(s32) @index
                default:
                    acc += cast(s32) @index
            }
        }

        return acc
    }

    const V = #run loopIndexVisibleThroughSwitch()
    #assert(V == 6)
}

#test
{
    func structCountLoop(value: CountedLoop)->s32
    {
        var acc: s32 = 0
        for value do
            acc += 1
        return acc
    }

    const V0 = #run structCountLoop({4})
    const V1 = #run structCountLoop({0})
    #assert(V0 == 4)
    #assert(V1 == 0)
}

#test
{
    func fixedStructCountLoop()->s32
    {
        let value = FixedCountedLoop{}
        var acc: s32 = 0
        for value do
            acc += 1
        return acc
    }

    const V = #run fixedStructCountLoop()
    #assert(V == 4)
}

#test
{
    func fixedStructIndexedLoop()->s32
    {
        let value = FixedCountedLoop{}
        var acc: s32 = 0
        for i in value do
            acc += cast(s32) i
        return acc
    }

    const V = #run fixedStructIndexedLoop()
    #assert(V == 6)
}
