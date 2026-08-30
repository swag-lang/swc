#global private

#[Swag.Compiler]
func checkProcessInfosAndArgs()->bool
{
    let a = (Swag.processInfos().args).count
    let b = Swag.processInfos().args
    #assert(#typeof(b) == #null string)
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
func checkProcessInfosArgsType()->bool
{
    let a = Swag.processInfos().args
    #assert(#typeof(a) == #null string)
    return true
}

#test
{
    const ok = #run checkProcessInfosAndArgs()
    #assert(ok)
}

#test
{
    const ok = #run checkArgs()
    #assert(ok)
}

#test
{
    const ok = #run checkProcessInfosArgsType()
    #assert(ok)
}
