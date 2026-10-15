#global private

#[Swag.Compiler]
func checkProcessInfoAndArgs()->bool
{
    let a = (Swag.processInfo().args).count
    let b = Swag.processInfo().args
    #assert(#typeof(b) == string?)
    let c = Swag.jit()
    #assert(#typeof(c) == bool)
    let d = Swag.args()
    #assert(#typeof(d) == const [..] string)
    let e = Swag.jit()
    #assert(#typeof(e) == bool)
    #assert(#typeof(a) == u64)
    Swag.assert(d.count >= 0)
    Swag.assert(e == Swag.jit())
    return true
}

#[Swag.Compiler]
func checkArgs()->bool
{
    let a = Swag.args()
    #assert(#typeof(a) == const [..] string)
    Swag.assert(a.count >= 0)
    return true
}

#[Swag.Compiler]
func checkProcessInfoArgsType()->bool
{
    let a = Swag.processInfo().args
    #assert(#typeof(a) == string?)
    return true
}

#test
{
    const ok = #run checkProcessInfoAndArgs()
    #assert(ok)
}

#test
{
    const ok = #run checkArgs()
    #assert(ok)
}

#test
{
    const ok = #run checkProcessInfoArgsType()
    #assert(ok)
}
