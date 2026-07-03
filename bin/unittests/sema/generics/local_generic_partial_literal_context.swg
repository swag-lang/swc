#global private

func(T, V) localStructPartialLiteral()->V
{
    struct(A, B = string, C = V) Local
    {
        first:  A
        second: B
        third:  C
    }

    var third: V
    let data = Local'T{first: false, second: "ok", third: third}
    return data.third
}

func(T) localUnionValueDefaultPartialLiteral()->T
{
    union(N: s32 = 3, U = T) Local
    {
        value: U
        count: s32
    }

    var value: T
    let data = Local'5{value: value}
    return data.value
}

func semaTest001()
{
    #assert(#typeof(localStructPartialLiteral'(bool, f32)()) == f32)
    #assert(#typeof(localUnionValueDefaultPartialLiteral'f32()) == f32)
}
