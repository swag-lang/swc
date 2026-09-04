#global private

// Flow-sensitive nullable narrowing: when the control flow proves a `?` value is
// non-null (guards, comparisons, early exits, loops, short-circuits, ternaries), the
// value can be used where a non-null type is required, without an explicit `!`.

struct NarrowNode
{
    value: s32
    next:  *NarrowNode?
}

struct NarrowOwner
{
    node: *NarrowNode?
}

func takesPtr(p: *NarrowNode)->s32 => p.value

// A plain truthiness guard narrows inside the `then` branch.
func narrowIf(p: *NarrowNode?)->s32
{
    if p do
        return takesPtr(p)
    return -1
}

// An explicit `!= null` comparison narrows the same way.
func narrowCmp(p: *NarrowNode?)->s32
{
    if p != null do
        return takesPtr(p)
    return -1
}

// `== null` narrows the else side / fallthrough.
func narrowCmpElse(p: *NarrowNode?)->s32
{
    if p == null do
        return -1
    return takesPtr(p)
}

// `if !p do return` guards the remainder of the function.
func narrowEarlyReturn(p: *NarrowNode?)->s32
{
    if !p do
        return -1
    return takesPtr(p)
}

// `a and b` narrows both operands in the `then` branch.
func narrowAnd(a, b: *NarrowNode?)->s32
{
    if a and b do
        return takesPtr(a) + takesPtr(b)
    return -1
}

// The right side of `and` sees the left side narrowed.
func narrowAndRhs(p: *NarrowNode?)->bool
{
    return p and takesPtr(p) == 42
}

// `a == null or b == null` guards both operands after the early exit.
func narrowOrReturn(a, b: *NarrowNode?)->s32
{
    if a == null or b == null do
        return -1
    return takesPtr(a) + takesPtr(b)
}

// A `while` condition narrows inside the body, re-proven at each iteration.
func narrowWhile(head: *NarrowNode?)->s32
{
    var total = 0
    var cur   = head
    while cur
    {
        total += takesPtr(cur)
        cur   = cur.next
    }
    return total
}

// Ternary branches inherit the condition's facts.
func narrowTernary(p: *NarrowNode?)->s32
{
    return p ? takesPtr(p) : -1
}

// Field access paths narrow too.
func narrowField(o: *NarrowOwner)->s32
{
    if o.node do
        return takesPtr(o.node)
    return -1
}

impl NarrowOwner
{
    // Implicit `me`-rooted paths behave like explicit ones.
    mtd narrowAuto()->s32
    {
        if .node do
            return takesPtr(.node)
        return -1
    }
}

// A `let` initialized from a narrowed value inherits the non-null type.
func narrowLet(p: *NarrowNode?)->s32
{
    if p
    {
        let q = p
        return takesPtr(q)
    }
    return -1
}

// Assigning a statically non-null value proves the path for the rest of the block.
func narrowAssignGen()->s32
{
    var node = NarrowNode{value: 7}
    var p: *NarrowNode?
    p = &node
    return takesPtr(p)
}

// Reassigning from a nullable source re-nullifies, and a new guard re-narrows.
func narrowKillAssign(p, q: *NarrowNode?)->s32
{
    var cur = p
    if cur
    {
        var total = takesPtr(cur)
        cur = q
        if cur do
            total += takesPtr(cur)
        return total
    }
    return -1
}

// `if let` bindings are non-null inside the block.
func narrowIfLet(o: *NarrowOwner)->s32
{
    if let n = o.node do
        return takesPtr(n)
    return -1
}

// `!` on an already non-null value is a tolerated no-op.
func narrowNotNullTolerant()->s32
{
    var node           = NarrowNode{value: 9}
    let q: *NarrowNode = &node
    return takesPtr(q!)
}

// `Swag.assert` panics when its condition is false, so the statements after it are only
// reachable with the condition true: its facts hold for the remainder of the block.
func narrowAssert(p: *NarrowNode?)->s32
{
    Swag.assert(p != null)
    return takesPtr(p)
}

// The proof holds across the statements that follow it, not just the next one.
func narrowAssertAcrossStatements(p: *NarrowNode?)->s32
{
    Swag.assert(p != null)
    let first = takesPtr(p)
    let next  = p.next
    return first + (next ? 1 : 0) + takesPtr(p)
}

// A logical chain proves every operand it requires.
func narrowAssertAnd(a, b: *NarrowNode?)->s32
{
    Swag.assert(a != null and b != null)
    return takesPtr(a) + takesPtr(b)
}

// Field access paths are asserted like locals.
func narrowAssertField(o: *NarrowOwner)->s32
{
    Swag.assert(o.node != null)
    return takesPtr(o.node)
}

// Reassigning from a nullable source kills the asserted fact; a second assert re-proves it.
func narrowAssertKill(p, q: *NarrowNode?)->s32
{
    var cur = p
    Swag.assert(cur != null)
    var total = takesPtr(cur)

    cur = q
    Swag.assert(cur != null)
    return total + takesPtr(cur)
}

// An assertion inside a nested block does not outlive it.
func narrowAssertScoped(p: *NarrowNode?)->s32
{
    {
        Swag.assert(p != null)
        discard takesPtr(p)
    }

    if p do
        return takesPtr(p)
    return -1
}

#test
{
    var node  = NarrowNode{value: 42}
    var node2 = NarrowNode{value: 8}
    node.next = &node2

    Swag.assert(narrowIf(&node) == 42)
    Swag.assert(narrowIf(null) == -1)
    Swag.assert(narrowCmp(&node) == 42)
    Swag.assert(narrowCmp(null) == -1)
    Swag.assert(narrowCmpElse(&node) == 42)
    Swag.assert(narrowCmpElse(null) == -1)
    Swag.assert(narrowEarlyReturn(&node) == 42)
    Swag.assert(narrowEarlyReturn(null) == -1)
    Swag.assert(narrowAnd(&node, &node2) == 50)
    Swag.assert(narrowAnd(&node, null) == -1)
    Swag.assert(narrowAnd(null, &node2) == -1)
    Swag.assert(narrowAndRhs(&node))
    Swag.assert(!narrowAndRhs(&node2))
    Swag.assert(!narrowAndRhs(null))
    Swag.assert(narrowOrReturn(&node, &node2) == 50)
    Swag.assert(narrowOrReturn(null, &node2) == -1)
    Swag.assert(narrowWhile(&node) == 50)
    Swag.assert(narrowWhile(null) == 0)
    Swag.assert(narrowTernary(&node) == 42)
    Swag.assert(narrowTernary(null) == -1)

    var owner = NarrowOwner{node: &node}
    Swag.assert(narrowField(&owner) == 42)
    Swag.assert(owner.narrowAuto() == 42)
    Swag.assert(narrowIfLet(&owner) == 42)

    var emptyOwner: NarrowOwner
    Swag.assert(narrowField(&emptyOwner) == -1)
    Swag.assert(emptyOwner.narrowAuto() == -1)
    Swag.assert(narrowIfLet(&emptyOwner) == -1)

    Swag.assert(narrowLet(&node) == 42)
    Swag.assert(narrowLet(null) == -1)
    Swag.assert(narrowAssignGen() == 7)
    Swag.assert(narrowKillAssign(&node, &node2) == 50)
    Swag.assert(narrowKillAssign(&node, null) == 42)
    Swag.assert(narrowKillAssign(null, &node2) == -1)
    Swag.assert(narrowNotNullTolerant() == 9)

    Swag.assert(narrowAssert(&node) == 42)
    Swag.assert(narrowAssertAcrossStatements(&node) == 85)
    Swag.assert(narrowAssertAnd(&node, &node2) == 50)
    Swag.assert(narrowAssertField(&owner) == 42)
    Swag.assert(narrowAssertKill(&node, &node2) == 50)
    Swag.assert(narrowAssertScoped(&node) == 42)
}
