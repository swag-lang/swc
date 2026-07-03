#global private

// Dereferencing a `#null` pointer (here through a method-call receiver) is allowed
// without any guard: it simply dereferences the pointer, C-like. It may fault at
// runtime if the pointer is actually null, but the compiler no longer rejects it.
// Only binding a `#null` pointer to a non-null reference/pointer storage stays an error.

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

func nullableDerefUnguarded(n: #null *NullableDerefNode)->s32
{
    // No `if n do ...` guard: calling a method on the nullable pointer just derefs it.
    return n.bump()
}

#test
{
    var node = NullableDerefNode{value: 41}
    let r    = nullableDerefUnguarded(&node)
    @assert(r == 42)
    @assert(node.value == 42)
}
