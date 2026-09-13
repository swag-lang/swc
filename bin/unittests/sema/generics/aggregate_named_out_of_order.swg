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
    Swag.assert(value == 1'u16)
}

func semaTest002()
{
    let unnamedFirst = pairFirst({1'u16, second: 2'u16})
    #assert(#typeof(unnamedFirst) == u16)
    Swag.assert(unnamedFirst == 1'u16)
}
