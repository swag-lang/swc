#global private

/**
# Values and Mutability

'const' declares a compile-time value, 'let' binds a runtime value once, and
'var' declares mutable storage. Types are inferred when the initializer is
unambiguous and can be written explicitly when they are part of the contract.
*/
#test
{
    const MaxRetries = 3
    let serviceName = "search"
    var attempts: u32

    attempts += 1

    #assert(#typeof(MaxRetries) == s32)
    #assert(#typeof(serviceName) == string)
    Swag.assert(attempts == 1)
}

/**
# Data with Behavior

A 'struct' groups fields. An 'impl' block adds methods without changing the
stored layout. In a method, 'me' is the receiver and '.field' is shorthand for
'me.field'.
*/
struct TourPoint
{
    x, y: s32
}

impl TourPoint
{
    mtd translate(dx, dy: s32)
    {
        .x += dx
        .y += dy
    }

    mtd const squaredLength() => .x * .x + .y * .y
}

#test
{
    var point = TourPoint{3, 4}
    Swag.assert(point.squaredLength() == 25)

    point.translate(1, -2)
    Swag.assert(point.x == 4 and point.y == 2)
}

/**
# Collections and Iteration

Arrays own a fixed number of elements. Slices are non-owning views. The same
'for value in collection' form visits both. Add a second ordinary binding when
the logical index is needed: 'for value, index in collection'.
*/
#test
{
    let values = [2, 4, 6, 8]
    let middle = values[1 until 3]
    var total  = 0

    for value, index in middle
    {
        Swag.assert(value == values[index + 1])
        total += value
    }

    Swag.assert(total == 10)
}

/**
# Branching

'if' handles boolean conditions. 'switch' is the natural choice when one value
selects among several cases. Blocks may use braces, or 'do' for a single
statement.
*/
enum TourState
{
    Idle
    Running
    Failed
}

func tourStateLabel(state: TourState)->string
{
    switch state
    {
    case .Idle:    return "idle"
    case .Running: return "running"
    case .Failed:  return "failed"
    }

    unreachable
}

#test
{
    let state = TourState.Running

    if state == .Running do
        Swag.assert(tourStateLabel(state) == "running")
    else do
        unreachable
}

/**
# Functions and Generic Code

Functions declare parameter and result types around '->'. A generic parameter
appears after 'func'; call-site inference normally supplies it.
*/
func(T) tourClamp(value, lower, upper: T)->T
{
    if value < lower do
        return lower
    if value > upper do
        return upper
    return value
}

#test
{
    Swag.assert(tourClamp(12, 0, 10) == 10)
    Swag.assert(tourClamp(0.25'f32, 0.0, 1.0) == 0.25)
}

/**
# Recoverable Errors

A function marked 'fail' may return an error instead of its normal result.
'try' propagates that error, while 'catch' handles it locally; capture it
with 'as err' to inspect it.
*/
func tourDivide(numerator, denominator: s32)->s32 fail
{
    if denominator == 0 do
        fail Swag.BaseError{"division by zero"}
    return numerator / denominator
}

#test
{
    Swag.assert(try tourDivide(12, 3) == 4)

    let fallback = catch tourDivide(12, 0) as err
    Swag.assert(fallback == 0)
    Swag.assert(err != null)
}

/**
# Compile-Time Programming

Swag uses the same language during compilation. '#run' evaluates an expression
at compile time; '#assert' then verifies the resulting constant before code
generation starts.
*/
func tourBuildMask(bits: u32)->u32
{
    return (1'u32 << bits) - 1
}

const TourLowByteMask = #run tourBuildMask(8)
#assert(TourLowByteMask == 0xFF)

/**
The rest of this reference expands each idea, including memory and nullability,
custom operators, interfaces, compile-time reflection, safety checks, and code
generation.
*/
