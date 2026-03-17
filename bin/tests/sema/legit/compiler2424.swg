#global fileprivate // swc-option sema-only
#global skip
const Cfg = #run dref @compiler.getBuildCfg()

func print(f: f32)
    verify
    {
        if Cfg.backend.optimize
            @assert(#isconstexpr(f))
        else
            @assert(!#isconstexpr(f))
        return true
    }
{
}

#[Swag.ConstExpr]
func tt() => 3.14

#test
{
    var x = 3.14
    print(tt())
}
