#global private

#[Swag.Inline]
func inlineArrayLiteralDigits(values: [4] s32)->s32
{
    var digits: s32 = 0
    for value in values
    {
        digits = digits * 10 + value
    }

    return digits
}

#[Swag.Inline]
func inlineArrayLiteralEdges(values: [4] s32)->s32
{
    return values[0] * 10 + values[3]
}

func inlineArrayLiteralDigitsForward()->s32
{
    return inlineArrayLiteralDigits([4, 3, 2, 1])
}

#test
{
    @assert(inlineArrayLiteralDigitsForward() == 4321)
    @assert(inlineArrayLiteralEdges([7, 8, 9, 6]) == 76)
}
