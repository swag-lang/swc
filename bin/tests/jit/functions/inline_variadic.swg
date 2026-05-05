#global fileprivate

#[Swag.Inline]
func inlineTypedVariadicConstForeach(values: s32...) -> s32
{
    var sum: s32 = 0
    foreach value in values do sum += value
    return sum
}

#[Swag.Inline]
func inlineTypedVariadicConstIndex(values: s32...) -> s32
{
    return values[0] + values[3]
}

func runInlineTypedVariadicConstForeach() -> s32
{
    return inlineTypedVariadicConstForeach(1, 2, 3, 4)
}

func runInlineTypedVariadicConstIndex() -> s32
{
    return inlineTypedVariadicConstIndex(10, 20, 30, 40)
}

#test
{
    const value = #run runInlineTypedVariadicConstForeach()
    #assert(value == 10)
}

#test
{
    const value = #run runInlineTypedVariadicConstIndex()
    #assert(value == 50)
}
