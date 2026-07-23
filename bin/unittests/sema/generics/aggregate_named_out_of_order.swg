#global private

struct(T) Pair
{
    first:  T
    second: T
}

func(T) pairFirst(value: Pair'T)->T
{
    return value.first
}

func semaTest001()
{
    let value = pairFirst({second: 2'u16, first: 1'u16})
    #assert(#typeof(value) == u16)
    @assert(value == 1'u16)
}
