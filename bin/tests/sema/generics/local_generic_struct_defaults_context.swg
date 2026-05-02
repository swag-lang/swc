#global fileprivate

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

#test
{
    #assert(localGenericStructDefaultType'f32())
    #assert(localGenericStructExplicitType'f32())
}
