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
func injectPlain(stmt: #code void)
{
    #inject(stmt)
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

#[Swag.Macro]
func(T) genericAliasFold(values: [..] T, delta: T, sumPtr: *T, stmt: #code void)
{
    for @countof(values)
    {
        #macro
        {
            let #alias0 = #up values[@index] + #up delta
            let #alias1 = #up sumPtr
            #inject(#up stmt)
        }
    }
}

struct MemberMacroWalker
{
    values: [3] s32
}

impl MemberMacroWalker
{
    #[Swag.Macro]
    mtd visit(scale: s32 = 1, stmt: #code void)
    {
        let values = .values
        for @countof(values)
        {
            #macro
            {
                let item = #up values[@index] * #up scale
                #inject(#up stmt)
            }
        }
    }

    #[Swag.Macro]
    mtd visitWithData(userData: *s32 = null, scale: s32 = 1, stmt: #code void)
    {
        let values = .values
        for @countof(values)
        {
            #macro
            {
                let item = #up values[@index] * #up scale
                let out  = #up userData
                #inject(#up stmt)
            }
        }
    }
}

namespace QualifiedMacroScope
{
    #[Swag.Macro]
    public func(T) fold(values: [..] T, delta: T, sumPtr: *T, stmt: #code void)
    {
        for @countof(values)
        {
            #macro
            {
                let item = #up values[@index] + #up delta
                let out  = #up sumPtr
                #inject(#up stmt)
            }
        }
    }
}

// #macro injects statement twice
#test
{
    var a = 1
    doItTwice()
    {
        a += 1
    }

    @assert(a == 3)
}

// #macro prefers caller scope for variables
#test
{
    var a = 1
    preferCallerScope()
    {
        a += 2
    }

    @assert(a == 3)
}

// Plain macro #inject keeps #up bound to the macro caller
#test
{
    var a = 0
    injectPlain(#code { #up a += 1; })
    injectPlain()
    {
        #up a += 2
    }

    @assert(a == 3)
}

// #macro exposes loop index via #up
#test
{
    var sum = 0
    repeatWithIndex(4)
    {
        sum += index
    }

    @assert(sum == 6)
}

// #macro passes struct config into scope
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

// #macro binds typed alias from outer scope
#test
{
    var result = 0
    bindTypedAlias()
    {
        result = typed + 1
    }

    @assert(result == 42)
}

// #macro nested block exposes value via #up
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

// Single #alias0 binding in macro
#test
{
    var result = 0
    singleAlias(|tripled| 14)
    {
        result = tripled
    }

    @assert(result == 42)
}

// Pair #alias0/#alias1 bindings in macro
#test
{
    var result = 0
    pairAlias(|sum, product| 3, 7)
    {
        result = sum + product
    }

    @assert(result == 10 + 21)
}

// #alias with #up variable reference
#test
{
    var result = 0
    aliasWithUpVar(|val| 5)
    {
        result = val
    }

    @assert(result == 105)
}

// #alias in loop macro with repeat count
#test
{
    var sum = 0
    repeatWithAlias(|idx| 4)
    {
        sum += idx
    }

    @assert(sum == 6)
}

// Nested block with dual #alias bindings
#test
{
    var result = 0
    nestedBlockAlias(|inc, doubled| 20)
    {
        result = inc + doubled
    }

    @assert(result == 21 + 40)
}

// #alias with struct config fields
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

// Generic macro alias calls keep the trailing code block argument
#test
{
    let values = [1, 2, 3]
    var sum    = 0
    genericAliasFold(|value, out| values, 10, &sum)
    {
        dref out += value
    }

    @assert(sum == 36)
}

// Member macro calls keep the trailing code block after named arguments.
#test
{
    var walker: MemberMacroWalker
    walker.values[0] = 1
    walker.values[1] = 2
    walker.values[2] = 3

    var sum = 0
    walker.visit(scale: 2)
    {
        sum += item
    }

    @assert(sum == 12)
}

// Member macro calls keep the trailing code block after positional and named arguments.
#test
{
    var walker: MemberMacroWalker
    walker.values[0] = 1
    walker.values[1] = 2
    walker.values[2] = 3

    var sum = 0
    walker.visitWithData(&sum, scale: 2)
    {
        dref out += item
    }

    @assert(sum == 12)
}

// Qualified generic macro calls still consume the implicit trailing code block.
#test
{
    let values = [1, 2, 3]
    var sum    = 0
    QualifiedMacroScope.fold(values, 10, &sum)
    {
        dref out += item
    }

    @assert(sum == 36)
}

// #[Swag.Macro] variadic with same-name caller local variable and #up access
// Matches the shape in the existing genericAliasFold / QualifiedMacroScope.fold tests.
#[Swag.Macro]
func(T) variadicUpSameName(values: [..] T, sumPtr: *T)
{
    for @countof(values)
    {
        #macro
        {
            let item = #up values[@index]
            dref #up sumPtr += item
        }
    }
}

#test
{
    let values: [3] s32 = [1, 2, 3]
    var sum: s32         = 0
    variadicUpSameName(values, &sum)
    @assert(sum == 6)
}

#test
{
    let arr: [3] s32 = [1, 2, 3]
    var sum: s32      = 0
    variadicUpSameName(arr, &sum)
    @assert(sum == 6)
}

#test
{
    let values2: [3] s32 = [10, 20, 30]
    var sum2: s32         = 0
    variadicUpSameName(values2, &sum2)
    @assert(sum2 == 60)
}
