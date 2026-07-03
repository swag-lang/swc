#global private

func contextSaysJit()->bool
{
    return @getcontext().runtimeFlags & .FromCompiler ? true : false
}

func jitCallMatchesContext()->bool
{
    return @jit() == contextSaysJit()
}

func jitCallCanBeStored()->bool
{
    let first = @jit()
    let second = @jit()
    return first == second and first == contextSaysJit()
}

func jitCallCanDriveBranch()->bool
{
    var value = 10
    if @jit() do
        value += 1
    else do
        value += 2

    return value == (contextSaysJit() ? 11 : 12)
}

func jitCallInCompoundExpression()->bool
{
    let expected = contextSaysJit()
    return (@jit() and expected) or (!@jit() and !expected)
}

#[Swag.Compiler]
func compilerJitCallMatchesContext()->bool
{
    return @jit() and @getcontext().runtimeFlags == .FromCompiler
}

#test
{
    @assert(jitCallMatchesContext())
    @assert(jitCallCanBeStored())
    @assert(jitCallCanDriveBranch())
    @assert(jitCallInCompoundExpression())
}

#test
{
    const ok = #run compilerJitCallMatchesContext()
    #assert(ok)
}
