#global private

func(U) localStructExplicitLiteral()->u16
{
    struct(T = U) Local
    {
        value: T
    }

    let data = Local'u16{value: 1'u16}
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

    let data = Local'u16{value: 1'u16}
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

func semaTest001()
{
    #assert(#typeof(localStructExplicitLiteral'f32()) == u16)
    #assert(#typeof(localStructImplicitLiteral(1.0'f32)) == f32)
    #assert(#typeof(localUnionExplicitLiteral'f32()) == u16)
    #assert(#typeof(localUnionImplicitLiteral(1.0'f32)) == f32)
}
