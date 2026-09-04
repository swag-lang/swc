#global private

// The postfix '!' not-null assertion: the mirror of '?.'. Both test for null; '?.'
// skips the rest of the chain, '!' asserts the value is there and panics under safety
// when it is not. What follows then runs on a non-null value, so the result keeps its
// plain type instead of carrying a null outcome. Being postfix, '!' chains with '.',
// '[' and '('.

struct NotNullInner
{
    count: s64
}

struct NotNullNode
{
    value: s32
    name:  string = ""
    inner: NotNullInner
    next:  *NotNullNode?
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

func notNullGet()->*NotNullNode? => &g_notNullNode

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
func notNullMixedWithOptional(node: *NotNullNode?)->s32 => node?.next!.value orelse -1

// Interfaces dereference their itable the same way.
func notNullInterface(itf: INotNullAccess?)->s32 => itf!.get()

// Tolerated on an already proven value: the flow got there first.
func notNullRedundant(node: *NotNullNode?)->s32
{
    if node == null do
        return -1
    return node!.value
}

// A bare unwrap binds the proven value; nothing needs to follow the '!'.
func notNullBinding()->s32
{
    let node = notNullGet()!
    return node.value
}

// Indexing and calling a proven value.
func notNullIndex(buffer: [*] s32?)->s32 => buffer![1]

func notNullCall(fn: (func()->s32)?)->s32 => fn!()

// The dereference applies to the proven pointer.
func notNullDeref(value: *s32?)->s32 => value![]

// A binding to a nullable slot is asserted through its reference layer: what an
// 'opIndex' hands back is as nullable as the slot, and the assertion strips the flag
// inside the reference so the member access still reaches the object.
alias NotNullSlot = *NotNullNode?

struct NotNullBox
{
    slot: NotNullSlot
}

impl NotNullBox
{
    mtd const at()->const *NotNullSlot => &.slot
    mtd atMut()->*NotNullSlot          => &.slot
}

func notNullThroughConstRef(box: *NotNullBox)->s32
{
    let bound = box.at()
    return bound[]!.value
}

func notNullThroughRef(box: *NotNullBox)->s32
{
    let bound = box.atMut()
    return bound[]!.inner.count == 7 ? bound[]!.value : -1
}

// A cast whose source is asserted first: the assertion binds tighter than the cast.
func notNullCastOperand(raw: *void?)->s32
{
    let typed = cast(*NotNullNode) raw!
    return typed.value
}

// Rule C: a '!' after an error-management keyword asserts its RESULT, not the
// fallible call, which is what the keyword already swallowed.
func notNullFallible(fails: bool)->*NotNullNode? fail
{
    if fails do
        fail Swag.BaseError{"no node"}
    return &g_notNullNode
}

func notNullAfterExpect()->s32 => (expect notNullFallible(false)!).value

// An assignment through '!.' writes to the proven storage.
func notNullAssign(newValue: s32)
{
    notNullGet()!.value = newValue
}

#test
{
    g_notNullNode.value  = 42
    g_notNullNode.name   = "hello"
    g_notNullNode.inner  = {count: 7}
    g_notNullNode.next   = &g_notNullOther
    g_notNullOther.value = 9

    Swag.assert(notNullScalar() == 42)
    Swag.assert(notNullString() == "hello")
    Swag.assert(notNullNested() == 7)
    Swag.assert(notNullTwoLinks() == 9)
    Swag.assert(notNullInterface(cast(INotNullAccess) g_notNullNode) == 42)
    Swag.assert(notNullRedundant(&g_notNullNode) == 42)
    Swag.assert(notNullRedundant(null) == -1)
    Swag.assert(notNullMixedWithOptional(&g_notNullNode) == 9)
    Swag.assert(notNullMixedWithOptional(null) == -1)
}

#test
{
    g_notNullNode.value = 42
    Swag.assert(notNullMethod() == 43)

    notNullVoidCall()
    Swag.assert(g_notNullNode.value == 0)

    notNullAssign(5)
    Swag.assert(g_notNullNode.value == 5)
}

#test
{
    g_notNullNode.value = 42
    Swag.assert(notNullBinding() == 42)
    Swag.assert(notNullAfterExpect() == 42)
    Swag.assert(notNullCastOperand(&g_notNullNode) == 42)

    var values = [7's32, 8, 9]
    Swag.assert(notNullIndex(values.buffer) == 8)

    var single = 11's32
    Swag.assert(notNullDeref(&single) == 11)

    var box = NotNullBox{slot: &g_notNullNode}
    Swag.assert(notNullThroughConstRef(&box) == 42)
    Swag.assert(notNullThroughRef(&box) == 42)

    func twelve()->s32 => 12
    Swag.assert(notNullCall(&twelve) == 12)
}
