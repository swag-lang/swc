#global private

// A slice parameter is a handle to storage owned elsewhere: whether the parameter can be
// reassigned says nothing about its elements. '&name' must therefore bind a mutable address
// in an inline function and in a macro exactly as it does in an ordinary function.

#[Swag.Inline]
func forRefInlineBump(values: [..] s32, action: func||(*s32))
{
    for &value in values do
        action(value)
}

#[Swag.Inline]
func(T) forRefInlineGenericBump(values: [..] T, action: func||(*T))
{
    for &value in values do
        action(value)
}

#[Swag.Macro]
func forRefMacroBump(values: [..] s32)
{
    for &value in values do
        value[] += 100
}

#test
{
    func run()->s32
    {
        var values = [1, 2, 3]
        forRefInlineBump(values, func(value: *s32) { value[] += 1 })
        forRefInlineGenericBump(values, func(value: *s32) { value[] += 10 })
        forRefMacroBump(values)
        return values[0] + values[1] + values[2]
    }

    Swag.assert(run() == 339)
    const V = #run run()
    #assert(V == 339)
}
