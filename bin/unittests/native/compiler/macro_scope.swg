#global private

struct MacroScopeConfig
{
    delta: s32
}

#[Swag.Macro]
func doItTwice(stmt: #code)
{
    #macro
    {
        #inject(#up stmt)
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func preferCallerScope(stmt: #code)
{
    var a = 100
    #macro
    {
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func injectPlain(stmt: #code)
{
    #inject(stmt)
}

#[Swag.Macro]
func repeatWithIndex(count: s32, stmt: #code)
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
func applyConfig(cfg: MacroScopeConfig, stmt: #code)
{
    #macro
    {
        let amount = #up cfg.delta
        #inject(#up stmt)
    }
}

#[Swag.Macro]
func bindTypedAlias(stmt: #code)
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
func nestedBlock(seed: s32, stmt: #code)
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
func singleAlias(value: s32, stmt: #code(tripled: s32))
{
    #inject(stmt, tripled = value * 3)
}

#[Swag.Macro]
func pairAlias(a: s32, b: s32, stmt: #code(sum: s32, product: s32))
{
    #inject(stmt, sum = a + b, product = a * b)
}

#[Swag.Macro]
func aliasWithUpVar(offset: s32, stmt: #code(val: s32))
{
    var local = offset + 100
    #inject(stmt, val = local)
}

#[Swag.Macro]
func repeatWithAlias(count: s32, stmt: #code(idx: s32))
{
    var i = 0
    while i < count
    {
        #inject(stmt, idx = i)
        i += 1
    }
}

#[Swag.Macro]
func nestedBlockAlias(seed: s32, stmt: #code(inc: s32, doubled: s32))
{
    {
        #inject(stmt, inc = seed + 1, doubled = seed * 2)
    }
}

#[Swag.Macro]
func aliasWithConfig(cfg: MacroScopeConfig, stmt: #code(single: s32, doubled: s32))
{
    #inject(stmt, single = cfg.delta, doubled = cfg.delta * 2)
}

#[Swag.Macro]
func(T) genericAliasFold(values: [..] T, delta: T, sumPtr: *T, stmt: #code(value, out))
{
    for @countof(values)
    {
        #inject(stmt, value = values[@index] + delta, out = sumPtr)
    }
}

struct MemberMacroWalker
{
    values: [3] s32
}

impl MemberMacroWalker
{
    #[Swag.Macro]
    mtd visit(scale: s32 = 1, stmt: #code)
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
    mtd visitWithData(userData: *s32 = null, scale: s32 = 1, stmt: #code)
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
    public func(T) fold(values: [..] T, delta: T, sumPtr: *T, stmt: #code)
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

// --- Block parameter tests ---

// Single block parameter binding in macro
#test
{
    var result = 0
    singleAlias(14)
    {
        result = tripled
    }

    @assert(result == 42)
}

// Paired block parameter bindings in macro
#test
{
    var result = 0
    pairAlias(3, 7)
    {
        result = sum + product
    }

    @assert(result == 10 + 21)
}

// Block parameter bound to a macro-local variable
#test
{
    var result = 0
    aliasWithUpVar(5)
    {
        result = val
    }

    @assert(result == 105)
}

// Block parameter in loop macro with repeat count
#test
{
    var sum = 0
    repeatWithAlias(4)
    {
        sum += idx
    }

    @assert(sum == 6)
}

// Nested block with dual block parameter bindings
#test
{
    var result = 0
    nestedBlockAlias(20)
    {
        result = inc + doubled
    }

    @assert(result == 21 + 40)
}

// Block parameters from struct config fields
#test
{
    var cfg: MacroScopeConfig
    cfg.delta = 5

    var result = 0
    aliasWithConfig(cfg)
    {
        result = single + doubled
    }

    @assert(result == 5 + 10)
}

// Generic macro calls keep the trailing code block argument
#test
{
    let values = [1, 2, 3]
    var sum    = 0
    genericAliasFold(values, 10, &sum)
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

// #[Swag.Macro] variadic [..] T parameter with for @countof + #up values[@index].
// Fixed two bugs:
//   1. copyImplicitCastPayload lost the type on constant-cast clones (hit by let/const arrays).
//   2. cloneAstPreservingResolvedIdentifierSymbols prevents circular substitute chains that
//      caused wrong JIT runtime values (hit by any typed-variadic clone).
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

// Caller variable same name as macro parameter, explicit type (const path: both bug 1 and 2).
#test
{
    let values: [3] s32 = [1, 2, 3]
    var sum: s32         = 0
    variadicUpSameName(values, &sum)
    @assert(sum == 6)
}

// Caller variable same name, inferred type (the exact shape from the bug report).
#test
{
    var sum: s32   = 0
    let values     = [1's32, 2, 3]
    variadicUpSameName(values, &sum)
    @assert(sum == 6)
}

// Caller variable with a different name — verifies the fix doesn't regress non-collision cases.
#test
{
    let arr: [3] s32 = [1, 2, 3]
    var sum: s32      = 0
    variadicUpSameName(arr, &sum)
    @assert(sum == 6)
}

// Different values, same-name (additional const-array regression check).
#test
{
    let values: [3] s32 = [10, 20, 30]
    var sum: s32         = 0
    variadicUpSameName(values, &sum)
    @assert(sum == 60)
}

// Different generic T (s64) — verifies generic type resolution is unaffected.
#test
{
    let values: [3] s64 = [10, 20, 30]
    var sum: s64         = 0
    variadicUpSameName(values, &sum)
    @assert(sum == 60)
}

// Single-element array — verifies count = 1 works correctly.
#test
{
    let values: [1] s32 = [42]
    var sum: s32         = 0
    variadicUpSameName(values, &sum)
    @assert(sum == 42)
}
