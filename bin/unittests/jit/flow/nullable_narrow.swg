#global private

// Flow-sensitive nullable narrowing: when the control flow proves a `#null` value is
// non-null (guards, comparisons, early exits, loops, short-circuits, ternaries), the
// value can be used where a non-null type is required, without an explicit `notnull`.

struct NarrowNode
{
    value: s32
    next:  #null *NarrowNode
}

struct NarrowOwner
{
    node: #null *NarrowNode
}

func takesPtr(p: *NarrowNode)->s32 => p.value

// A plain truthiness guard narrows inside the `then` branch.
func narrowIf(p: #null *NarrowNode)->s32
{
    if p do
        return takesPtr(p)
    return -1
}

// An explicit `!= null` comparison narrows the same way.
func narrowCmp(p: #null *NarrowNode)->s32
{
    if p != null do
        return takesPtr(p)
    return -1
}

// `== null` narrows the else side / fallthrough.
func narrowCmpElse(p: #null *NarrowNode)->s32
{
    if p == null do
        return -1
    return takesPtr(p)
}

// `if !p do return` guards the remainder of the function.
func narrowEarlyReturn(p: #null *NarrowNode)->s32
{
    if !p do
        return -1
    return takesPtr(p)
}

// `a and b` narrows both operands in the `then` branch.
func narrowAnd(a, b: #null *NarrowNode)->s32
{
    if a and b do
        return takesPtr(a) + takesPtr(b)
    return -1
}

// The right side of `and` sees the left side narrowed.
func narrowAndRhs(p: #null *NarrowNode)->bool
{
    return p and takesPtr(p) == 42
}

// `a == null or b == null` guards both operands after the early exit.
func narrowOrReturn(a, b: #null *NarrowNode)->s32
{
    if a == null or b == null do
        return -1
    return takesPtr(a) + takesPtr(b)
}

// A `while` condition narrows inside the body, re-proven at each iteration.
func narrowWhile(head: #null *NarrowNode)->s32
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
func narrowTernary(p: #null *NarrowNode)->s32
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
func narrowLet(p: #null *NarrowNode)->s32
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
    var p: #null *NarrowNode
    p = &node
    return takesPtr(p)
}

// Reassigning from a nullable source re-nullifies, and a new guard re-narrows.
func narrowKillAssign(p, q: #null *NarrowNode)->s32
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

// `notnull` on an already non-null value is a tolerated no-op.
func narrowAssumeTolerant()->s32
{
    var node = NarrowNode{value: 9}
    let q: *NarrowNode = &node
    return takesPtr(notnull q)
}

#test
{
    var node  = NarrowNode{value: 42}
    var node2 = NarrowNode{value: 8}
    node.next = &node2

    @assert(narrowIf(&node) == 42)
    @assert(narrowIf(null) == -1)
    @assert(narrowCmp(&node) == 42)
    @assert(narrowCmp(null) == -1)
    @assert(narrowCmpElse(&node) == 42)
    @assert(narrowCmpElse(null) == -1)
    @assert(narrowEarlyReturn(&node) == 42)
    @assert(narrowEarlyReturn(null) == -1)
    @assert(narrowAnd(&node, &node2) == 50)
    @assert(narrowAnd(&node, null) == -1)
    @assert(narrowAnd(null, &node2) == -1)
    @assert(narrowAndRhs(&node))
    @assert(!narrowAndRhs(&node2))
    @assert(!narrowAndRhs(null))
    @assert(narrowOrReturn(&node, &node2) == 50)
    @assert(narrowOrReturn(null, &node2) == -1)
    @assert(narrowWhile(&node) == 50)
    @assert(narrowWhile(null) == 0)
    @assert(narrowTernary(&node) == 42)
    @assert(narrowTernary(null) == -1)

    var owner = NarrowOwner{node: &node}
    @assert(narrowField(&owner) == 42)
    @assert(owner.narrowAuto() == 42)
    @assert(narrowIfLet(&owner) == 42)

    var emptyOwner: NarrowOwner
    @assert(narrowField(&emptyOwner) == -1)
    @assert(emptyOwner.narrowAuto() == -1)
    @assert(narrowIfLet(&emptyOwner) == -1)

    @assert(narrowLet(&node) == 42)
    @assert(narrowLet(null) == -1)
    @assert(narrowAssignGen() == 7)
    @assert(narrowKillAssign(&node, &node2) == 50)
    @assert(narrowKillAssign(&node, null) == 42)
    @assert(narrowKillAssign(null, &node2) == -1)
    @assert(narrowAssumeTolerant() == 9)
}
