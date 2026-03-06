#global fileprivate
#global skip
//#[Swag.PrintBc]
#[Swag.Optimize(.All, false)]
#test
{
    if @jit
    {
        let cfg = @compiler.getBuildCfg().safetyGuards
        @assert(#sizeof(cfg) == 2)
    }
}
