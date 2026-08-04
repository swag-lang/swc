#global private

// '!.' not-null access: the mirror of '?.'. Both test the left side for null; '?.'
// skips the rest of the chain, '!.' asserts the value is there and panics under
// safety when it is not. The access itself then runs on a non-null value, so the
// result keeps its plain type instead of carrying a null outcome.

struct NotNullInner
{
    count: s64
}

struct NotNullNode
{
    value: s32
    name:  string = ""
    inner: NotNullInner
    next:  #null *NotNullNode
}

impl NotNullNode
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

interface INotNullAccess
{
    mtd get()->s32
}

impl INotNullAccess for NotNullNode
{
    mtd impl get()->s32 => .value
}

var g_notNullNode:  NotNullNode
var g_notNullOther: NotNullNode

func notNullGet()->#null *NotNullNode => &g_notNullNode

// A scalar result stays a scalar: no 'orelse' is needed, unlike '?.'.
func notNullScalar()->s32 => notNullGet()!.value

// The member type is preserved through the assertion.
func notNullString()->string => notNullGet()!.name

// Nested field paths resolve on the proven value.
func notNullNested()->s64 => notNullGet()!.inner.count

// Methods and void calls go through the same receiver materialization.
func notNullMethod()->s32 => notNullGet()!.bump()

func notNullVoidCall()
{
    notNullGet()!.reset()
}

// Several links in one chain each assert their own left side.
func notNullTwoLinks()->s32 => notNullGet()!.next!.value

// Mixed with '?.': the skip outcome still governs the chain, so the scalar result
// needs the 'orelse' the optional chain requires.
func notNullMixedWithOptional(node: #null *NotNullNode)->s32 => node?.next!.value orelse -1

// Interfaces dereference their itable the same way.
func notNullInterface(itf: #null INotNullAccess)->s32 => itf!.get()

// Tolerated on an already proven value, like 'notnull': the flow got there first.
func notNullRedundant(node: #null *NotNullNode)->s32
{
    if node == null do
        return -1
    return node!.value
}

// An assignment through '!.' writes to the proven storage.
func notNullAssign(newValue: s32)
{
    notNullGet()!.value = newValue
}

#test
{
    g_notNullNode.value   = 42
    g_notNullNode.name    = "hello"
    g_notNullNode.inner   = {count: 7}
    g_notNullNode.next    = &g_notNullOther
    g_notNullOther.value  = 9

    @assert(notNullScalar() == 42)
    @assert(notNullString() == "hello")
    @assert(notNullNested() == 7)
    @assert(notNullTwoLinks() == 9)
    @assert(notNullInterface(cast(INotNullAccess) g_notNullNode) == 42)
    @assert(notNullRedundant(&g_notNullNode) == 42)
    @assert(notNullRedundant(null) == -1)
    @assert(notNullMixedWithOptional(&g_notNullNode) == 9)
    @assert(notNullMixedWithOptional(null) == -1)
}

#test
{
    g_notNullNode.value = 42
    @assert(notNullMethod() == 43)

    notNullVoidCall()
    @assert(g_notNullNode.value == 0)

    notNullAssign(5)
    @assert(g_notNullNode.value == 5)
}
