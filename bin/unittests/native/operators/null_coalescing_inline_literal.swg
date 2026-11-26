#global private

#[Swag.Inline]
func inlineZeroLiteralOrelseReturn(value: u8)->u8
{
    return 0_u8 != 0 ? 0_u8 : value
}

#test
{
    Swag.require(inlineZeroLiteralOrelseReturn(9_u8) == 9_u8)
}
