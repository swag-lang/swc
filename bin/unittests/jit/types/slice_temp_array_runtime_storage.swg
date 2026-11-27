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

    let mid = cb(false)[1 to 2]
    Swag.require(mid.count == 2)
    Swag.require(mid[0] == 60_u16)
    Swag.require(mid[1] == 70_u16)
}
