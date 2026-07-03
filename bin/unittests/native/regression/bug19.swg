#global private

#[Swag.Inline]
func inlineZeroLiteralOrelseReturn(value: u8)->u8
{
    return 0 orelse value
}

#test
{
    @assert(inlineZeroLiteralOrelseReturn(9'u8) == 9'u8)
}
