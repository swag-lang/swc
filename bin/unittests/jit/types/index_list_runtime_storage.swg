#test
{
    let flag = false
    let cb   = func(v: bool)->[2, 2] u16
    {
        if v
        {
            return [[31_u16, 32], [33, 34]]
        }
        return [[41_u16, 42], [43, 44]]
    }

    Swag.require(cb(flag)[1, 0] == 43_u16)
    Swag.require(cb(flag)[0, 1] == 42_u16)
}
