#global fileprivate

struct MacroScopeConfig
{
    delta: s32
}

#[Swag.Macro]
func doItTwice(stmt: #code void)
{
    #macro
    {
        #inject(#up stmt)
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func preferCallerScope(stmt: #code void)
{
    var a = 100
    #macro
    {
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func repeatWithIndex(count: s32, stmt: #code void)
{
    var i = 0
    while i < count
    {
        #macro
        {
            let index = #up i
            #inject(#up stmt)
        }
        i += 1
    }
}

#[Swag.Macro]
func applyConfig(cfg: MacroScopeConfig, stmt: #code void)
{
    #macro
    {
        let amount = #up cfg.delta
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func bindTypedAlias(stmt: #code void)
{
    alias ScopeValue = s32
    var value: ScopeValue = 41
    #macro
    {
        var typed: #up ScopeValue = #up value
        #inject(#up stmt)
    }
}

func runDoItTwice()->bool
{
    var a = 1
    doItTwice()
    {
        a += 1
    }

    return a == 3
}

func runPreferCallerScope()->bool
{
    var a = 1
    preferCallerScope()
    {
        a += 2
    }

    return a == 3
}

func runRepeatWithIndex()->bool
{
    var sum = 0
    repeatWithIndex(4)
    {
        sum += index
    }

    return sum == 6
}

func runApplyConfig()->bool
{
    var cfg: MacroScopeConfig
    cfg.delta = 6

    var total = 1
    applyConfig(cfg)
    {
        total += amount
    }

    return total == 7
}

func runBindTypedAlias()->bool
{
    var result = 0
    bindTypedAlias()
    {
        result = typed + 1
    }

    return result == 42
}

const MacroScopeDoItTwiceOk      = #run runDoItTwice()
const MacroScopeCallerScopeOk    = #run runPreferCallerScope()
const MacroScopeRepeatWithIdxOk  = #run runRepeatWithIndex()
const MacroScopeApplyConfigOk    = #run runApplyConfig()
const MacroScopeBindTypedAliasOk = #run runBindTypedAlias()

#assert(MacroScopeDoItTwiceOk)
#assert(MacroScopeCallerScopeOk)
#assert(MacroScopeRepeatWithIdxOk)
#assert(MacroScopeApplyConfigOk)
#assert(MacroScopeBindTypedAliasOk)
