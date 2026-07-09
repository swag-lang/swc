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
    mtd visitWithData(userData: *s32 = null, scale: s32 = 1, stmt: #code(item: s32, out: *s32))
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

func runNestedBlock()->bool
{
    var result = 0
    nestedBlock(41)
    {
        result = value
    }

    return result == 42
}

func runGenericAliasFold()->bool
{
    let values = [1, 2, 3]
    var sum    = 0
    genericAliasFold(values, 10, &sum)
    {
        dref out += value
    }

    return sum == 36
}

func runMemberMacroWithNamedArg()->bool
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

    return sum == 12
}

func runMemberMacroWithPositionalThenNamedArg()->bool
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

    return sum == 12
}

func runQualifiedGenericMacro()->bool
{
    let values = [1, 2, 3]
    var sum    = 0
    QualifiedMacroScope.fold(values, 10, &sum)
    {
        dref out += item
    }

    return sum == 36
}

const MacroScopeDoItTwiceOk      = #run runDoItTwice()
const MacroScopeCallerScopeOk    = #run runPreferCallerScope()
const MacroScopeRepeatWithIdxOk  = #run runRepeatWithIndex()
const MacroScopeApplyConfigOk    = #run runApplyConfig()
const MacroScopeBindTypedAliasOk = #run runBindTypedAlias()
const MacroScopeNestedBlockOk    = #run runNestedBlock()
const MacroScopeGenericAliasOk   = #run runGenericAliasFold()
const MacroScopeMemberMacroOk    = #run runMemberMacroWithNamedArg()
const MacroScopeMemberMacroPosOk = #run runMemberMacroWithPositionalThenNamedArg()
const MacroScopeQualifiedMacroOk = #run runQualifiedGenericMacro()

#assert(MacroScopeDoItTwiceOk)
#assert(MacroScopeCallerScopeOk)
#assert(MacroScopeRepeatWithIdxOk)
#assert(MacroScopeApplyConfigOk)
#assert(MacroScopeBindTypedAliasOk)
#assert(MacroScopeNestedBlockOk)
#assert(MacroScopeGenericAliasOk)
#assert(MacroScopeMemberMacroOk)
#assert(MacroScopeMemberMacroPosOk)
#assert(MacroScopeQualifiedMacroOk)
