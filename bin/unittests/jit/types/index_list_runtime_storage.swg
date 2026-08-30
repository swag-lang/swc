#test
{
    let flag = false
    let cb   = func(v: bool)->[2, 2] u16
    {
        if v do
            return [[31'u16, 32], [33, 34]]
        return [[41'u16, 42], [43, 44]]
    }

    Swag.assert(cb(flag)[1, 0] == 43'u16)
    Swag.assert(cb(flag)[0, 1] == 42'u16)
}
