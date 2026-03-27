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

#[Swag.Macro]
func nestedBlock(seed: s32, stmt: #code void)
{
    #macro
    {
        {
            let value = #up seed + 1
            #inject(#up stmt)
        }
    }
}

#[Swag.Macro]
func singleAlias(value: s32, stmt: #code void)
{
    #macro
    {
        let #alias0 = #up value * 3
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func pairAlias(a: s32, b: s32, stmt: #code void)
{
    #macro
    {
        let #alias0 = #up a + #up b
        let #alias1 = #up a * #up b
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func aliasWithUpVar(offset: s32, stmt: #code void)
{
    var local = offset + 100
    #macro
    {
        let #alias0 = #up local
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func repeatWithAlias(count: s32, stmt: #code void)
{
    var i = 0
    while i < count
    {
        #macro
        {
            let #alias0 = #up i
            #inject(#up stmt)
        }
        i += 1
    }
}

#[Swag.Macro]
func nestedBlockAlias(seed: s32, stmt: #code void)
{
    #macro
    {
        {
            let #alias0 = #up seed + 1
            let #alias1 = #up seed * 2
            #inject(#up stmt)
        }
    }
}

#[Swag.Macro]
func aliasWithConfig(cfg: MacroScopeConfig, stmt: #code void)
{
    #macro
    {
        let #alias0 = #up cfg.delta
        let #alias1 = #up cfg.delta * 2
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

#test
{
    var result = 0
    nestedBlock(41)
    {
        result = value
    }

    @assert(result == 42)
}

// --- Alias tests ---

#test
{
    var result = 0
    singleAlias(|tripled| 14)
    {
        result = tripled
    }

    @assert(result == 42)
}

#test
{
    var result = 0
    pairAlias(|sum, product| 3, 7)
    {
        result = sum + product
    }

    @assert(result == 10 + 21)
}

#test
{
    var result = 0
    aliasWithUpVar(|val| 5)
    {
        result = val
    }

    @assert(result == 105)
}

#test
{
    var sum = 0
    repeatWithAlias(|idx| 4)
    {
        sum += idx
    }

    @assert(sum == 6)
}

#test
{
    var result = 0
    nestedBlockAlias(|inc, doubled| 20)
    {
        result = inc + doubled
    }

    @assert(result == 21 + 40)
}

#test
{
    var cfg: MacroScopeConfig
    cfg.delta = 5

    var result = 0
    aliasWithConfig(|single, doubled| cfg)
    {
        result = single + doubled
    }

    @assert(result == 5 + 10)
}
