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
    genericAliasFold(|value, out| values, 10, &sum)
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
const MacroScopeQualifiedMacroOk = #run runQualifiedGenericMacro()

#assert(MacroScopeDoItTwiceOk)
#assert(MacroScopeCallerScopeOk)
#assert(MacroScopeRepeatWithIdxOk)
#assert(MacroScopeApplyConfigOk)
#assert(MacroScopeBindTypedAliasOk)
#assert(MacroScopeNestedBlockOk)
#assert(MacroScopeGenericAliasOk)
#assert(MacroScopeMemberMacroOk)
#assert(MacroScopeQualifiedMacroOk)
