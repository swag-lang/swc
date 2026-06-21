#global fileprivate

#[Swag.Inline]
func inlineGcdShadow(a0, b0: s64)->s64
{
    var a = a0
    var b = b0
    while b != 0
    {
        let temp = b
        b = a % b
        a = temp
    }

    return a
}

func inlineLcmShadow(a, b: s64)->s64
{
    if a > b do
        return a / inlineGcdShadow(a, b) * b
    return b / inlineGcdShadow(a, b) * a
}

#test
{
    @assert(inlineGcdShadow(12, 8) == 4)
    @assert(inlineLcmShadow(12, 8) == 24)
}
