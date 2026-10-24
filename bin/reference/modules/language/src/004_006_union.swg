#global private

/**
# The `union` Type in Swag

A `union` is a special kind of struct where all fields share the same memory location.
Each field starts at offset `0`, allowing multiple variables to overlap in memory.

This makes it possible to represent different data types using the same storage space,
which is particularly useful for optimizing memory when only one field is used at a time.
*/

#test
{
    // Define a union with three overlapping f32 fields: x, y, and z
    union MyUnion
    {
        x, y, z: f32
    }

    // Initialize the union, setting the value of the 'x' field
    let v = MyUnion{x: 666}

    // All fields share the same memory location — updating one affects all
    Swag.assert(v.y == 666)
    Swag.assert(v.z == 666)
}

/**
# How Unions Work

In this example, the `MyUnion` type defines three fields (`x`, `y`, and `z`) that occupy the same
memory space. Writing to one field overwrites the others, since they are all stored at the same offset.

This design is ideal for cases where different data types (or values) are stored alternately in the
same memory area. Here, since all fields are of type `f32`, assigning a value to `x` automatically
updates `y` and `z`, demonstrating the shared-memory behavior of unions.
*/

/**
# Tagged Unions

A plain union does not know which member was written last. A **tagged union** does: write an
enum type in parentheses after `union`, and label every member with the tag values that select
it, using the grammar of a `switch` arm.

The union stores its tag first and its members after it. The tag is not a field: it changes only
when a whole case is written, so a member and the tag that selects it can never disagree. Tag
values that no `case` lists carry no member at all.
*/

#test
{
    enum Kind { None, Circle, Rect, Square }

    struct Shape
    {
        using geometry: union(Kind)
        {
            case .Circle:        circle: struct{ radius: f32 }
            case .Rect, .Square: rect:   struct{ w, h: f32 }
        } = .None
    }

    var shape: Shape
    Swag.assert(shape.geometry is .None)

    // A case is written with a leading dot, and its member with braces.
    shape.geometry = .Circle{radius: 2}
    Swag.assert(shape.geometry is .Circle)
    Swag.assert(shape.circle.radius == 2)

    shape.geometry = .Square{w: 3, h: 3}
    Swag.assert(Swag.kindOf(shape.geometry) == .Square)
}

/**
# Building a Case

A position that expects a tagged union lends its tag to a leading dot. `.Circle{radius: 2}`
builds the member of that case from the braces, then writes the tag and the member together.
Braces holding a single value of the member's own type hold that value as it is, and a member
that is not a struct takes its one value the same way. A case named without braces takes the
default its member declares, or its type's default.

A tagged union has no default case of its own: a value of it must be built from a case. The
declaration that holds it can give it one, as `= .None` does above.
*/

#test
{
    enum Mode { Text, Signed, Unsigned }

    struct Bounds
    {
        using mode: union(Mode)
        {
            case .Signed:   signed:   {min, max: s64} = {-10, 10}
            case .Unsigned: unsigned: {min, max: u64} = {0, 100}
        } = .Text
    }

    var bounds: Bounds
    bounds.mode = .Signed
    Swag.assert(bounds.signed.min == -10)

    bounds.mode = .Unsigned{max: 50}
    Swag.assert(bounds.unsigned.max == 50)
}

/**
A tagged union can also be declared with a name, the tag type following it. It is then a type
like any other, which a function takes, returns or stores.
*/

#test
{
    enum ValueKind { None, Number, Point }
    struct Point { x, y: s32 }

    union Value(ValueKind)
    {
        case .Number:
        number: s32
        case .Point:
        point: Point
    }

    func makePoint(x, y: s32)->Value => .Point{x: x, y: y}

    let p     = Point{x: 1, y: 2}
    var value = makePoint(3, 4)
    Swag.assert(value is .Point)

    value = .Point{p}
    Swag.assert(value.point.y == 2)

    value = .Number{7}
    Swag.assert(value.number == 7)
}

/**
# Reading the Case

`switch` on a tagged union selects on its tag, and `u is .Circle` tests one case.
`Swag.kindOf(u)` returns the tag itself, as a value of the enum.

A member is read or written only where the flow proves that its case is the active one: inside
the matching `case`, after an `is` test, after `Swag.assert(u is .Circle)`, or right after the
assignment that wrote the case. Any other access is rejected. A proof lasts until the union is
assigned again.
*/

#test
{
    enum Kind { None, Circle, Rect }

    struct Shape
    {
        using geometry: union(Kind)
        {
            case .Circle: circle: struct{ radius: f32 }
            case .Rect:   rect:   struct{ w, h: f32 }
        } = .None
    }

    func area(shape: Shape)->f32
    {
        switch shape.geometry
        {
        case .Circle: return 3 * shape.circle.radius * shape.circle.radius
        case .Rect:   return shape.rect.w * shape.rect.h
        default:      return 0
        }
    }

    var shape: Shape
    shape.geometry = .Rect{w: 2, h: 5}
    Swag.assert(area(shape) == 10)

    if shape.geometry is .Rect do
        shape.rect.w = 4
    Swag.assert(area(shape) == 20)
}

/**
# Asserting a Case with `!`

When the proof lives elsewhere, the postfix `!` asserts the case at the access. A safety check
panics at runtime when another case is active. A `!` on an access that is already proven is
rejected, as it is on a value already proven non-null.
*/

#test
{
    enum Kind { None, Rect }

    struct Shape
    {
        using geometry: union(Kind)
        {
            case .Rect: rect: struct{ w, h: f32 }
        } = .None
    }

    func width(shape: Shape)->f32 => shape.rect!.w

    var shape: Shape
    shape.geometry = .Rect{w: 4, h: 1}
    Swag.assert(width(shape) == 4)
}

/**
# Copy, Move, Drop and Equality

A tagged union copies, moves and drops only its active member. Two values are equal when they
hold the same case and their active members are equal; the storage of the other members takes
no part in the comparison.
*/

#test
{
    enum Kind { None, Name, Size }

    struct Label
    {
        using text: union(Kind)
        {
            case .Name: name: string
            case .Size: size: s32
        } = .None
    }

    var a, b: Label
    a.text = .Name{"disc"}
    b.text = .Name{"disc"}
    Swag.assert(a == b)

    b.text = .Size{4}
    Swag.assert(a != b)
}
