#global private

// ---------------------------------------------------------------------------
// New '#code' declaration forms.
// - '#code' alone is a void statement block (same as legacy '#code void').
// - '#code->T' is an expression block returning T (same as legacy '#code T').
// - '#code(a, b: T)' declares named block parameters; names are the default
//   binder names at the call site and the binding names for '#inject'.
// ---------------------------------------------------------------------------

#[Swag.Macro]
func bareCode(stmt: #code)
{
    #inject(stmt)
}

#[Swag.Macro]
func arrowCond(cond: #code->bool)->bool
{
    return #inject(cond)
}

// Declared parameter names with a legacy '#alias' body: names map to slots.
#[Swag.Macro]
func withNames(value: s32, stmt: #code(v: s32, dbl: s32))
{
    let #alias0 = value
    let #alias1 = value * 2
    #inject(stmt)
}

// Declared parameter names bound at '#inject' time: no '#alias', no '#macro'.
#[Swag.Macro]
func withBindings(value: s32, stmt: #code(v: s32, dbl: s32))
{
    #inject(stmt, v = value, dbl = value * 2)
}

// A 'var' parameter gives the injected code a mutable binding.
#[Swag.Macro]
func withVarBinding(value: s32, stmt: #code(var v: s32))
{
    #inject(stmt, v = value)
}

// Legacy declaration, new call-site binder: binder names map to alias slots.
#[Swag.Macro]
func legacyPair(value: s32, stmt: #code void)
{
    let #alias0 = value
    let #alias1 = value * 2
    #inject(stmt)
}

// Mixins support '#inject' bindings too.
#[Swag.Mixin]
func mixinBinding(value: s32, stmt: #code(v: s32))
{
    #inject(stmt, v = value)
}

// A signed code value forwards to another macro with a compatible signature.
#[Swag.Macro]
func forwardNames(value: s32, stmt: #code(v: s32, dbl: s32))
{
    withBindings(value, stmt)
}

// Bindings compose with break/continue replacements in the same '#inject'.
#[Swag.Macro]
func repeatUpTo(count: s32, stmt: #code(index: s32))
{
    #scope(Outer)
    for i in count
    {
        #inject(stmt, index = i, break = break to Outer)
    }
}

// ---------------------------------------------------------------------------
// Runtime checks
// ---------------------------------------------------------------------------

func runBare()->bool
{
    var cpt = 0
    bareCode(#code { cpt += 1 })
    bareCode()
    {
        cpt += 1
    }
    return cpt == 2
}

func runArrowCond()->bool
{
    if !arrowCond(#code => true) do
        return false
    if !arrowCond(1 == 1) do
        return false
    return true
}

func runDefaultNames()->bool
{
    var total = 0
    withNames(10)
    {
        total = v + dbl
    }
    return total == 30
}

func runBinderTrailing()->bool
{
    var total = 0
    withNames(10) #code(a, b) { total = a + b }
    return total == 30
}

func runBinderInline()->bool
{
    var total = 0
    withNames(10, #code(a, b) { total = a + b })
    return total == 30
}

func runLegacyAliasSyntaxOnNames()->bool
{
    var total = 0
    withNames(|a, b| 10)
    {
        total = a + b
    }
    return total == 30
}

func runPartialBinder()->bool
{
    // Binder arity can be lower than the declared arity, like foreach.
    var total = 0
    withNames(10) #code(a) { total = a + dbl }
    return total == 30
}

func runBindings()->bool
{
    var total = 0
    withBindings(7)
    {
        total = v + dbl
    }
    return total == 21
}

func runBindingsWithBinder()->bool
{
    var total = 0
    withBindings(7) #code(x, y) { total = x + y }
    return total == 21
}

func runBindingsCallerScope()->bool
{
    // Injected user code must still see the caller scope with bindings present.
    var accum = 0
    withBindings(5)
    {
        accum += v
    }
    withBindings(6)
    {
        accum += dbl
    }
    return accum == 17
}

func runVarBinding()->bool
{
    var total = 0
    withVarBinding(5)
    {
        v += 1
        total = v
    }
    return total == 6
}

func runBinderOnLegacy()->bool
{
    var total = 0
    legacyPair(10) #code(a, b) { total = a + b }
    return total == 30
}

func runMixinBinding()->bool
{
    var total = 0
    mixinBinding(4)
    {
        total = v
    }
    return total == 4
}

func runForwardNames()->bool
{
    var total = 0
    forwardNames(3)
    {
        total = v + dbl
    }

    let ok = total == 9
    return ok
}

func runRepeatBindings()->bool
{
    var total = 0
    repeatUpTo(10)
    {
        total += index
        if index == 4 do
            break
    }

    return total == 0 + 1 + 2 + 3 + 4
}

func runBindingEvalOnce()->bool
{
    // Binding initializers evaluate once per '#inject', in macro scope.
    var evals = 0
    #[Swag.Macro]
    func onceMacro(stmt: #code(v: s32))
    {
        #inject(stmt, v = 111)
    }

    var got = 0
    onceMacro()
    {
        evals += 1
        got = v
    }

    return evals == 1 and got == 111
}

const BareOk               = #run runBare()
const ArrowCondOk          = #run runArrowCond()
const DefaultNamesOk       = #run runDefaultNames()
const BinderTrailingOk     = #run runBinderTrailing()
const BinderInlineOk       = #run runBinderInline()
const LegacyAliasSyntaxOk  = #run runLegacyAliasSyntaxOnNames()
const PartialBinderOk      = #run runPartialBinder()
const BindingsOk           = #run runBindings()
const BindingsBinderOk     = #run runBindingsWithBinder()
const BindingsCallerOk     = #run runBindingsCallerScope()
const VarBindingOk         = #run runVarBinding()
const BinderOnLegacyOk     = #run runBinderOnLegacy()
const MixinBindingOk       = #run runMixinBinding()
const ForwardNamesOk       = #run runForwardNames()
const RepeatBindingsOk     = #run runRepeatBindings()
const BindingEvalOnceOk    = #run runBindingEvalOnce()

#assert(BareOk)
#assert(ArrowCondOk)
#assert(DefaultNamesOk)
#assert(BinderTrailingOk)
#assert(BinderInlineOk)
#assert(LegacyAliasSyntaxOk)
#assert(PartialBinderOk)
#assert(BindingsOk)
#assert(BindingsBinderOk)
#assert(BindingsCallerOk)
#assert(VarBindingOk)
#assert(BinderOnLegacyOk)
#assert(MixinBindingOk)
#assert(ForwardNamesOk)
#assert(RepeatBindingsOk)
#assert(BindingEvalOnceOk)
