#global private

// A '!' is an assertion written in operand position, so it proves its operand for the rest of
// the enclosing block. A second one on the same path asserts what the first already established:
// it costs a guard that can never fire, and it hides what really proves the value present.

struct NotNullProvenNode
{
    value: s32
    next:  *NotNullProvenNode?
}

// The dominating null test is the proof; the assertion adds nothing.
func notNullAfterGuard(node: *NotNullProvenNode?)->s32
{
    if node == null do
        return 0
    return node!.value     // swc-expected-error {{sema_err_notnull_already_proven}}
}

// 'Swag.assert' reads as a precondition and proves the path for the remainder of the block.
func notNullAfterAssert(node: *NotNullProvenNode?)->s32
{
    Swag.assert(node != null)
    return node!.value     // swc-expected-error {{sema_err_notnull_already_proven}}
}

// The first '!' is the proof: every later one on the same path is dead.
func notNullTwiceOnPath(node: *NotNullProvenNode?)->s32
{
    let first = node!.value
    return first + node!.value     // swc-expected-error {{sema_err_notnull_already_proven}}
}

// A member path is proven exactly like a root.
func notNullTwiceOnMemberPath(node: *NotNullProvenNode)->s32
{
    let first = node.next!.value
    return first + node.next!.value     // swc-expected-error {{sema_err_notnull_already_proven}}
}

// A value whose declared type is already non-null has nothing to assert.
func notNullOnNonNullDeclared(node: *NotNullProvenNode)->s32
{
    return node!.value     // swc-expected-error {{sema_err_notnull_already_proven}}
}

// An assertion inside a branch belongs to that branch, but the statement after the 'if' is
// reached only through it, so the proof carries.
func notNullProvenBySoleBranch(node: *NotNullProvenNode?)->s32
{
    if node == null do
        return 0
    else do
        discard node!.value     // swc-expected-error {{sema_err_notnull_already_proven}}
    return node.value
}

// An inlined body is judged at a call site it did not choose, so the clone is not reported --
// but the caller writing the redundant '!' in its own source still is.
#[Swag.Inline]
func notNullReadInline(node: *NotNullProvenNode)->s32 => node.value

#[Swag.NoInline]
func notNullReportedInlineArgument(node: *NotNullProvenNode)->s32
{
    return notNullReadInline(node!)     // swc-expected-error {{sema_err_notnull_already_proven}}
}

// A reassignment drops the proof, so the second assertion is needed again and is not reported.
func notNullReassigned(a: *NotNullProvenNode?, b: *NotNullProvenNode?)->s32
{
    var cur   = a
    let first = cur!.value
    cur = b
    return first + cur!.value
}

// A '!' in a short-circuit branch proves the rest of that branch, but not the following statement.
func notNullUnderShortCircuit(flag: bool, node: *NotNullProvenNode?)->s32
{
    if flag and node!.value > 0 do
        discard flag
    return node!.value
}

func notNullTwiceUnderShortCircuit(flag: bool, node: *NotNullProvenNode?)->bool
{
    return flag and (node!.value > 0 and node!.value > 1)     // swc-expected-error {{sema_err_notnull_already_proven}}
}

func notNullUnderFallback(node: *NotNullProvenNode?)->s32
{
    let first = node?.value orelse node!.value
    return first + node!.value
}

func notNullTwiceUnderFallback(node: *NotNullProvenNode?)->s32
{
    return node?.value orelse node!.value + node!.value     // swc-expected-error {{sema_err_notnull_already_proven}}
}

func notNullUnderConditional(flag: bool, node: *NotNullProvenNode?)->s32
{
    let first = flag ? node!.value : 0
    return first + node!.value
}

func notNullTwiceUnderConditional(flag: bool, node: *NotNullProvenNode?)->s32
{
    return flag ? node!.value + node!.value : 0     // swc-expected-error {{sema_err_notnull_already_proven}}
}

impl NotNullProvenNode
{
    mtd sameNode(other: *NotNullProvenNode)->bool => me == other
    mtd sameNodes(lhs, rhs: *NotNullProvenNode)->bool => lhs == rhs
}

func notNullUnderOptionalChain(node: *NotNullProvenNode?)->bool
{
    return node?.sameNodes(node!, node!)     // swc-expected-error {{sema_err_notnull_already_proven}}
}

func notNullDoesNotEscapeOptionalChain(node: *NotNullProvenNode?)->s32
{
    let same = node?.sameNode(node!) orelse false
    return (same ? 1 : 0) + node!.value
}
