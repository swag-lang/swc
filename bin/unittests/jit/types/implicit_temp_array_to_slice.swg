#global private

func implicitTempArrayToSliceConsume(values: const [..] u16)->u16
{
    return values[0] + values[3]
}

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

    let view: const [..] u16 = cb(false)
    Swag.require(view.count == 4)
    Swag.require(view[0] == 50_u16)
    Swag.require(view[3] == 80_u16)
    Swag.require(implicitTempArrayToSliceConsume(cb(false)) == 130_u16)
}
