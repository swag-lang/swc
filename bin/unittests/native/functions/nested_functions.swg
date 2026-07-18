#global private
#global #[Swag.ExplicitNullability]

alias NestedUnary = func(s32)->s32

func runLocalDirectCall()->s32
{
    func increment(value: s32)->s32
    {
        return value + 1
    }

    return increment(41)
}

func runLocalSiblingCall()->s32
{
    func triple(value: s32)->s32
    {
        return value * 3
    }

    func tripleAndBias(value: s32)->s32
    {
        return triple(value) + 2
    }

    return tripleAndBias(5)
}

func runLocalFunctionPointer()->s32
{
    func addBias(value: s32)->s32
    {
        return value + 7
    }

    let cb: NestedUnary = &addBias
    return cb(5)
}

func runLocalRecursion(value: s32)->s32
{
    func factorial(n: s32)->s32
    {
        if n <= 1 do
            return 1
        return n * factorial(n - 1)
    }

    return factorial(value)
}

#test
{
    @assert(runLocalDirectCall() == 42)
}

#test
{
    @assert(runLocalSiblingCall() == 17)
}

#test
{
    @assert(runLocalFunctionPointer() == 12)
}

#test
{
    @assert(runLocalRecursion(6) == 720)
}
