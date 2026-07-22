#global private

// Dereferencing a `#null` pointer (here through a method-call receiver) is allowed
// without any guard: it simply dereferences the pointer, C-like. It may fault at
// runtime if the pointer is actually null, but the compiler does not force a proof
// at the use site. Two boundaries frame that freedom:
// - binding a `#null` pointer to a non-null reference/pointer storage is an error;
// - a `#null` PARAMETER whose first use on every path requires its address is a
//   dead contract (sema_err_nullable_param_contract), so the unguarded dereference
//   below lives behind a reachable early-out.

struct NullableDerefNode
{
    value: s32
}

impl NullableDerefNode
{
    mtd bump()->s32
    {
        .value += 1
        return .value
    }
}

func nullableDerefUnguarded(n: #null *NullableDerefNode, skip: bool)->s32
{
    if skip do
        return 0

    // No `if n do ...` guard: calling a method on the nullable pointer just derefs it.
    return n.bump()
}

#test
{
    var node = NullableDerefNode{value: 41}
    let r    = nullableDerefUnguarded(&node, false)
    @assert(r == 42)
    @assert(node.value == 42)
    @assert(nullableDerefUnguarded(&node, true) == 0)
}
