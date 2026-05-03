#global fileprivate

func(U) localStructDefaultType()->bool
{
    struct(T = U) Local
    {
        value: T
    }

    var data: Local
    data.value = cast(U) 2
    return #typeof(data.value) == U and data.value == cast(U) 2
}

func(U) localStructExplicitType()->u16
{
    struct(T = U) Local
    {
        value: T
    }

    var data: Local'u16
    data.value = 7
    return data.value
}

func(U) localUnionDefaultType()->bool
{
    union(T = U) Local
    {
        value: T
        other: s32
    }

    var data: Local
    data.value = cast(U) 3
    return #typeof(data.value) == U and data.value == cast(U) 3
}

func(U) localUnionExplicitType()->u16
{
    union(T = U) Local
    {
        value: T
        other: s32
    }

    var data: Local'u16
    data.value = 9
    return data.value
}

func(U) localStructExplicitLiteral()->u16
{
    struct(T = U) Local
    {
        value: T
    }

    let data = Local'u16{value: 11'u16}
    return data.value
}

func(U) localStructImplicitLiteral(value: U)->U
{
    struct(T = U) Local
    {
        value: T
    }

    let data = Local{value: value}
    return data.value
}

func(U) localUnionExplicitLiteral()->u16
{
    union(T = U) Local
    {
        value: T
        other: s32
    }

    let data = Local'u16{value: 13'u16}
    return data.value
}

func(U) localUnionImplicitLiteral(value: U)->U
{
    union(T = U) Local
    {
        value: T
        other: s32
    }

    let data = Local{value: value}
    return data.value
}

func(T, V) localStructPartialLiteral(tail: V)->V
{
    struct(A, B = string, C = V) Local
    {
        first:  A
        second: B
        third:  C
    }

    let data = Local'T{first: false, second: "ok", third: tail}
    return data.third
}

func(T) localUnionPartialLiteral(value: T)->T
{
    union(N: s32 = 3, U = T) Local
    {
        value: U
        count: s32
    }

    let data = Local'5{value: value}
    return data.value
}

#test
{
    @assert(localStructDefaultType'f32())
    @assert(localUnionDefaultType'f32())

    let structValue = localStructExplicitType'f32()
    let unionValue = localUnionExplicitType'f32()
    #assert(#typeof(structValue) == u16)
    #assert(#typeof(unionValue) == u16)
    @assert(structValue == 7'u16)
    @assert(unionValue == 9'u16)
}

#test
{
    let structExplicit = localStructExplicitLiteral'f32()
    let structImplicit = localStructImplicitLiteral(1.5'f32)
    let unionExplicit = localUnionExplicitLiteral'f32()
    let unionImplicit = localUnionImplicitLiteral(2.5'f32)

    #assert(#typeof(structExplicit) == u16)
    #assert(#typeof(structImplicit) == f32)
    #assert(#typeof(unionExplicit) == u16)
    #assert(#typeof(unionImplicit) == f32)
    @assert(structExplicit == 11'u16)
    @assert(structImplicit == 1.5'f32)
    @assert(unionExplicit == 13'u16)
    @assert(unionImplicit == 2.5'f32)
}

#test
{
    let structPartial = localStructPartialLiteral'(bool, f32)(4.5)
    let unionPartial = localUnionPartialLiteral'f32(6.5)

    #assert(#typeof(structPartial) == f32)
    #assert(#typeof(unionPartial) == f32)
    @assert(structPartial == 4.5'f32)
    @assert(unionPartial == 6.5'f32)
}
