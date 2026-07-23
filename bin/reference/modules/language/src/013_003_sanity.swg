#global private

/**
# 'Sanity Checks in Swag'

Where '#[Swag.Safety]' adds **runtime** guards that panic on invalid operations,
'#[Swag.Sanity]' controls the **static** checks: analyses that run at compile time
and report errors before the program ever runs. They reuse the same 'SafetyWhat'
flags, cost nothing at runtime, and can be toggled at the same granularity levels —
module, function, or file.

You can also configure them globally from the build configuration with
'buildCfg.sanityGuards'.
*/

/**
> NOTE:
> Sanity checks are enabled by default in every build configuration except
> 'fast-compile'. This differs from runtime safety, which is disabled in 'release'
> for performance: the static checks stay on in 'release' since they are free.
*/

/**
# 'Proven Runtime Faults'

The compiler proves some runtime faults statically and reports them as errors
instead of letting the (guaranteed) panic or crash happen at runtime: division by
a value proven to be zero ('.Math'), proven integer overflow ('.Overflow'),
dereferencing or calling a pointer proven to be null ('.Null'), and indexing a
stack array with a provably out-of-range constant ('.BoundCheck') — free coverage
in 'release', where the runtime guard is off.
*/
#test
{
    var d = 0
    var a = 10

    // var x = a / d  // Uncomment: error, division by zero (proven)

    var arr: [4] s32
    var i = 5
    arr[0] = i

// let y = arr[i]  // Uncomment: error, out-of-bounds access (proven)
}

/**
# 'Returning the Address of a Local'

The frame dies with the return, so the address of a local is always dangling
('.Memory').
*/
var sanityGlobalValue: s32

func sanityGlobalAddress()->*s32
{
    // var v: s32
    // return &v  // Uncomment: error, returns the address of a local
    return &sanityGlobalValue     // A global outlives the call
}

/**
# 'Borrow Escapes'

Views that borrow function-local storage — pointers, slices, strings, 'any',
interfaces, closures capturing by address — must not outlive that storage
('.Lifecycle'). Returning them, storing them into a global, or writing them through
a caller-visible pointer is a compile-time error. This includes views of an OWNER's
heap payload (a 'string' view of a local 'Core.String', for example): the payload is
freed when the owner drops, and a local owner drops with its scope.
*/
var sanityGlobalBuffer: [4] u8

#test
{
    func makeView()->const [..] u8
    {
        // var buf: [4] u8
        // return cast(const [..] u8) buf  // Uncomment: error, borrow escapes
        return cast(const [..] u8) sanityGlobalBuffer     // A global's storage is fine
    }

    @assert(@countof(makeView()) == 4)
}

/**
The analysis follows borrows across local bindings — including a call result bound
to a local and returned later ('let p = passthrough(&v); return p') — control-flow
joins, and even opaque calls: a function whose return value may borrow one of its
parameters is summarized, and the call site is checked against what was really
passed in. The summaries chain, so wrapping a borrowing function does not hide the
borrow, and they cross module boundaries through the generated module API (the
'Swag.BorrowSummary' attribute).
*/
#test
{
    func passthrough(p: *s32)->*s32
    {
        return p
    }

    func wrapper(p: *s32)->*s32
    {
        return passthrough(p)     // Inherits the summary of 'passthrough'
    }

    func caller()->*s32
    {
        // var v: s32
        // return wrapper(&v)  // Uncomment: error, borrows a local through the chain
        return wrapper(&sanityGlobalValue)     // Caller-owned data flows through
    }

    @assert(caller() == &sanityGlobalValue)
}

/**
An aggregate can carry several independent borrows. Swag keeps every parameter
origin in function summaries and tracks local borrows by field path. Assigning a
sibling field therefore neither hides nor inherits another field's borrow. Constant
array indices are tracked independently; a dynamic index conservatively overlaps
every element. Opaque-call snapshots also survive control-flow joins and compose
through arbitrarily deep local call chains.
*/
#test
{
    struct Views
    {
        local:  *s32
        global: *s32
    }

    var local: s32
    var views: Views = undefined
    views.local  = &local
    views.global = &sanityGlobalValue
    @assert(views.global == &sanityGlobalValue)
}

/**
# 'Stored Arguments'

A callee that stores its parameter into storage that outlives the call (a global)
makes any borrowed argument escape, whatever happens to the call result. This
summary is inferred like the return summary, chains through wrappers, and crosses
module boundaries the same way. Storing one parameter into storage reachable from
ANOTHER ('container.add(&item)') is summarized as a pair: the call site errors when
the container argument is a global and the stored one borrows a local.
*/
var sanityGlobalStash: #null *s32

func sanityStash(p: *s32)
{
    sanityGlobalStash = p     // Legal here: 'p' is caller-owned. Judged at call sites.
}

#test
{
    func caller()
    {
        // var v: s32
        // sanityStash(&v)  // Uncomment: error, the callee keeps the borrow
        sanityStash(&sanityGlobalValue)     // A global outlives everything
    }

    caller()
    @assert(sanityGlobalStash == &sanityGlobalValue)
}

/**
# 'Use After Free and Double Free'

Every allocation flows through the [[Swag.IAllocator]] interface, whose methods make
the operation structural: the analysis infers which functions FREE what their
parameters point to (a 'frees' summary, chained through wrappers and across modules
like the other summaries). Dereferencing a pointer after it was provably freed — or
freeing it twice — is a compile-time error ('.Lifecycle'). Aliases and conditional
frees are misses, never false positives; reassigning the pointer makes it valid
again.
*/
#test
{
    func exampleAlloc(size: u64)->#null *void
    {
        var req: Swag.AllocatorRequest
        req.size = size
        @getcontext().allocator.alloc(&req)
        return req.address
    }

    func exampleFree(ptr: #null *void, size: u64)
    {
        var req: Swag.AllocatorRequest
        req.address = ptr
        req.size    = size
        @getcontext().allocator.free(&req)
    }

    let p = cast(*s32) notnull exampleAlloc(4)
    dref p = 1
    exampleFree(p, 4)

// let x = dref p       // Uncomment: error, use of a freed pointer (proven)
// exampleFree(p, 4)    // Uncomment: error, the pointer is freed twice (proven)
}

/**
# 'Use of Moved-From Values'

Reading a local abandoned by '#move' or '#relocate' (and not reset) is a proven
error at compile time ('.Lifecycle'). At runtime, the '.Lifecycle' **safety** half
additionally poisons abandoned storage with '0xDD' so the accesses the static check
cannot prove still fail deterministically.
*/
#test
{
    struct Item
    {
        x: s32
    }

    var a = Item{x: 1}
    var b = #move a
    @assert(b.x == 1)

    // @assert(a.x == 1)  // Uncomment: error, use of moved-from value
    a = Item{x: 2}
    @assert(a.x == 2)     // Reassigning makes it readable again
}

/**
# 'Opting Out'

Like safety, sanity can be disabled per scope with the attribute. Disabling
'.Lifecycle' turns the whole borrow analysis off for that function.
*/
#[Swag.Sanity(.Lifecycle, false), Swag.Sanity(.Memory, false)]
func sanityOptedOut()->*s32
{
    var v: s32
    return &v     // Accepted: the analysis is off here
}

/**
# 'The '#sanity' Intrinsic'

'#sanity(...)' evaluates, at compile time, whether a given static check is active
at this point — the build-config default combined with the 'Swag.Sanity' overrides
in scope. It mirrors '#safety(...)', which queries the runtime safety flags.
*/
#[Swag.Sanity(.Lifecycle, false)]
#test
{
    #assert(#sanity(Swag.SafetyWhat.Lifecycle) == false)
}
