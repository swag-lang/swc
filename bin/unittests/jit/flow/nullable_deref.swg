#global private

// Dereferencing a '?' pointer now requires a proof at the use site: a
// dominating null test (flow narrowing), a '!' assertion, or a '?.'
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

func nullableDerefNarrowed(n: *NullableDerefNode?, skip: bool)->s32
{
    if skip or n == null do
        return 0
    return n.bump()
}

func nullableDerefAsserted(n: *NullableDerefNode?, skip: bool)->s32
{
    if skip do
        return 0
    return n!.bump()
}

func nullableDerefOptional(n: *NullableDerefNode?)->s32
{
    return n?.bump() orelse 0
}

#test
{
    var node = NullableDerefNode{value: 41}
    Swag.assert(nullableDerefNarrowed(&node, false) == 42)
    Swag.assert(node.value == 42)
    Swag.assert(nullableDerefNarrowed(&node, true) == 0)
    Swag.assert(nullableDerefAsserted(&node, false) == 43)
    Swag.assert(nullableDerefOptional(&node) == 44)
    Swag.assert(nullableDerefOptional(null) == 0)
    Swag.assert(node.value == 44)
}
