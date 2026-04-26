#global fileprivate

struct Pair32
{
    a: u32
    b: u32
}

func MakePair32()->Pair32
{
    return {a: 20, b: 22}
}

func SumPair32(value: Pair32)->u32
{
    return value.a + value.b
}

#test
{
    @assert(SumPair32(MakePair32()) == 42)
}
