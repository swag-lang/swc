#global private

// Dereferencing a '#null' pointer now requires a proof at the use site: a
// dominating null test (flow narrowing), a 'notnull' assertion, or a '?.'
// guarded access. This file exercises the three sanctioned routes at runtime;
// the rejected unguarded forms live in errors/sema/sema_err_nullable_use_site.swg.

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

func nullableDerefNarrowed(n: #null *NullableDerefNode, skip: bool)->s32
{
    if skip or n == null do
        return 0
    return n.bump()
}

func nullableDerefAsserted(n: #null *NullableDerefNode, skip: bool)->s32
{
    if skip do
        return 0
    return (notnull n).bump()
}

func nullableDerefOptional(n: #null *NullableDerefNode)->s32
{
    return n?.bump() orelse 0
}

#test
{
    var node = NullableDerefNode{value: 41}
    @assert(nullableDerefNarrowed(&node, false) == 42)
    @assert(node.value == 42)
    @assert(nullableDerefNarrowed(&node, true) == 0)
    @assert(nullableDerefAsserted(&node, false) == 43)
    @assert(nullableDerefOptional(&node) == 44)
    @assert(nullableDerefOptional(null) == 0)
    @assert(node.value == 44)
}
