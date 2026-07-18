#global private

func semaTest001()
{
    let c   = @compiler
    let msg = c.getMessage()
    let cfg = c.getBuildCfg()
    c.compileString("")
    #assert(#typeof(msg) == #null const *Swag.CompilerMessage)
    #assert(#typeof(cfg) == #null *Swag.BuildCfg)
}
