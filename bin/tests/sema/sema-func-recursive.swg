#global internal

func directRegular(n: s32)->s32
{
    if n <= 1
    {
        return 1
    }

    return n * directRegular(n - 1)
}

func directShort(n: s32)->s32 => n <= 1 ? 1 : n * directShort(n - 1)

func indirectRegularA(n: s32)->s32
{
    if n <= 1
    {
        return 1
    }

    return n * indirectRegularB(n - 1)
}

func indirectRegularB(n: s32)->s32
{
    if n <= 1
    {
        return 1
    }

    return n * indirectRegularA(n - 1)
}

func indirectShortA(n: s32)->s32 => n <= 1 ? 1 : n * indirectShortB(n - 1)
func indirectShortB(n: s32)->s32 => n <= 1 ? 1 : n * indirectShortA(n - 1)

#test
{
    @assert(directRegular(6) == 720)
}

#test
{
    @assert(directShort(6) == 720)
}

#test
{
    @assert(indirectRegularA(6) == 720)
    @assert(indirectRegularB(6) == 720)
}

#test
{
    @assert(indirectShortA(6) == 720)
    @assert(indirectShortB(6) == 720)
}
