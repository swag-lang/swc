#global private

func jitValueFromRuntimeFlags()->bool
{
    return Swag.getContext().runtimeFlags & .FromCompiler ? true : false
}

func jitStableWithNullAllocatorContext()->bool
{
    let prev     = Swag.getContext()
    let expected = Swag.jit()

    var cxt = prev[]
    cxt.allocator = null
    Swag.setContext(cxt)

    let during              = Swag.jit()
    let matchesRuntimeFlags = during == jitValueFromRuntimeFlags()

    Swag.setContext(prev)
    return expected == during and matchesRuntimeFlags and Swag.jit() == expected
}

#[Swag.Compiler]
func compilerJitStableWithNullAllocatorContext()->bool
{
    let prev = Swag.getContext()

    var cxt = prev[]
    cxt.allocator = null
    Swag.setContext(cxt)

    let result = Swag.jit() and Swag.getContext().runtimeFlags == .FromCompiler and Swag.getContext().allocator == null

    Swag.setContext(prev)
    return result and Swag.jit()
}

#test
{
    Swag.assert(jitStableWithNullAllocatorContext())
}

#test
{
    const ok = #run compilerJitStableWithNullAllocatorContext()
    #assert(ok)
}
