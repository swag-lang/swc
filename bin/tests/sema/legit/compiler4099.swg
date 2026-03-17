#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#[Swag.Optimize(.All, false)]
#test
{
    if @bytecode
    {
        var cfg: *Swag.BuildCfg
        cfg = @compiler.getBuildCfg()
        //@print(cfg.debugAllocator)
        let cfg1 = @compiler.getBuildCfg()
        @assert(cfg == cfg1)
    }
}
