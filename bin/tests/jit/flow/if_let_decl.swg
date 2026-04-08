#global fileprivate

func jitRetNothing()->#null string => null

func jitIfLetSimple()->s32
{
    if let x = 1
    {
        return x
    }
    else
    {
        return x + 10
    }
}

func jitIfLetWhereFalseElse()->s32
{
    if let x = 1 where false
    {
        return -1
    }
    else
    {
        return x + 2
    }
}

func jitIfLetDo()->s32
{
    if let x = 4 where x > 2 do
        return x + 1

    return -1
}

func jitIfLetNullableNullElse()->s32
{
    if let str = jitRetNothing()
    {
        return -1
    }

    return 1
}

func jitIfLetNullableWhereSkip()->s32
{
    if let str = jitRetNothing() where str[0] == 's'
    {
        return -1
    }

    return 1
}

#test
{
    const V = #run jitIfLetSimple()
    @assert(V == 1)
}

#test
{
    const V = #run jitIfLetWhereFalseElse()
    @assert(V == 3)
}

#test
{
    const V = #run jitIfLetDo()
    @assert(V == 5)
}

#test
{
    const V = #run jitIfLetNullableNullElse()
    @assert(V == 1)
}

#test
{
    const V = #run jitIfLetNullableWhereSkip()
    @assert(V == 1)
}
