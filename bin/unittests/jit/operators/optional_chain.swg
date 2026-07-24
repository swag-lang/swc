#global private

// '?.' optional chaining: the whole postfix chain is skipped when the tested value
// is null. The chain result is either nullable-capable (carries the null outcome),
// void (statement), or handed to an immediate 'orelse' fallback.

struct OptChainInner
{
    count: s64
}

struct OptChainNode
{
    value: s32
    ratio: f32
    ok:    bool
    name:  string = ""
    inner: OptChainInner
    next:  #null *OptChainNode
}

impl OptChainNode
{
    mtd bump()->s32
    {
        .value += 1
        return .value
    }

    mtd reset()
    {
        .value = 0
    }
}

interface IOptChain
{
    mtd get()->s32;
}

impl IOptChain for OptChainNode
{
    mtd impl get()->s32 => .value
}

var g_optChainNode:  OptChainNode
var g_optChainOther: OptChainNode

func optChainGet(use: bool)->#null *OptChainNode
{
    if use do
        return &g_optChainNode
    return null
}

// Fused with 'orelse': scalar results flow through untested.
func optChainScalar(use: bool)->s32
{
    return optChainGet(use)?.value orelse -1
}

// A false/zero produced value is NOT the null outcome: it must flow through.
func optChainBool(use: bool)->bool
{
    return optChainGet(use)?.ok orelse true
}

func optChainFloat(use: bool)->f32
{
    return optChainGet(use)?.ratio orelse -1.5
}

// Deep chain through a struct value field.
func optChainDeep(use: bool)->s64
{
    return optChainGet(use)?.inner.count orelse -1
}

// Method call through '?.'.
func optChainMethod(use: bool)->s32
{
    return optChainGet(use)?.bump() orelse -1
}

// Void method call: the chain is a statement.
func optChainVoidCall(use: bool)
{
    let node = optChainGet(use)
    node?.reset()
}

// Nullable-capable results carry the null outcome in their own type.
func optChainNullablePtr(use: bool)->#null *OptChainNode
{
    return optChainGet(use)?.next
}

// Wide nullable-capable result (string): the null outcome is a null string.
func optChainString(use: bool)->#null string
{
    return optChainGet(use)?.name
}

// Two '?.' links in one chain.
func optChainTwoLinks(use: bool)->s32
{
    return optChainGet(use)?.next?.value orelse -1
}

// A '?.' chain used as a condition.
func optChainCondition(use: bool)->bool
{
    if optChainGet(use)?.next do
        return true
    return false
}

// Interface method through '?.'.
func optChainInterface(itf: #null IOptChain)->s32
{
    return itf?.get() orelse -1
}

// A redundant '?.' inside a narrowed region stays valid.
func optChainNarrowedRedundant(p: #null *OptChainNode)->s32
{
    if p == null do
        return -1
    return p?.value orelse -2
}

#test
{
    g_optChainNode.value       = 42
    g_optChainNode.ratio       = 2.5
    g_optChainNode.ok          = false
    g_optChainNode.name        = "hello"
    g_optChainNode.inner.count = 7
    g_optChainNode.next        = &g_optChainOther
    g_optChainOther.value      = 9

    @assert(optChainScalar(true) == 42)
    @assert(optChainScalar(false) == -1)
    @assert(optChainBool(true) == false)
    @assert(optChainBool(false) == true)
    @assert(optChainFloat(true) == 2.5)
    @assert(optChainFloat(false) == -1.5)
    @assert(optChainDeep(true) == 7)
    @assert(optChainDeep(false) == -1)
}

#test
{
    g_optChainNode.value = 42
    @assert(optChainMethod(true) == 43)
    @assert(optChainMethod(false) == -1)

    optChainVoidCall(true)
    @assert(g_optChainNode.value == 0)
    g_optChainNode.value = 5
    optChainVoidCall(false)
    @assert(g_optChainNode.value == 5)
}

#test
{
    g_optChainNode.name   = "hello"
    g_optChainNode.next   = &g_optChainOther
    g_optChainOther.value = 9

    @assert(optChainNullablePtr(true) == &g_optChainOther)
    @assert(optChainNullablePtr(false) == null)
    @assert(optChainString(true) == "hello")
    @assert(optChainString(false) == null)
    @assert(optChainTwoLinks(true) == 9)
    @assert(optChainTwoLinks(false) == -1)
    @assert(optChainCondition(true))
    @assert(!optChainCondition(false))

    g_optChainNode.next = null
    @assert(optChainTwoLinks(true) == -1)
    @assert(!optChainCondition(true))
    g_optChainNode.next = &g_optChainOther

    g_optChainNode.value = 42
    @assert(optChainInterface(cast(IOptChain) g_optChainNode) == 42)
    @assert(optChainInterface(null) == -1)
    @assert(optChainNarrowedRedundant(&g_optChainNode) == 42)
    @assert(optChainNarrowedRedundant(null) == -1)
}
