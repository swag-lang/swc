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

    let view = cast(const [..] u16, cb(false))
    Swag.require(view.count == 4)
    Swag.require(view[0] == 50_u16)
    Swag.require(view[3] == 80_u16)
}
