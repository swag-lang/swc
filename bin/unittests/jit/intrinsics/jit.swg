#global private

func contextSaysJit()->bool
{
    return Swag.getContext().runtimeFlags & .FromCompiler ? true : false
}

func jitCallMatchesContext()->bool
{
    return Swag.jit() == contextSaysJit()
}

func jitCallCanBeStored()->bool
{
    let first  = Swag.jit()
    let second = Swag.jit()
    return first == second and first == contextSaysJit()
}

func jitCallCanDriveBranch()->bool
{
    var value = 10
    if Swag.jit() do
        value += 1
    else do
        value += 2

    return value == (contextSaysJit() ? 11 : 12)
}

func jitCallInCompoundExpression()->bool
{
    let expected = contextSaysJit()
    return (Swag.jit() and expected) or (!Swag.jit() and !expected)
}

#[Swag.Compiler]
func compilerJitCallMatchesContext()->bool
{
    return Swag.jit() and Swag.getContext().runtimeFlags == .FromCompiler
}

#test
{
    Swag.assert(jitCallMatchesContext())
    Swag.assert(jitCallCanBeStored())
    Swag.assert(jitCallCanDriveBranch())
    Swag.assert(jitCallInCompoundExpression())
}

#test
{
    const ok = #run compilerJitCallMatchesContext()
    #assert(ok)
}
