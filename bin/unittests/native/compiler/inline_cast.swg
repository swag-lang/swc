#global fileprivate

// Inlining a callee whose body contains a cast must materialize the cast faithfully.
// The tricky case: a value-to-`any` box. When the callee is sema-completed on its own,
// `value` is a runtime parameter, so the box reserves a `[sizeof(Any) + sizeof(value)]`
// runtime storage buffer on the cast node. Inlining clones that cast (and its storage
// symbol), but now the inlined argument is a constant, so the box folds to a self-contained
// constant `any`. The stale, oversized runtime buffer must be dropped, otherwise codegen
// tries to fill the larger buffer with the smaller constant and asserts.

#[Swag.EnumFlags]
enum TestFlags: u32
{
    A
    B
    C
    AB = A | B
}

#[Swag.Strict]
alias StrictTestFlags = TestFlags

#[Swag.Inline]
func boxStrictTestFlags(value: StrictTestFlags)->bool
{
    let boxed: any = value
    return @kindof(boxed) == StrictTestFlags and cast(StrictTestFlags) boxed == value
}

#[Swag.Inline]
func widen(value: u32)->u64
{
    return cast(u64) value + 1
}

// Unmarked twin: an auto-inline candidate under `-bc release` (Auto mode). A preceding
// constant `any` box of the same type is what made the stale-buffer mismatch deterministic.
func boxStrictTestFlagsAuto(value: StrictTestFlags)->bool
{
    let boxed: any = value
    return @kindof(boxed) == StrictTestFlags and cast(StrictTestFlags) boxed == value
}

#test
{
    @assert(boxStrictTestFlags(cast(StrictTestFlags) TestFlags.C))
    @assert(widen(41) == 42)

    const seed: any = cast(StrictTestFlags) TestFlags.B
    @assert(@kindof(seed) == StrictTestFlags)
    @assert(boxStrictTestFlagsAuto(cast(StrictTestFlags) TestFlags.C))
    @assert(boxStrictTestFlagsAuto(cast(StrictTestFlags) TestFlags.A))
}
