#global fileprivate

#test
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
}

#test
{
    let a = @args
    #assert(#typeof(a) == const [..] string)
    @assert(@countof(a) >= 0)
}

#test
{
    let a = @pinfos.args
    #assert(#typeof(a) == string)
}
