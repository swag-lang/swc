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
dereferencing or calling a pointer proven to be null ('.Null').
*/
#test
{
    var d = 0
    var a = 10
    // var x = a / d  // Uncomment: error, division by zero (proven)
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
    return &sanityGlobalValue // A global outlives the call
}

/**
# 'Borrow Escapes'

Views that borrow function-local storage — pointers, slices, strings, 'any',
interfaces, closures capturing by address — must not outlive that storage
('.Lifecycle'). Returning them, storing them into a global, or writing them through
a caller-visible pointer is a compile-time error.
*/
var sanityGlobalBuffer: [4] u8

#test
{
    func makeView()->const [..] u8
    {
        // var buf: [4] u8
        // return cast(const [..] u8) buf  // Uncomment: error, borrow escapes
        return cast(const [..] u8) sanityGlobalBuffer // A global's storage is fine
    }

    @assert(@countof(makeView()) == 4)
}

/**
The analysis follows borrows across local bindings, control-flow joins, and even
opaque calls: a function whose return value may borrow one of its parameters is
summarized, and the call site is checked against what was really passed in.
*/
#test
{
    func passthrough(p: *s32)->*s32
    {
        return p
    }

    func caller()->*s32
    {
        // var v: s32
        // return passthrough(&v)  // Uncomment: error, borrows a local through the call
        return passthrough(&sanityGlobalValue) // Caller-owned data flows through
    }

    @assert(caller() == &sanityGlobalValue)
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
    struct Item { x: s32 }

    var a = Item{x: 1}
    var b = #move a
    @assert(b.x == 1)
    // @assert(a.x == 1)  // Uncomment: error, use of moved-from value
    a = Item{x: 2}
    @assert(a.x == 2) // Reassigning makes it readable again
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
    return &v // Accepted: the analysis is off here
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
