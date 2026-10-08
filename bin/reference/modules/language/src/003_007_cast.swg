#global private

/**
# Explicit Cast with 'cast'

Explicit casting converts a value from one type to another using the syntax
'cast(type, value)'. This transformation changes the type of 'value' to the
specified 'type'.
*/
#test
{
    let x = 1.0     // Defaults to 'f32'
    #assert(#typeof(x) == f32)

    let y = cast(s32, x)     // Explicit cast to 's32'
    #assert(#typeof(y) == s32)
    Swag.assert(y == 1)
}

/**
# Interface Conversion
`cast(IFoo, value)` produces an 'IFoo' interface value when the source type
implements that interface. The compiler establishes this conversion statically.
Pass a pointer when borrowing an existing object. A type alias for an interface
works as the target too.
*/

interface ICount
{
    mtd count()->s32
}

struct Counter { value: s32 }

impl ICount for Counter
{
    mtd count()->s32 => .value
}

#test
{
    var counter = Counter{42}
    let view    = cast(ICount, &counter)
    Swag.assert(view.count() == 42)
    #assert(#typeof(view) == ICount)
}

/**
# Dynamic Casts

The conversion stays `cast(Type, value)`. Its prefix states how to handle a
validity condition that the compiler cannot establish statically:

- `try cast(*T, value)` checks compatibility and propagates a conversion error.
- `expect cast(*T, value)` checks compatibility and panics on failure in every build configuration.
- `assume cast(*T, value)` asserts an invariant established by the caller. The '.Assume'
  safety flag checks the assertion; disabling that safety removes the check.

An ordinary dynamic cast needs one of these policies, or a surrounding `catch`.
A numeric conversion or a statically known conversion to an embedded parent does
not gain a dynamic type lookup. An assumed downcast along a known by-value `using`
path needs only its fixed address adjustment when '.Assume' safety is disabled.
Other representations can still require work to locate their borrowed view.

The destination also states the presence contract. `*T` requires a present value;
`*T?` accepts null. There is no separate trailing `!` to add to the operand.
When only nullability changes, the checked conversion tests presence without a
dynamic type lookup. An assumed presence conversion follows `.Assume` safety.

Use `catch cast(*T?, value)` when a nullable result is useful after a failed
conversion. `catch ... as error` also preserves its error. Like other caught
expressions, the destination needs an implicit default value.

These forms apply to `any`, interfaces, and pointers to dynamic structs. A plain
struct pointer can expose a concrete enclosing type only when its struct is marked
`#[Swag.DynCast]`, or inherits that capability through a by-value `using` field.
The attribute adds a compiler-managed metadata pointer to object storage; pointers
to the object retain their ordinary size. A pointer-valued `using` field does not
make its pointee part of the enclosing object's storage.

Use `value is T` for a boolean compatibility test, or `if value is T as name`
to test and borrow the matching value without constructing a conversion error.
Expression `as` is not a conversion operator; it introduces a binding in a type
pattern or a caught error.
*/

#[Swag.DynCast]
struct CastNode { id: s32 }

struct CastButton
{
    using node: CastNode
    label:      string = "Apply"
}

#test
{
    var button: CastButton
    let node:   *CastNode = &button
    let found = (catch cast(*CastButton?, node))
    if found != null do
        Swag.assert(found.label == "Apply")
    Swag.assert(found != null)
    Swag.assert(assume cast(*CastButton, node) == &button)
    Swag.assert(expect cast(*CastButton, node) == &button)
}

/**
## Testing and Using the Same Result

A type pattern tests compatibility and gives the branch a non-null borrowed view.
`if value is T as name` borrows a `*T`, or an interface view when `T` is an interface.
Constness follows the source. The source is evaluated once; the name belongs only
to the successful branch and its optional `where` guard. A false guard continues
to `elif` or `else`. No pattern copies the object or extends its lifetime.

Prefer `is` when the purpose is selecting a branch by type. Use a checked cast
when failure belongs to the operation's error contract, and `assume cast` when
the caller already guarantees compatibility.
*/
#test
{
    var counter = Counter{42}
    let view    = cast(ICount, &counter)
    if view is Counter as found do
        Swag.assert(found.value == 42)

    switch view
    {
    case Counter as found where found.value > 0: Swag.assert(found == &counter)
    default: Swag.assert(false)
    }
}

/**
## Values Stored in `any`

`try cast(*T, boxed)` borrows a stored value of type `T`. Dereference the result
to read or update that value. A stored pointer can also expose the object it
points to. A mismatching type raises a conversion error in either case.

`assume cast(T, boxed)` extracts a value when its type is an invariant. For a
pointer or interface destination, it produces the corresponding borrowed view.
Neither mode extends the lifetime of the boxed value or its pointee.
*/
#test
{
    var boxed: any = 42's32
    if boxed is s32 as value do
        Swag.assert(value[] == 42)
    Swag.assert(not (boxed is s64))
    Swag.assert(assume cast (s32, boxed) == 42)
}

/**
## Compile-Time Compatibility

`Source is Target` tests whether `Source` exposes a view of type `Target` and
returns a boolean. This relation also works in generic `where` constraints.
Exact type equality remains `Source == Target`.

Write `where Source is Target` for a generic compatibility constraint.
The same relation applies when the source is a `typeinfo` value evaluated at runtime.
Numeric widening does not establish type compatibility: `s32` and `s64` are
different dynamic types. Non-strict aliases are transparent; strict aliases and
enumerations retain their identity.
*/
#assert(Counter is ICount)
#assert(not (s32 is ICount))
#assert(not (s32 is s64))

func supportsCounterType(source: typeinfo)->bool
{
    return source is ICount
}

/**
## Targets Chosen at Runtime

Both `value is target` and explicit dynamic casts accept a 'typeinfo' target,
including a function result. With a type-information operand, a successful cast
returns the source descriptor. With a value operand, it borrows a value of the
requested type and returns an 'any'. The target must be a descriptor emitted
by the compiler; constructing or copying a descriptor does not create a type.

The value result borrows its source and can also refer to an interface view in
the current function. It does not allocate and must not escape that function.
`assume cast` checks compatibility when the `Swag.SafetyWhat.Assume` safety is
enabled, like every other `assume`. `try` and `expect` keep their checks even when
that safety is disabled.
*/
func supportsRuntimeType(target, source: typeinfo)->bool
{
    return source is target
}

#test
{
    Swag.assert(supportsRuntimeType(ICount, Counter))
    Swag.assert(not supportsRuntimeType(ICount, s32))
    Swag.assert(supportsCounterType(Counter))
    Swag.assert(not supportsCounterType(s32))

    var value = 42's32
    let target: typeinfo = s32
    let view  = expect cast(target, &value)
    if view is s32 as number do
        Swag.assert(number[] == 42)
    Swag.assert(view != null)
}

/**
# Contextual Cast with 'cast(value)'

A 'cast(value)' without an explicit type performs a **contextual cast**, allowing the compiler
to infer the target type based on the left-hand side of the assignment.
*/
#test
{
    let x: f32 = 1.0
    let y: s32 = cast(x)
    #assert(#typeof(y) == s32)
    Swag.assert(y == 1)
}

/**
Automatic casts can also be applied when passing function arguments.
*/
func testAutoCast(x: s32)
{
    Swag.assert(x == 1)
}

#test
{
    testAutoCast(cast(1.4))     // Automatically cast to 's32'
}

/**
A structure field or a typed array element also supplies a destination. Named and
positional fields follow the same rule; the cast remains explicit even though its
destination is inferred.
*/
struct CastCount { value: u16 }

#test
{
    var count:  u64     = 42
    let field           = CastCount{value: cast(count)}
    let values: [2] u16 = [cast(count), cast(count)]
    Swag.assert(field.value == 42)
    Swag.assert(values == [42'u16, 42'u16])
}

/**
# Bit Cast

The '#bit' cast mode performs a **bit-level reinterpretation** of a value’s
type without altering its underlying bit pattern. Source and destination types
must have the same size.
*/
#test
{
    let x: f32 = 1.0
    let y: u32 = cast #bit (u32, x)
    Swag.assert(y == 0x3F800000)     // 1.0 in IEEE 754 format

    #assert(cast #bit (u32, 1.0) == 0x3F800000)
    #assert(cast #bit (f32, 0x3F800000) == 1.0)
}

/**
Bitcasting also allows reinterpreting an integer’s bit pattern as a floating-point
value, or vice versa.
*/
#test
{
    let rawBits: u32 = 0x40490FDB
    let pi:      f32 = cast #bit (f32, rawBits)
    Swag.assert(pi == 3.1415927)

    let backToBits: u32 = cast #bit (u32, pi)
    Swag.assert(backToBits == 0x40490FDB)
}

/**
# Implicit Casts

Swag supports **implicit casts**, automatically converting between compatible
types when no data loss or precision loss can occur. These conversions happen
without requiring an explicit 'cast' statement.
*/

/**
## Implicit Cast Rules

1. **Widening conversions** — Allowed when converting from smaller to larger
   types, such as 's8' → 's16' or 'f32' → 'f64'.
2. **Sign preservation** — Implicit signed/unsigned conversions occur only if
   the value fits in the destination type.
3. **No narrowing conversions** — Conversions that could lose precision or range
   require an explicit cast.
*/
#test
{
    let x: s16 = 1's8
    let y: s32 = 1's16
    let z: s64 = 1's32
    Swag.assert(x == 1 and y == 1 and z == 1)

    let a: u16 = 255'u8
    let b: u32 = 65535'u16
    let c: u64 = 4294967295'u32
    Swag.assert(a == 255 and b == 65535 and c == 4294967295)

    let d: f64 = 1.23'f32
    Swag.assert(d > 1.22 and d < 1.24)
}

/**
# Disallowed Implicit Casts

Swag forbids implicit casts that may lose data or precision. In such cases, an
explicit cast is required. The '#wrap' cast mode can be used to
acknowledge potential data loss.
*/
#test
{
    // Explicit cast from 's16' to 's8' required
    let z0: s16 = 256
    let z1: s8  = cast #wrap (s8, z0)
    Swag.assert(z1 == 0)

    // Explicit cast from 'u16' to 's16' required
    let u_val: u16 = 65535
    let s_val: s16 = cast #wrap (s16, u_val)
    Swag.assert(s_val == -1)

    // Explicit cast from 'f64' to 'f32' required
    let large_float:   f64 = 1.23456789012345611111
    let smaller_float: f32 = cast(f32, large_float)
    Swag.assert(smaller_float > 1.23 and smaller_float < 1.24)
}

/**
# Casting Between Pointers and Integers

An address is an integer, so one explicit cast crosses in either direction. Towards a
pointer, any integer type that fits in an address is accepted, and a narrower one is
zero-extended; an enum crosses through its underlying type. Towards an integer, the
destination has to be able to hold an address: 'u64' and 's64' do, and a narrower type
is refused rather than silently losing the high half of the address.

Naming the destination is part of it. A 'cast(value)' takes its destination from the context,
and only 'u64' reaches a pointer that way: an integer that could bind any pointer
parameter would let overload resolution pick a call nobody wrote.
*/
enum CastPointerTag: u64
{
    First  = 7
    Second = 9
}

#test
{
    var storage: [16] u8
    let base = storage.buffer

    let address = cast(u64, base)
    Swag.assert(cast([*] u8, address) == base)
    Swag.assert(cast(s64, base) == cast(s64, address))

    // A narrower integer needs no second step towards a pointer.
    Swag.assert(cast(*void, 0xBEEF'u16) == cast(*void, 0xBEEF'u64))
    Swag.assert(cast(*void, CastPointerTag.First) == cast(*void, 7'u64))
    Swag.assert(cast(CastPointerTag, cast(*void, 9'u64)) == CastPointerTag.Second)

    // 'cast(u32, base)' is refused. Widen the address first, then narrow that value with
    // '#wrap' to say that dropping its high half is intended.
    Swag.assert(cast #wrap (u32, address) == cast #wrap (u32, cast(u64, base)))

    // A deduced destination reaches a pointer from 'u64' only.
    let deduced: [*] u8 = cast(address)
    Swag.assert(deduced == base)
}
