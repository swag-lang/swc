#global fileprivate

const Cfg = #run dref @compiler.getBuildCfg()

func add(a: s32, b: s32)->s32 => a + b

#[Swag.Inline]
func addInline(a: s32, b: s32)->s32 => a + b

#[Swag.Inline]
func mulInline(a: s32, b: s32)->s32 { return a * b }

func helper(a: s32)->s32 { return a + 1 }

#[Swag.Inline]
func inlineCallsNonConst(a: s32)->s32 => helper(a)

#test
{
    #assert(addInline(2, 3) == 5)
    #assert(mulInline(4, 5) == 20)
}

#test
{
    #if Cfg.backend.optimize {
        #assert(add(2, 3) == 5)
    } #else {
        const V = #run add(2, 3)
        #assert(V == 5)
    }
}

#test
{
    var x: s32 = 3
    #assert(addInline(x, 1) == 4) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    #if Cfg.backend.optimize {
        #assert(inlineCallsNonConst(2) == 3)
    } #else {
        const V = #run inlineCallsNonConst(2)
        #assert(V == 3)
    }
}
