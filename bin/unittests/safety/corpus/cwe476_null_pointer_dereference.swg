#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-476 - NULL pointer dereference
//
// Juliet's largest single family, and the one Swag answers in the type system rather than in
// an analysis.
//
// A pointer is non-null BY DEFAULT. Nullability is opted into with the '?' suffix, and a
// nullable value cannot be dereferenced, indexed, member-accessed or called while it is still
// nullable: every use site needs a proof. The proof is a dominating null test (flow
// narrowing), the postfix '!' assertion, or '?.' which skips the access instead.
//
// So the class splits in two. Dereferencing a nullable value without a proof is a TYPE error,
// rejected in every configuration. Asserting with '!' on a value that is null at run time is
// a guard, and follows '.Expect'.
// -----------------------------------------------------------------------------

struct Node
{
    value: s32
    next:  *Node?
}

var nodeStorage: Node

// --- Faults ---

// No proof at all: a type error, not an analysis result.
func derefWithoutProof(node: *Node?)->s32
{
    return node.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// The proof is dropped by a reassignment, so the second access needs its own.
func proofDroppedByReassignment(first, second: *Node?)->s32
{
    if first == null do
        return -1
    let before = first.value
    var node   = first
    node       = second
    return before + node.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// A proof made inside a branch belongs to that branch.
func proofDoesNotEscapeBranch(node: *Node?, ready: bool)->s32
{
    if ready
    {
        if node == null do
            return -1
    }

    return node.value     // swc-expected-error {{sema_err_nullable_member_access}}
}

// '!' asserts rather than proves: when the value really is null, the guard answers.
#[Swag.Safety(.Expect, true)]
func assertOnNull(node: *Node?)->s32
{
    return node!.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run assertOnNull(null)
}

// The static half proves it where it can, without any guard.
#[Swag.Safety(.Expect, false), Swag.Sanity(.Null, true)]
func derefProvenNull()->s32
{
    let node: *Node? = null
    return node!.value     // swc-expected-error {{sanity_err_null_deref}}
}

#test
{
    #run derefProvenNull()
}

// --- Sound ---

// A dominating test narrows the value for the rest of the block.
func narrowedByTest(node: *Node?)->s32
{
    if node == null do
        return -1
    return node.value
}

// 'Swag.assert' is a dominating test like any other, and reads as a precondition.
func narrowedByAssert(node: *Node?)->s32
{
    Swag.assert(node != null)
    return node.value
}

// The left side of 'and' narrows the right side.
func narrowedByConjunction(node: *Node?)->bool
{
    return node != null and node.value == 5
}

// Every path assigns a present value, so what follows needs no assertion.
func narrowedByJoin(ready: bool)->s32
{
    var node: *Node?
    if ready do
        node = &nodeStorage
    else do
        node = &nodeStorage
    return node.value
}

// '?.' skips the access and 'orelse' supplies the scalar fallback.
func guardedAccess(node: *Node?)->s32
{
    return node?.value orelse -1
}

// A bare pointer needs no ceremony at all, which is the point of the default.
func bareNeedsNothing(node: *Node)->s32
{
    return node.value
}

#test
{
    nodeStorage.value = 5
    Swag.assert(narrowedByTest(&nodeStorage) == 5)
    Swag.assert(narrowedByTest(null) == -1)
    Swag.assert(narrowedByAssert(&nodeStorage) == 5)
    Swag.assert(narrowedByConjunction(&nodeStorage))
    Swag.assert(!narrowedByConjunction(null))
    Swag.assert(narrowedByJoin(opaqueBool(true)) == 5)
    Swag.assert(guardedAccess(null) == -1)
    Swag.assert(guardedAccess(&nodeStorage) == 5)
    Swag.assert(bareNeedsNothing(&nodeStorage) == 5)
}
