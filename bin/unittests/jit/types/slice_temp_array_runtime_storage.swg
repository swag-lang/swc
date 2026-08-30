#global private

#test
{
    let cb = func(flag: bool)->[4] u16
    {
        if flag do
            return [10'u16, 20, 30, 40]
        return [50'u16, 60, 70, 80]
    }

    let mid = cb(false)[1 to 2]
    Swag.assert(mid.count == 2)
    Swag.assert(mid[0] == 60'u16)
    Swag.assert(mid[1] == 70'u16)
}
