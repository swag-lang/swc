#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#[Swag.Optimize(.All, false)]
#test
{
    if @bytecode
    {
        let cfg = @compiler.getBuildCfg().safetyGuards
        @assert(#sizeof(cfg) == 2)
    }
}
