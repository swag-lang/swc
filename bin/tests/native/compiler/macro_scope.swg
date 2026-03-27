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

#test
{
    var a = 1
    doItTwice()
    {
        a += 1
    }

    @assert(a == 3)
}

#test
{
    var a = 1
    preferCallerScope()
    {
        a += 2
    }

    @assert(a == 3)
}

#test
{
    var sum = 0
    repeatWithIndex(4)
    {
        sum += index
    }

    @assert(sum == 6)
}

#test
{
    var cfg: MacroScopeConfig
    cfg.delta = 6

    var total = 1
    applyConfig(cfg)
    {
        total += amount
    }

    @assert(total == 7)
}

#test
{
    var result = 0
    bindTypedAlias()
    {
        result = typed + 1
    }

    @assert(result == 42)
}
