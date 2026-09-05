#global private

/**
# Generic 'where' Constraints
The `where` clause constrains generic functions and generic structs. It is
evaluated at compile time from generic parameters and other constant data.

For functions, a failing `where` removes that specialization from overload
resolution. For generic structs, a failing `where` prevents the instantiation
entirely because structs do not participate in overload selection.
*/

/**
# Function Specialization
Different overloads can share the same generic signature and still be selected
by different `where` clauses.
*/

#test
{
    func(T) classify(value: T)->u8
        where T == s32 or T == s64
    {
        return 1
    }

    func(T) classify(value: T)->u8
        where T == f32 or T == f64
    {
        return 2
    }

    Swag.assert(classify(1's32) == 1)
    Swag.assert(classify(1.5'f32) == 2)
}

/**
# Interface Requirements
The preferred declaration-site form for an interface requirement is
`where T is IValue`. With a type on the left and an interface on the right,
`is` evaluates to a compile-time `bool`: a struct satisfies the contract if
it implements that interface, directly or through a `using` field. An
interface satisfies its own contract. Other types answer `false`.

The bound participates in overload selection just like other `where` clauses.
Combine requirements with `and`, or write one `where` per interface.

Borrow the concrete argument through the required interface to call its
operations. The body is checked for each concrete specialization; the
bound does not make the generic parameter an interface type or check
the body independently of instantiation.

A type that does not implement `IValue` is rejected at the call. The
diagnostic names the function, its generic arguments, and the failed
`where T is IValue` declaration.
With a value on the left, `is` retains its dynamic type-test behavior.
For exact type equality, use `T == U`.
*/

interface IValue
{
    mtd value()->s32
}

struct ConstantValue {}

impl IValue for ConstantValue
{
    mtd value()->s32 => 42
}

func(T) readValue(value: *T)->s32
    where T is IValue
{
    let view = value as IValue
    return view.value()
}

#test
{
    var value: ConstantValue
    Swag.assert(readValue(&value) == 42)
    Swag.assert(readValue'ConstantValue(&value) == 42)
}

/**
# Block-based Constraints
`where` can also be a block returning a compile-time `bool`. This is useful
when the constraint is clearer as ordinary control flow.
*/

#test
{
    func(T, U = T) sameTypePair(left: T, right: U)->U
        where
        {
            if T == U do
                return true
            return false
        }
    {
        return right
    }

    Swag.assert(sameTypePair(10's32, 20's32) == 20)
    Swag.assert(sameTypePair'(f64)(1.0'f64, 2.0'f64) == 2.0'f64)
}

/**
# Generic Struct Constraints
Generic structs can also be constrained. The condition is checked as soon as
the compiler tries to instantiate the type.
*/

#test
{
    struct(T = f64) FloatPoint
        where T == f32 or T == f64
    {
        x, y: T
    }

    struct(T, Rows: s32, Cols: s32 = Rows) SquareMatrix
        where Rows > 0
        where Cols > 0
        where Rows == Cols
        where T == f32 or T == f64
    {
        data: [Rows * Cols] T
    }

    let point:  FloatPoint'f64        = {x: 1.5, y: 2.5}
    let matrix: SquareMatrix'(f32, 2) = {data: [1.0'f32, 2.0, 3.0, 4.0]}

    #assert(#typeof(point.x) == f64)
    #assert(#typeof(matrix.data) == #type [4] f32)
}

/**
# Generic Methods with Inherited Arguments
Method constraints can use a method's own generic parameters together with the
generic arguments inherited from the surrounding generic struct instance.
*/

struct(T, Count: s32) RefWindow
{
    values: [Count] T
}

impl RefWindow
{
    func(const Index: s32) at(const me)->T
        where Index >= 0
        where Index < Count
    {
        return me.values[Index]
    }

    func(U = T) sameSample(const me, other: U)->U
        where Count > 0
        where T == U
    {
        return other
    }
}

#test
{
    let floatWindow: RefWindow'(f32, 3) = {values: [10.0'f32, 20.0, 30.0]}

    Swag.assert(floatWindow.at'1() == 20.0'f32)
    Swag.assert(floatWindow.sameSample(99.0'f32) == 99.0'f32)
    #assert(#typeof(floatWindow.sameSample(1.5'f32)) == f32)
}
