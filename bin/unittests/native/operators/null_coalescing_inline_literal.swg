#global private

#[Swag.Inline]
func inlineZeroLiteralOrelseReturn(value: u8)->u8
{
    return 0'u8 != 0 ? 0'u8 : value
}

#test
{
    Swag.assert(inlineZeroLiteralOrelseReturn(9'u8) == 9'u8)
}
