#global fileprivate

#[Swag.Compiler]
func checkProcessInfosAndArgs()->bool
{
    let a = @countof(@pinfos.args)
    let b = @pinfos.args
    #assert(#typeof(b) == string)
    let c = @jit
    #assert(#typeof(c) == bool)
    let d = @args
    #assert(#typeof(d) == const [..] string)
    let e = @jit
    #assert(#typeof(e) == bool)
    #assert(#typeof(a) == u64)
    @assert(@countof(d) >= 0)
    @assert(e == @jit)
    return true
}

#[Swag.Compiler]
func checkArgs()->bool
{
    let a = @args
    #assert(#typeof(a) == const [..] string)
    @assert(@countof(a) >= 0)
    return true
}

#[Swag.Compiler]
func checkProcessInfosArgsType()->bool
{
    let a = @pinfos.args
    #assert(#typeof(a) == string)
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
