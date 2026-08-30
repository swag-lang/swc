#global private

/**
# Static Sanity Checks

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
> Sanity checks are enabled by default in every build configuration. This differs
> from runtime safety, which is disabled in 'release' for performance: the static
> checks stay on in 'release' since they are free.
*/

/**
# Proven Runtime Faults

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
> NOTE:
> A view that borrows function-local storage — the address of a local, a slice of a
> local array, a 'string' of a local 'Core.String' — is governed by the **borrow rules**,
> which are part of the language rather than of this layer: no attribute and no build
> configuration turns them off. See the 'Borrowing' section.
*/
var sanityGlobalValue: s32

func sanityGlobalAddress()->*s32
{
    // var v: s32
    // return &v  // Uncomment: error, the view outlives 'v' (a language rule)
    return &sanityGlobalValue     // A global outlives the call
}

/**
# Use After Free and Double Free

Every allocation flows through the 'Swag.IAllocator' interface, whose methods make
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
        let allocItf = Swag.getContext().allocator!
        allocItf.alloc(&req)
        return req.address
    }

    func exampleFree(ptr: #null *void, size: u64)
    {
        var req: Swag.AllocatorRequest
        req.address = ptr
        req.size    = size
        let allocItf = Swag.getContext().allocator!
        allocItf.free(&req)
    }

    let p = cast(*s32) exampleAlloc(4)!
    p[] = 1
    exampleFree(p, 4)

// let x = p[]       // Uncomment: error, use of a freed pointer (proven)
// exampleFree(p, 4)    // Uncomment: error, the pointer is freed twice (proven)
}

/**
# Use of Moved-From Values

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
    Swag.assert(b.x == 1)

    // Swag.assert(a.x == 1)  // Uncomment: error, use of moved-from value
    a = Item{x: 2}
    Swag.assert(a.x == 2)     // Reassigning makes it readable again
}

/**
# Opting Out

Like safety, sanity can be disabled per scope with the attribute. Disabling
'.Lifecycle' turns off the analyses above that prove a lifetime fault — the
use-after-free, double-free and use-after-move proofs. It does **not** reach the
borrow rules: those are language rules and stay on.
*/
var sanityOptedOutValue: s32

#[Swag.Sanity(.Lifecycle, false), Swag.Sanity(.Memory, false)]
func sanityOptedOut()->*s32
{
    // A frame borrow would still be rejected here: what the attribute switches off is
    // the proof machinery, not the rule.
    return &sanityOptedOutValue
}

/**
# The '#sanity' Intrinsic

'#sanity(...)' evaluates, at compile time, whether a given static check is active
at this point — the build-config default combined with the 'Swag.Sanity' overrides
in scope. It mirrors '#safety(...)', which queries the runtime safety flags.
*/
#[Swag.Sanity(.Lifecycle, false)]
#test
{
    #assert(#sanity(Swag.SafetyWhat.Lifecycle) == false)
}
