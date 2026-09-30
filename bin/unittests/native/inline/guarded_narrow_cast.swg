#global private

#[Swag.Inline]
func narrow(value: u32)->u16
{
    switch
    {
    case value <= 0xFFFF:
        return cast(u16) value
    default:
        return 7
    }
}

#test
{
    Swag.assert(narrow(42) == 42)
    Swag.assert(narrow(0x1F642) == 7)
}
