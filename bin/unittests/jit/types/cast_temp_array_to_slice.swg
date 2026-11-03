#global private

#test
{
    let cb = func(flag: bool)->[4] u16
    {
        if flag do
            return [10'u16, 20, 30, 40]
        return [50'u16, 60, 70, 80]
    }

    let view = cast(const [..] u16, cb(false))
    Swag.require(view.count == 4)
    Swag.require(view[0] == 50'u16)
    Swag.require(view[3] == 80'u16)
}
