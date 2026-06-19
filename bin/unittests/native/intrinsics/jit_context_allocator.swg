#global fileprivate

func jitValueFromRuntimeFlags()->bool
{
    return @getcontext().runtimeFlags & .FromCompiler ? true : false
}

func jitStableWithNullAllocatorContext()->bool
{
    let prev = @getcontext()
    let expected = @jit()

    var cxt = dref prev
    cxt.allocator = null
    @setcontext(cxt)

    let during = @jit()
    let matchesRuntimeFlags = during == jitValueFromRuntimeFlags()

    @setcontext(prev)
    return expected == during and matchesRuntimeFlags and @jit() == expected
}

#[Swag.Compiler]
func compilerJitStableWithNullAllocatorContext()->bool
{
    let prev = @getcontext()

    var cxt = dref prev
    cxt.allocator = null
    @setcontext(cxt)

    let result = @jit() and @getcontext().runtimeFlags == .FromCompiler and @getcontext().allocator == null

    @setcontext(prev)
    return result and @jit()
}

#test
{
    @assert(jitStableWithNullAllocatorContext())
}

#test
{
    const ok = #run compilerJitStableWithNullAllocatorContext()
    #assert(ok)
}
