#global private

struct(T) Pair
{
    first:  T
    second: T
}

func(T) pairFirst(value: Pair!{T})->T
{
    return value.first
}

func semaTest001()
{
    let value = pairFirst({second: 2_u16, first: 1_u16})
    #assert(#typeof(value) == u16)
    Swag.assert(value == 1_u16)
}

func semaTest002()
{
    let unnamedFirst = pairFirst({first: 1_u16, second: 2_u16})
    #assert(#typeof(unnamedFirst) == u16)
    Swag.assert(unnamedFirst == 1_u16)
}
