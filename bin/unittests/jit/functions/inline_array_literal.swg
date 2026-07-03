#global private

#[Swag.Inline]
func inlineArrayLiteralForeach(values: [4] s32) -> s32
{
    var sum: s32 = 0
    foreach value in values
    {
        sum += value
    }

    return sum
}

#[Swag.Inline]
func inlineArrayLiteralMiddle(values: [4] s32) -> s32
{
    return values[1] + values[2]
}

func runInlineArrayLiteralForeach() -> s32
{
    return inlineArrayLiteralForeach([1, 2, 3, 4])
}

func runInlineArrayLiteralMiddle() -> s32
{
    return inlineArrayLiteralMiddle([10, 20, 30, 40])
}

#test
{
    const value = #run runInlineArrayLiteralForeach()
    #assert(value == 10)
}

#test
{
    const value = #run runInlineArrayLiteralMiddle()
    #assert(value == 50)
}
