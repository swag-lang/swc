#global fileprivate

#[Swag.Inline]
func inlineAdd(a: s32, b: s32)->s32 => a + b

#[Swag.Inline]
func inlineNamed(a: s32, b: s32, c: s32)->s32
{
    var x: s32 = a + b
    return x + c
}

#[Swag.Inline]
func inlineBranch(flag: bool, x: s32, y: s32)->s32
{
    if flag
    {
        return x
    }

    return y
}

#run
{
    var a: s32 = inlineAdd(20, 22)
    @assert(a == 42)

    var b: s32 = inlineNamed(a: 1, c: 40, b: 1)
    @assert(b == 42)

    var c: s32 = inlineBranch(true, 42, 5)
    var d: s32 = inlineBranch(false, 5, 42)
    @assert(c == 42)
    @assert(d == 42)
}

#test
{
    inlineAdd(1, 2) // swc-expected-error {{sema_err_return_value_must_be_used}}
}
