#global fileprivate

#test
{
    let c   = @compiler
    let msg = c.getMessage()
    let cfg = c.getBuildCfg()
    c.compileString("")
    #assert(#typeof(msg) == const *Swag.CompilerMessage)
    #assert(#typeof(cfg) == *Swag.BuildCfg)
}
