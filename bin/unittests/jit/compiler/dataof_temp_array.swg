#global private

#test
{
    let cb = func(flag: bool)->[4] u16
    {
        if flag
        {
            return [10_u16, 20, 30, 40]
        }
        return [50_u16, 60, 70, 80]
    }

    let p = (cb(false)).buffer
    Swag.require(p[0] == 50_u16)
    Swag.require(p[3] == 80_u16)
}
