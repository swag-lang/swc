#global private

/**
# Custom Assignment Behavior with 'opSet'

The 'opSet' method in Swag allows you to define custom assignment behaviors
for your struct using the '=' operator. By overloading 'opSet', you can handle
assignments of different types and control how your struct responds.
*/

struct Struct
{
    x, y, z: s32 = 666     // Fields with default value 666
}

impl Struct
{
    // Overload for 's32'
    mtd opSet(value: s32)
    {
        me.x, me.y = value
    }

    // Overload for 'bool'
    mtd opSet(value: bool)
    {
        me.x, me.y = value ? 1 : 0
    }
}

#test
{
    let v: Struct = 4's32
    Swag.assert(v.x == 4)
    Swag.assert(v.y == 4)
    Swag.assert(v.z == 666)
    var v1: Struct = true
    Swag.assert(v1.x == 1)
    Swag.assert(v1.y == 1)
    v1 = false
    Swag.assert(v1.x == 0)
    Swag.assert(v1.y == 0)
}

/**
# Optimizing Initialization with 'Swag.FullInit'

When 'opSet' completely initializes the struct, mark it with '#[Swag.FullInit]'.
This avoids default initialization before assignment for better performance.
*/

impl Struct
{
    #[Swag.FullInit]
    mtd opSet(value: u64)
    {
        me.x, me.y, me.z = cast(s32) value
    }

    #[Swag.Implicit]
    mtd opSet(value: u16)
    {
        me.x, me.y = cast(s32) value
    }
}

#test
{
    let v: Struct = 2'u64
    Swag.assert(v.x == 2)
    Swag.assert(v.y == 2)
    Swag.assert(v.z == 2)
}

/**
# Handling Function Arguments and Automatic Conversion

Function arguments are not automatically converted through 'opSet' unless
'Swag.Implicit' is used. Otherwise, an explicit cast is required.
*/

#test
{
    func takesExplicit(v: Struct)
    {
        Swag.assert(v.x == 5)
        Swag.assert(v.y == 5)
        Swag.assert(v.z == 666)
    }

    func takesImplicit(v: Struct)
    {
        Swag.assert(v.x == 5)
        Swag.assert(v.y == 5)
        Swag.assert(v.z == 666)
    }

    // Explicit cast triggers 'opSet(s32)'
    takesExplicit(cast(Struct) 5's32)

    // Implicit conversion via 'opSet(u16)'
    takesImplicit(5'u16)
}

/**
# Using 'opSet' in Constant Expressions

To allow compile-time initialization through 'opSet', mark it with
'#[Swag.ConstExpr]'.
*/

struct Vector2
{
    x, y: f32
}

impl Vector2
{
    #[Swag.ConstExpr]
    mtd opSet(one: f32)
    {
        me.x, me.y = one
    }
}

const One: Vector2 = 1.0
#assert(One.x == 1.0)
#assert(One.y == 1.0)
