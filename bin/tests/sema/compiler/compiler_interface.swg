#global internal

#test
{
    let c   = @compiler
    let msg = c.getMessage()
    let cfg = c.getBuildCfg()
    c.compileString("")
    #assert(#typeof(msg) == const *Swag.CompilerMessage)
    #assert(#typeof(cfg) == *Swag.BuildCfg)
}

#test
{
    let c = @compiler
    c.compileString(1) // swc-expected-error {{sema_err_too_many_arguments}}
}
