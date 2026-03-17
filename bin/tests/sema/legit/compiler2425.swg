#global fileprivate // swc-option sema-only
#global skip
const Cfg = #run dref @compiler.getBuildCfg()

#[Swag.ConstExpr]
func toto() => 1

#test
{
    @assert(#isconstexpr(1))

    var x = 0
    x += 1
    @assert(!#isconstexpr(x))
    @assert(!#isconstexpr(x + 1))

    if Cfg.backend.optimize
        @assert(#isconstexpr(toto() + 1))
    else
        @assert(!#isconstexpr(toto() + 1))

    const Y = toto() + 1
    @assert(Y == 2)
}
