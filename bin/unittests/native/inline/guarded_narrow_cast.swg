#global private

#[Swag.Inline]
func narrow(value: u32)->u16
{
    switch
    {
    case value <= 0xFFFF:
        return cast(u16, value)
    default:
        return 7
    }
}

#test
{
    Swag.require(narrow(42) == 42)
    Swag.require(narrow(0x1F642) == 7)
}
