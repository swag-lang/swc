#global private

/**
# Constant-Evaluable Functions

'#[Swag.ConstExpr]' allows a function to participate in a constant expression.
When the call and everything it depends on are constant, 'swc' executes it
during compilation. A call with runtime arguments remains an ordinary runtime
call.

Use this attribute for deterministic computation that belongs in array sizes,
constants, static conditions, or generated declarations. Use '#run' when the
operation should execute only as a build-time action.
*/

#[Swag.ConstExpr]
func constexprSquare(value: s32)->s32
{
    return value * value
}

const ConstexprSquares = [
    constexprSquare(1),
    constexprSquare(2),
    constexprSquare(3),
    constexprSquare(4),]

#assert(ConstexprSquares[0] == 1)
#assert(ConstexprSquares[1] == 4)
#assert(ConstexprSquares[2] == 9)
#assert(ConstexprSquares[3] == 16)

#test
{
    var runtimeValue = 5
    @assert(constexprSquare(runtimeValue) == 25)
}

/**
# Branches, Loops, and Recursion

A constant-evaluable function uses ordinary Swag control flow. Recursive
definitions still need a valid base case and are subject to the compiler's
execution limits.
*/

#[Swag.ConstExpr]
func constexprFactorial(value: u32)->u32
{
    if value <= 1 do
        return 1
    return value * constexprFactorial(value - 1)
}

#[Swag.ConstExpr]
func constexprSum(values: const [..] s32)->s32
{
    var result = 0
    for value in values do
        result += value
    return result
}

#assert(constexprFactorial(5) == 120)
#assert(constexprSum([1, 2, 3, 4]) == 10)

/**
# Constant User-Defined Values

A struct can opt into constant evaluation when its lifecycle operations are
valid in that environment. ConstExpr functions may then construct and return
instances of that type.
*/

#[Swag.ConstExpr]
struct ConstexprPoint
{
    x, y: s32
}

#[Swag.ConstExpr]
func makeConstexprPoint(x, y: s32)->ConstexprPoint
{
    return {x, y}
}

const ConstexprOrigin = makeConstexprPoint(3, 7)
#assert(ConstexprOrigin.x == 3)
#assert(ConstexprOrigin.y == 7)

/**
# Static Conditions and Types

The result can drive '#static if' or any other context that requires a constant:
*/

#[Swag.ConstExpr]
func constexprIsPowerOfTwo(value: u32)->bool
{
    return value != 0 and (value & (value - 1)) == 0
}

#static if !constexprIsPowerOfTwo(64)
{
    #error("64 must be a power of two")
}

const TableSize = constexprFactorial(3)
var ConstexprSizedTable: [TableSize] u8
#assert(@countof(ConstexprSizedTable) == 6)

/**
# Failure Is a Compile-Time Diagnostic

If a constant context calls a 'ConstExpr' function with an operation the
compile-time engine cannot perform, the build fails at that call. The compiler
does not silently defer a required constant to runtime.

Do not mark a function 'ConstExpr' merely as an optimization hint. The
attribute is an API promise that callers may rely on in type-level and
declaration-level expressions.
*/
