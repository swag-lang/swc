#global private

enum ShapeKind
{
    Empty
    Circle
    Rect
    Square
}

struct Shape
{
    using geometry: union(ShapeKind)
    {
        case .Circle:        circle: struct{ radius: f32 }
        case .Rect, .Square: rect:   struct{ w, h: f32 }
    } = .Empty
}

func area(shape: Shape)->f32
{
    switch shape.geometry
    {
    case .Circle:
        return 3 * shape.circle.radius * shape.circle.radius
    case .Rect, .Square:
        return shape.rect.w * shape.rect.h
    default:
        return 0
    }
}

func width(shape: Shape)->f32 => shape.rect!.w

#test
{
    var shape: Shape
    Swag.assert(Swag.kindOf(shape.geometry) == .Empty)
    Swag.assert(area(shape) == 0)

    shape.geometry = .Circle{radius: 2}
    Swag.assert(shape.geometry is .Circle)
    Swag.assert(area(shape) == 12)

    shape.geometry = .Square{w: 3, h: 3}
    Swag.assert(Swag.kindOf(shape.geometry) == .Square)
    Swag.assert(area(shape) == 9)
    Swag.assert(width(shape) == 3)
}

// An assignment proves the case it writes, and a test proves the case it checks.
#test
{
    var shape: Shape
    shape.geometry = .Rect{w: 2, h: 5}
    shape.rect.w   += 1
    Swag.assert(shape.rect.w * shape.rect.h == 15)

    if shape.geometry is .Rect
    {
        shape.rect.h = 1
        Swag.assert(area(shape) == 3)
    }

    if not (shape.geometry is .Circle) do
        return
    Swag.assert(false)
}

// Two holders compare equal when they hold the same case and equal payloads.
#test
{
    var a, b: Shape
    a.geometry = .Circle{radius: 1}
    b.geometry = .Circle{radius: 1}
    Swag.assert(a == b)
    b.geometry = .Circle{radius: 2}
    Swag.assert(a != b)
    b.geometry = .Rect{w: 1, h: 0}
    Swag.assert(a != b)
}

// A payload compared by content gets a generated case-wise equality.
struct Label
{
    using text: union(ShapeKind)
    {
        case .Circle: name: string
        case .Rect:   size: s32
    } = .Empty
}

#test
{
    var a, b: Label
    a.text = .Circle{"disc"}
    b.text = .Circle{"disc"}
    Swag.assert(a == b)
    b.text = .Rect{4}
    Swag.assert(a != b)
    a.text = .Rect{4}
    Swag.assert(a == b)
}

var taggedDropCount = 0's32

struct Counted
{
    id: s32
}

impl Counted
{
    mtd opDrop()
    {
        taggedDropCount += 1
    }
}

struct Holder
{
    using item: union(ShapeKind)
    {
        case .Circle: counted: Counted
        case .Rect:   plain:   s32
    } = .Empty
}

// Only the active member is dropped, once, when the case changes and when the holder dies.
#test
{
    taggedDropCount = 0
    {
        var holder: Holder
        holder.item = .Circle{id: 5}
        Swag.assert(holder.counted.id == 5)
        holder.item = .Rect{3}
        Swag.assert(taggedDropCount == 1)
        holder.item = .Circle{id: 6}
    }

    Swag.assert(taggedDropCount == 2)
}

// A switch on 'Swag.kindOf' proves the case too, here through a pointer receiver.
impl Holder
{
    mtd value()->s32
    {
        switch Swag.kindOf(me.item)
        {
        case .Circle:
            return .counted.id
        case .Rect:
            return .plain
        default:
            return -1
        }
    }
}

#test
{
    var holder: Holder
    Swag.assert(holder.value() == -1)
    holder.item = .Rect{7}
    Swag.assert(holder.value() == 7)
}

// A member default applies when the case is named without braces.
struct Bounds
{
    using mode: union(ShapeKind)
    {
        case .Circle: signed:   {min, max: s64} = {-10, 10}
        case .Rect:   unsigned: {min, max: u64} = {0, 100}
    } = .Rect
}

#test
{
    var bounds: Bounds
    Swag.assert(bounds.mode is .Rect)
    Swag.assert(bounds.unsigned.max == 100)

    bounds.mode = .Circle
    Swag.assert(bounds.signed.min == -10)
    Swag.assert(#sizeof(Bounds) == 24)
}

// A named tagged union is a type of its own: it can be passed, returned and stored.
enum ValueKind
{
    None
    Number
    Point
}

struct ValuePoint
{
    x, y: s32
}

union Value(ValueKind)
{
    case .Number: number: s32
    case .Point:  point:  ValuePoint
}

func makePoint(x, y: s32)->Value
{
    return .Point{x: x, y: y}
}

func sum(value: Value)->s32
{
    switch value
    {
    case .Number:
        return value.number
    case .Point:
        return value.point.x + value.point.y
    default:
        return 0
    }
}

#test
{
    Swag.assert(sum(makePoint(2, 3)) == 5)

    // Braces holding one value of the payload's own type hold that value as it is.
    let p = ValuePoint{x: 4, y: 6}
    var value: Value = .Point{p}
    Swag.assert(sum(value) == 10)

    value = .Number{7}
    Swag.assert(sum(value) == 7)

    var values: [3] Value = [.Number{1}, .Point{x: 1, y: 1}, .None]
    var total = 0
    for v in values do
        total += sum(v)
    Swag.assert(total == 3)
}

// A guard in 'where' proves the case in the body, and an inline call keeps the proof of its argument.
#[Swag.Inline]
func twice(v: s32)->s32 => v * 2

#test
{
    var values: [3] Value = [.Number{1}, .Point{x: 5, y: 5}, .Number{2}]
    var total = 0
    for v in values where v is .Number do
        total += twice(v.number)
    Swag.assert(total == 6)

    // A block pointer reaches the union as well as a plain one.
    let first: [*] Value = &values[0]
    if first is .Number do
        Swag.assert(first.number == 1)
}
