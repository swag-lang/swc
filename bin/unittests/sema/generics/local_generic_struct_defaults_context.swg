#global private

func(U) localGenericStructDefaultType()->bool
{
    struct(T = U) Local
    {
        value: T
    }

    var data: Local
    return #typeof(data.value) == U
}

func(U) localGenericStructExplicitType()->bool
{
    struct(T = U) Local
    {
        value: T
    }

    var data: Local'u16
    return #typeof(data.value) == u16
}

func(U) localGenericUnionExplicitType()->bool
{
    union(T = U) Local
    {
        value: T
        other: s32
    }

    var data: Local'u16
    return #typeof(data.value) == u16
}

func(U) localGenericUnionDefaultType()->bool
{
    union(T = U) Local
    {
        value: T
        other: s32
    }

    var data: Local
    return #typeof(data.value) == U
}

func semaTest001()
{
    #assert(localGenericStructDefaultType'f32())
    #assert(localGenericStructExplicitType'f32())
    #assert(localGenericUnionExplicitType'f32())
    #assert(localGenericUnionDefaultType'f32())
}
