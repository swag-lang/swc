#global fileprivate

/*
#[Swag.PrintMicro]
#[Swag.Optimize(false)]
#run
{
    let a = cast(u64) @getcontext().runtimeFlags
    if a & 1 do
        @print(true)
    else do
        @print(false)
}
*/

//#[Swag.PrintMicro]
#run
{
    var a: Swag.Context
    a.runtimeFlags = .FromCompiler
    @assert(a.runtimeFlags == .FromCompiler)
    var b = &a.runtimeFlags
    var c = dref b
    @assert(c == .FromCompiler)
}