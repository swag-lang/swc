#global fileprivate

// A reference parameter to an anonymous aggregate (`const &{x, y}`) is excluded from the
// auto-inline heuristic: resolving a member access on that ephemeral tuple type in the
// auto-inline clone races with the type's own member-symbol population (intermittent
// spurious "unknown symbol"). These functions must still compile and run correctly — they
// are simply not auto-inlined.

func takeTupleRef(param: const &{ x: s32, y: s32 })->s32
{
    return param.x + param.y
}

func checkTupleRef(param: const &{ x: s32, y: s32 })
{
    @assert(param.x == 1)
    @assert(param.y == 2)
}

#test
{
    @assert(takeTupleRef({3, 4}) == 7)
    checkTupleRef({1, 2})
}
