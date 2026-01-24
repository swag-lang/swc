#global internal

#test
{
    let a = @countof(@pinfos.args)
    let b = @pinfos.args
    #assert(#typeof(b) == string)
    let c = @bytecode
    #assert(#typeof(c) == bool)
    let d = @args
    #assert(#typeof(d) == const [..] string)
    let e = @bytecode
    #assert(#typeof(e) == bool)
}
