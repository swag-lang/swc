#global private

/**
Interfaces in Swag are virtual tables (lists of function pointers) that can be associated with a struct.

Unlike C++, the virtual table is not embedded in the struct; it is a separate object.
This lets you implement an interface for a struct without changing the struct.
*/

struct Point2
{
    x, y: f32
}

struct Point3
{
    x, y, z: f32
}

/**
# Interface Declaration
Declare interface 'IReset' with two functions 'set' and 'reset'.
*/

interface IReset
{
    // First parameter must be 'me' when using 'func'
    mtd set(val: f32)

    // 'mtd' avoids specifying 'me'
    mtd reset()
}

/**
# Implementing an Interface
Implement interface 'IReset' for 'Point2'.
*/
impl IReset for Point2
{
    // Mark with 'impl' to implement an interface function
    mtd impl set(val: f32)
    {
        me.x = val
        me.y = val + 1
    }

    mtd impl reset()
    {
        me.x, me.y = 0
    }

    // Regular methods may also appear in this 'impl'
    mtd myOtherMethod() {}
}

/**
# Implementing the Interface for Another Struct
Implement 'IReset' for 'Point3'.
*/
impl IReset for Point3
{
    mtd impl set(val: f32)
    {
        me.x = val
        me.y = val + 1
        me.z = val + 2
    }

    mtd impl reset()
    {
        me.x, me.y, me.z = 0
    }
}

/**
# Using the Interface
Cast to the interface and call its methods.
*/
#test
{
    var pt2: Point2
    var pt3: Point3
    var itf = cast(IReset) pt2
    itf.set(10)
    Swag.assert(pt2.x == 10)
    Swag.assert(pt2.y == 11)
    itf = cast(IReset) pt3
    itf.set(10)
    Swag.assert(pt3.x == 10)
    Swag.assert(pt3.y == 11)
    Swag.assert(pt3.z == 12)
    itf.reset()
    Swag.assert(pt3.x == 0 and pt3.y == 0 and pt3.z == 0)
}

/**
# Accessing Interface Methods Directly
An 'impl I for T' publishes its functions under a scope named 'I' inside 'T', so
'value.I.method()' calls that implementation directly, without building an
interface value and without going through the virtual table.

This is the only place where the right-hand side of a dot names a scope rather
than a member, and it is what a call to a base implementation is written with: a
composed type reaches the implementation it wraps as 'me.base.IWnd.onResize(evt)'.
Because the scope shares the struct's member namespace, an interface name and a
field name cannot collide on the same struct.
*/
#test
{
    var pt2: Point2
    var pt3: Point3
    pt2.IReset.set(10)
    pt2.IReset.reset()
    pt3.IReset.set(10)
    pt3.IReset.reset()
}

/**
# Interface as a Type
An interface occupies two pointers: object pointer + virtual table pointer.
*/
#test
{
    var pt2: Point2
    var pt3: Point3
    var itf = cast(IReset) pt2
    #assert(#sizeof(itf) == 2 * #sizeof(#null *void))

    // Retrieve the concrete type with 'Swag.kindOf'
    itf = cast(IReset) pt2
    Swag.assert(Swag.kindOf(itf) == Point2)
    itf = cast(IReset) pt3
    Swag.assert(Swag.kindOf(itf) == Point3)

    // Retrieve the concrete data with '.buffer'
    itf = cast(IReset) pt2
    Swag.assert(itf.buffer == &pt2)
    itf = cast(IReset) pt3
    Swag.assert(itf.buffer == &pt3)
}

/**
# Default Implementation in Interfaces
Provide default bodies directly in the interface. If a struct does not override,
the default is used.
*/
interface ITest
{
    mtd isImplemented()->bool
    {
        return false
    }
}

/**
Override on 'Point2'; no override on 'Point3'.
*/
impl ITest for Point2
{
    mtd impl isImplemented()->bool
    {
        return true
    }
}

impl ITest for Point3 {}

/**
For 'Point3', 'isImplemented()' returns 'false' (the default).
*/
#test
{
    var v2: Point2
    var v3: Point3

    let i2 = cast(ITest) v2
    Swag.assert(i2.isImplemented())

    let i3 = cast(ITest) v3
    Swag.assert(!i3.isImplemented())
}
