#global private

/**
# Runtime Safety Checks

Swag provides safety checks that can be enabled at different granularity
levels — module, function, or even individual instruction — via
'#[Swag.Safety]'.

These checks prevent common programming errors by triggering panics during
unsafe operations (overflows, invalid math, out-of-bounds access, etc.).

You can also configure safety checks globally from the build configuration
with 'buildCfg.safetyGuards'.
*/

/**
> NOTE:
> Swag offers two predefined build configurations: 'devmode' and 'release'.
> Safety checks are enabled by default in 'devmode' and disabled in 'release'
> for performance.

> NOTE:
> Safety covers the RUNTIME guards. Their static, compile-time counterparts are
> controlled separately with '#[Swag.Sanity]' and stay enabled in 'release';
> see the dedicated 'Sanity Checks in Swag' section.
*/

/**
# Assertions

'Swag.assert(condition, message)' is the standard assertion for programmer invariants.
'SafetyWhat.Assert' follows the same defaults as other runtime safety guards: enabled
in 'devmode', disabled in 'release'. Set 'buildCfg.safetyGuards |= .Assert' to keep
assertions in a release module, or use a local 'Swag.Safety' override. The 'test'
command enables assertions by default in every configuration, including release.
Explicit local overrides still apply, and other runtime guards keep their configured
defaults. '#safety(Swag.SafetyWhat.Assert)' reports the effective setting in tests too.

When disabled, the assertion emits no code and evaluates none of its arguments.
Arguments still type-check. The invariant remains a precondition for subsequent
flow-narrowed code. Keep required side effects outside the assertion.
'#assert' is a separate compile-time check and is unaffected by this flag.
*/
#test
{
    #[Swag.Safety(.Assert, true)]
    {
        #assert(#safety(Swag.SafetyWhat.Assert))
        Swag.assert(10 > 0, "positive value")
    }

    #[Swag.Safety(.Assert, false)]
    {
        #assert(!#safety(Swag.SafetyWhat.Assert))
        Swag.assert(false)
    }
}

/**
# Overflow Safety
Example:
#[Swag.Safety(.Overflow, true)]
When enabled, Swag panics on arithmetic overflow, on a runtime negative shift
count, or when bits are lost during integer conversions.

Operators that can overflow include '+ - *' and compound forms '+= -= *='.
Shifts have defined truncating and large-count behavior; overflow safety only
guards their negative signed counts.
*/
#test
{
    var x = 255'u8

    // x += 1  // Uncomment to see overflow panic
}

/**
## Disabling Overflow Safety with '#wrap'

Use '#wrap' on the operation if overflow is expected and should not panic.
It is unnecessary for shifts, whose discarded bits already truncate normally.
*/
#test
{
    var x = 255'u8
    x += #wrap 1
    Swag.assert(x == 0)
}

/**
## Global Overflow Safety Control

Disable overflow safety checks in a scope with '#[Swag.Safety(.Overflow, false)]'.
*/
#[Swag.Safety(.Overflow, false)]
#test
{
    var x = 255'u8
    x += 1
    Swag.assert(x == 0)
}

/**
## Promoting Operations to Prevent Overflow

For 8/16-bit operations, use '#prom' to promote to 32-bit and avoid overflow.
*/
#test
{
    let x = 255'u8 + #prom 1
    Swag.assert(x == 256)
    Swag.assert(#typeof(x) == u32)
}

/**
# Information Loss During Casting

Swag checks casts for potential information loss between integer types.
*/
#test
{
    let x1 = 255'u8

    // var y0 = cast(s8) x1  // Would panic: 255 not representable as s8

    let y1 = cast #wrap (s8) x1
    Swag.assert(y1 == -1)

    let x2 = -1's8

    // var y2 = cast(u8) x2  // Would panic: negative to unsigned
    let y2 = cast #wrap (u8) x2
    Swag.assert(y2 == 255)
}

/**
## Disabling Overflow Safety Globally

Same as above: '#[Swag.Safety(.Overflow, false)]' allows overflowing operations.
*/
#[Swag.Safety(.Overflow, false)]
#test
{
    var x = 255'u8
    x += 255     // -> 254 (wrap)
    x += 1       // -> 255
    x >>= 1      // -> 127
    Swag.assert(x == 127)
}

/**
# Dynamic Cast Type Safety
Example:
#[Swag.Safety(.DynCast, true)]
Swag panics if a cast from 'any' to another type is invalid.
*/
#test
{
    let x: any = "1"
    let y      = cast(string) x

    // var z = cast(s32) x  // Would panic: underlying type mismatch
    // Swag.assert(z == 0)
}

/**
Swag also panics if casting from an interface to a pointer-to-struct
cannot be performed.
*/

/**
# Array Bounds Checking
Example:
#[Swag.Safety(.BoundCheck, true)]
Swag panics if an index is out of range when dereferencing sized values
(arrays, slices, strings).
*/
#test
{
    var x   = [0, 1, 2]
    var idx = 10

    // Swag.assert(x[idx] == 1)  // Would panic: out-of-bounds
}

/**
## Safety When Indexing a Slice

Indexing a slice is checked for bounds.
*/
#test
{
    let x: const [..] s32 = [0, 1, 2]
    var idx               = 1
    Swag.assert(x[idx] == 1)
    idx += 9

    // Swag.assert(x[idx] == 1)  // Would panic: out-of-bounds
}

/**
## Safety When Slicing a Sized Value

Slice operations are checked for bounds.
*/
#test
{
    var x: const [..] s32 = [0, 1, 2]

    // var slice = x[1 to 4]   // Would panic: out-of-bounds
    // Swag.assert(slice[0] == 1)
}

#test
{
    var x   = "string"
    var idx = 10

    // var slice = x[0 to idx] // Would panic: out-of-bounds
    // Swag.assert(slice[0] == 's')
}

/**
## Safety on Loop Ranges

A 'for' range asks a predicate rather than a length, and the loop lowering answers it before
the first iteration: an inverted range is EMPTY, not a fault, and runs zero times. That is why
no guard applies here. A range whose bounds are both constant is different — the inversion is
certain rather than merely possible — and it is rejected at compile time.

Slicing keeps its check, because 'x[a to b]' asks for a length: a range that runs off the end
of the sliced value panics under '.BoundCheck'.
*/
#test
{
    func sumRange(low, high: s32)->s32
    {
        var sum = 0
        for i in low until high do
            sum += i
        return sum
    }

    Swag.assert(sumRange(0, 0) == 0)
    Swag.assert(sumRange(2, 2) == 0)
    Swag.assert(sumRange(0, 4) == 0 + 1 + 2 + 3)

    // Swag.assert(sumRange(4, 2) == 0)  // Would panic: lower bound above upper bound
}

/**
# Math Safety
Example:
#[Swag.Safety(.Math, true)]
Swag panics on an INTEGER division or remainder by zero, and on an intrinsic argument outside
its domain.

A float division by zero is not covered, and needs no cover: it is defined by IEEE 754 and
yields an infinity rather than trapping. What can go wrong afterwards is a 'NaN', which
'.NaN' watches.

A divisor the compiler can fold to zero is rejected at compile time by the static half instead
('#[Swag.Sanity(.Math)]'), which is what covers a build with the dynamic guards off. The two
never both report: the guard lowers to a test of the divisor, and past that test the divisor is
no longer provably zero, so whichever layer is enabled is the one that speaks.
*/
#test
{
    var value   = 10's32
    var divisor = 2's32
    Swag.assert(value / divisor == 5)

    // divisor = 0
    // Swag.print(value / divisor)  // Would panic: division by zero
}

/**
## Checking Invalid Math Intrinsic Arguments

Swag validates arguments for several math intrinsics and panics if invalid.
*/
#test
{
    // Swag.abs(-128)        // Invalid for abs on this target
    // Swag.log(-2'f32)      // Invalid: log of negative
    // Swag.log2(-2'f32)     // Invalid: log2 of negative
    // Swag.log10(2'f64)     // Example: implementation-specific constraints
    // Swag.sqrt(-2'f32)     // Invalid: sqrt of negative
    // Swag.asin(-2'f32)     // Invalid: asin out of range
    // Swag.acos(2'f32)      // Invalid: acos out of range
}

/**
# Switch Safety
Example:
#[Swag.Safety(.Switch, true)]
The guard covers 'switch #complete' only. Such a switch has an arm for every
declared value of its enum, so the only value that can reach no case is one
outside that set — and that is what Swag panics on.

A plain 'switch' is not guarded: an unmatched value simply reaches no case and
execution continues after the switch, in every build configuration.
*/
#test
{
    enum Color
    {
        Red
        Green
        Blue
    }

    func colorRank(color: Color)->s32
    {
        // A plain switch: 'Blue' matches nothing and falls through to the return below.
        // 'switch #complete' here would reject the missing 'Blue' case at compile time.
        switch color
        {
        case .Red:   return 1
        case .Green: return 2
        }

        return -1
    }

    Swag.assert(colorRank(Color.Blue) == -1)
}

/**
# Boolean Safety
Example:
#[Swag.Safety(.Bool, true)]
Swag panics if a 'bool' is not 'true' (1) or 'false' (0).
*/
#test
{
    var b: u8 = 2

    // if b { }  // Would panic: invalid boolean value
}

/**
# NaN Safety
Example:
#[Swag.Safety(.NaN, true)]
Swag panics if a floating-point 'NaN' participates in an operation,
preventing propagation of invalid values.
*/

/**
# Stack Exhaustion

Swag uses the host thread's stack and does not promise a fixed recursion depth. Exhausting that
stack is a fatal execution fault, not a 'fail' value that 'catch' can handle. The available depth
depends on the host stack reservation and the size of the generated frames.

The Windows backend probes guard pages when reserving a large frame. During execution inside
the compiler, its fault reporter reserves stack space and reports 'EXCEPTION_STACK_OVERFLOW'.
For a native executable, fatal-fault reporting belongs to its host environment. Enabling or
disabling the safety guards does not turn stack exhaustion into a recoverable language error.
*/
