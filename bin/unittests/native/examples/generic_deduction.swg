#global private

// Test: generic type argument deduction from enclosing context.
// When a generic struct is used bare (without explicit type arguments)
// inside an impl block for a generic struct, the compiler deduces
// the type arguments by matching parameter names.

// ---------------------------------------------------------------------------
// Basic generic structs
// ---------------------------------------------------------------------------

struct(T) Vec2
{
    x: T
    y: T
}

// Field types also benefit from deduction: Vec2 deduced as Vec2'T
struct(T) Rect
{
    min: Vec2
    max: Vec2
}

struct(T) Wrapper
{
    inner: T
}

struct(A, B) Duo
{
    first:  A
    second: B
}

// ---------------------------------------------------------------------------
// Self-type deduction: Rect inside impl Rect
// ---------------------------------------------------------------------------

impl Rect
{
    // Return type 'Rect' is deduced as Rect'T
    func center(const me)->Vec2
    {
        return {x: (me.min.x + me.max.x) / 2, y: (me.min.y + me.max.y) / 2}
    }

    // Parameter type 'Vec2' and return type 'Rect' deduced from context
    func translate(const me, offset: Vec2)->Rect
    {
        return {min: {x: me.min.x + offset.x, y: me.min.y + offset.y},
                max: {x: me.max.x + offset.x, y: me.max.y + offset.y}}
    }

    func scale(const me, factor: T)->Rect
    {
        return {min: {x: me.min.x * factor, y: me.min.y * factor},
                max: {x: me.max.x * factor, y: me.max.y * factor}}
    }
}

// ---------------------------------------------------------------------------
// Cross-struct deduction: Vec2 inside impl Vec2
// ---------------------------------------------------------------------------

impl Vec2
{
    func make(x: T, y: T)->Vec2
    {
        return {x: x, y: y}
    }

    // Return type 'Vec2' is deduced as Vec2'T (self-type)
    func add(const me, other: Vec2)->Vec2
    {
        return {x: me.x + other.x, y: me.y + other.y}
    }

    func negate(const me)->Vec2
    {
        return {x: -me.x, y: -me.y}
    }

    func doubled(const me)->Vec2
    {
        return Vec2.make(me.x + me.x, me.y + me.y)
    }
}

// ---------------------------------------------------------------------------
// Wrapper with deduction
// ---------------------------------------------------------------------------

impl Wrapper
{
    func get(const me)->T
    {
        return me.inner
    }
}

// ---------------------------------------------------------------------------
// Multi-param struct: Duo'(A,B) cannot be deduced from single-param context
// (Pair with matching params CAN be deduced)
// ---------------------------------------------------------------------------

struct(T) Container
{
    val: Vec2'T
}

impl Container
{
    // Vec2 is deduced as Vec2'T (T matches)
    func getVec(const me)->Vec2
    {
        return me.val
    }
}

// ===========================================================================
// Tests
// ===========================================================================

// Test: self-type deduction in Rect
#test
{
    let r: Rect's32 = {min: {x: 0, y: 0}, max: {x: 20, y: 10}}
    let c           = r.center()

    #assert(#typeof(c) == Vec2's32)
    Swag.assert(c.x == 10)
    Swag.assert(c.y == 5)
}

// Test: cross-struct param deduction (Vec2 in Rect's impl)
#test
{
    let r:      Rect's32 = {min: {x: 0, y: 0}, max: {x: 10, y: 10}}
    var offset: Vec2's32 = {x: 5, y: -3}
    let moved            = r.translate(&offset)

    #assert(#typeof(moved) == Rect's32)
    Swag.assert(moved.min.x == 5)
    Swag.assert(moved.min.y == -3)
    Swag.assert(moved.max.x == 15)
    Swag.assert(moved.max.y == 7)
}

// Test: scale with deduced return type
#test
{
    let r: Rect's32 = {min: {x: 1, y: 2}, max: {x: 3, y: 4}}
    let scaled      = r.scale(10)

    #assert(#typeof(scaled) == Rect's32)
    Swag.assert(scaled.min.x == 10)
    Swag.assert(scaled.min.y == 20)
    Swag.assert(scaled.max.x == 30)
    Swag.assert(scaled.max.y == 40)
}

// Test: self-type deduction in Vec2
#test
{
    var a: Vec2's32 = {x: 1, y: 2}
    var b: Vec2's32 = {x: 10, y: 20}
    let sum         = a.add(&b)

    #assert(#typeof(sum) == Vec2's32)
    Swag.assert(sum.x == 11)
    Swag.assert(sum.y == 22)
}

// Test: deduction with Vec2 negate
#test
{
    var v: Vec2's32 = {x: 3, y: -7}
    let neg         = v.negate()

    #assert(#typeof(neg) == Vec2's32)
    Swag.assert(neg.x == -3)
    Swag.assert(neg.y == 7)
}

// Test: member lookup on a bare generic root still uses the current specialization
#test
{
    var v: Vec2's32 = {x: 3, y: 4}
    let doubled     = v.doubled()

    #assert(#typeof(doubled) == Vec2's32)
    Swag.assert(doubled.x == 6)
    Swag.assert(doubled.y == 8)
}

// Test: deduction in Container (cross-struct matching T)
#test
{
    let c: Container's32 = {val: {x: 42, y: 99}}
    let v                = c.getVec()

    #assert(#typeof(v) == Vec2's32)
    Swag.assert(v.x == 42)
    Swag.assert(v.y == 99)
}

// Test: deduction with s64 type
#test
{
    let r: Rect's64 = {min: {x: 0, y: 0}, max: {x: 100000, y: 50000}}
    let c           = r.center()

    #assert(#typeof(c) == Vec2's64)
    Swag.assert(c.x == 50000)
    Swag.assert(c.y == 25000)
}

// Test: deduction with Wrapper
#test
{
    let w: Wrapper's32 = {inner: 42}
    let val            = w.get()

    #assert(#typeof(val) == s32)
    Swag.assert(val == 42)
}
