#global fileprivate

alias InlineFunctionExprUnary = func||(s32)->s32

#[Swag.Inline]
func inlineFunctionExprAccept(cb: InlineFunctionExprUnary)->InlineFunctionExprUnary => cb

func semaInlineFunctionExprArg()
{
    let cb = inlineFunctionExprAccept(func(value: s32)->s32 { return value * 2 })

    #assert(#typeof(cb) == InlineFunctionExprUnary)
}
