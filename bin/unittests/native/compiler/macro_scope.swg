#global private

struct MacroScopeConfig
{
    delta: s32
}

#[Swag.Macro]
func doItTwice(stmt: #code)
{
    #inject(stmt)
    #inject(stmt)
}

#[Swag.Macro]
func preferCallerScope(stmt: #code)
{
    // Macro-local 'a': injection hygiene keeps it invisible to the injected code.
    var a = 100
    #inject(stmt)
}

#[Swag.Macro]
func injectPlain(stmt: #code)
{
    // Macro-local 'a': must never shadow the caller's 'a' inside the injected code.
    var a = 666
    #inject(stmt)
}

#[Swag.Macro]
func repeatWithIndex(count: s32, stmt: #code(index: s32))
{
    var i = 0
    while i < count
    {
        #inject(stmt, index = i)
        i += 1
    }
}

#[Swag.Macro]
func applyConfig(cfg: MacroScopeConfig, stmt: #code(amount: s32))
{
    #inject(stmt, amount = cfg.delta)
}

#[Swag.Macro]
func bindTypedAlias(stmt: #code(typed: s32))
{
    alias ScopeValue = s32
    var value: ScopeValue = 41
    #inject(stmt, typed = value)
}

#[Swag.Macro]
func nestedBlock(seed: s32, stmt: #code(value: s32))
{
    {
        #inject(stmt, value = seed + 1)
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
    mtd visit(scale: s32 = 1, stmt: #code(item: s32))
    {
        let values = .values
        for @countof(values)
        {
            #inject(stmt, item = values[@index] * scale)
        }
    }

    #[Swag.Macro]
    mtd visitWithData(userData: *s32, scale: s32 = 1, stmt: #code(item: s32, out: *s32))
    {
        let values = .values
        for @countof(values)
        {
            #inject(stmt, item = values[@index] * scale, out = userData)
        }
    }
}

namespace QualifiedMacroScope
{
    #[Swag.Macro]
    public func(T) fold(values: [..] T, delta: T, sumPtr: *T, stmt: #code(item, out))
    {
        for @countof(values)
        {
            #inject(stmt, item = values[@index] + delta, out = sumPtr)
        }
    }
}

// Macro injects the statement twice
#test
{
    var a = 1
    doItTwice()
    {
        a += 1
    }

    @assert(a == 3)
}

// Injection hygiene: the macro-local 'a' never shadows the caller's 'a'
#test
{
    var a = 1
    preferCallerScope()
    {
        a += 2
    }

    @assert(a == 3)
}

// Injection hygiene with an inline '#code' argument: injected code resolves
// in the caller scope, with no escape marker needed
#test
{
    var a = 0
    injectPlain(#code { a += 1; })
    injectPlain()
    {
        a += 2
    }

    @assert(a == 3)
}

// Block parameter exposes the loop index to the injected code
#test
{
    var sum = 0
    repeatWithIndex(4)
    {
        sum += index
    }

    @assert(sum == 6)
}

// Block parameter bound from a struct config field
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

// Block parameter typed through a macro-local alias; the binding initializer
// evaluates in the macro's own scope
#test
{
    var result = 0
    bindTypedAlias()
    {
        result = typed + 1
    }

    @assert(result == 42)
}

// Block parameter bound from inside a nested block of the macro
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

// #[Swag.Macro] variadic [..] T parameter with for @countof + values[@index]:
// the macro body must resolve its own 'values' parameter even when the caller
// has a same-named local. Regression coverage for two clone bugs:
//   1. copyImplicitCastPayload lost the type on constant-cast clones (hit by let/const arrays).
//   2. cloneAstPreservingResolvedIdentifierSymbols prevents circular substitute chains that
//      caused wrong JIT runtime values (hit by any typed-variadic clone).
#[Swag.Macro]
func(T) variadicSameName(values: [..] T, sumPtr: *T)
{
    for @countof(values)
    {
        let item = values[@index]
        dref sumPtr += item
    }
}

// Caller variable same name as macro parameter, explicit type (const path: both bug 1 and 2).
#test
{
    let values: [3] s32 = [1, 2, 3]
    var sum:    s32         = 0
    variadicSameName(values, &sum)
    @assert(sum == 6)
}

// Caller variable same name, inferred type (the exact shape from the bug report).
#test
{
    var sum: s32   = 0
    let values     = [1's32, 2, 3]
    variadicSameName(values, &sum)
    @assert(sum == 6)
}

// Caller variable with a different name — verifies the fix doesn't regress non-collision cases.
#test
{
    let arr: [3] s32 = [1, 2, 3]
    var sum: s32      = 0
    variadicSameName(arr, &sum)
    @assert(sum == 6)
}

// Different values, same-name (additional const-array regression check).
#test
{
    let values: [3] s32 = [10, 20, 30]
    var sum:    s32         = 0
    variadicSameName(values, &sum)
    @assert(sum == 60)
}

// Different generic T (s64) — verifies generic type resolution is unaffected.
#test
{
    let values: [3] s64 = [10, 20, 30]
    var sum:    s64         = 0
    variadicSameName(values, &sum)
    @assert(sum == 60)
}

// Single-element array — verifies count = 1 works correctly.
#test
{
    let values: [1] s32 = [42]
    var sum:    s32         = 0
    variadicSameName(values, &sum)
    @assert(sum == 42)
}
