#global private

#test
{
    let cb = func(v: bool)->#decltype({first: 31_u16, second: 32_u16})
    {
        if v
        {
            return {first: 31_u16, second: 32_u16}
        }
        return {first: 41_u16, second: 42_u16}
    }

    Swag.require(cb(false).first == 41_u16)
    Swag.require(cb(true).second == 32_u16)
}
