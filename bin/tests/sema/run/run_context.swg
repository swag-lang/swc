#global fileprivate

#run
{
    let a = @getcontext().runtimeFlags
    @assert(a == .FromCompiler)
}

#run
{
    var a: Swag.Context
    a.runtimeFlags = .FromCompiler
    @assert(a.runtimeFlags == .FromCompiler)
    var b = &a.runtimeFlags
    var c = dref b
    @assert(c == .FromCompiler)
}