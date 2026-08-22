#global private     //

// A struct literal whose pointer members force the constant-payload route must still convert
// nested integer literals to the float fields they initialize, exactly as the checked
// assignment promised. The payload lowering once wrote the integer bytes as they were.

struct Point
{
    x, y: f32
}

struct Base
{
    type:     #null typeinfo
    target:   #null *Base
    accepted: bool
}

#[Swag.EnumFlags]
enum Modifiers
{
    None = 0
    Control
    Shift
}

enum Kind
{
    None
    Wheel
}

struct Evt
{
    using base: Base
    kind:       Kind
    button:     u32       = undefined
    surfacePos: Point
    delta:      Point
    modifiers:  Modifiers = None
}

#test
{
    var wheel = Evt{kind: .Wheel, surfacePos: {320, 210}, delta: {0, 120}, modifiers: .Control}
    @assert(wheel.kind == .Wheel)
    @assert(wheel.surfacePos.x == 320 and wheel.surfacePos.y == 210)
    @assert(wheel.delta.x == 0 and wheel.delta.y == 120)
    @assert(wheel.modifiers == .Control)
    @assert(wheel.type == null and wheel.target == null and !wheel.accepted)
}

// The same conversion holds for a nested tuple element and for an array of float pairs built
// from integer literals.
#test
{
    var pairs: [2] Point = [{1, 2}, {3, 4}]
    @assert(pairs[0].x == 1 and pairs[0].y == 2)
    @assert(pairs[1].x == 3 and pairs[1].y == 4)

    var mixed = Evt{kind: .Wheel, surfacePos: {x: 5, y: 6.5}}
    @assert(mixed.surfacePos.x == 5 and mixed.surfacePos.y == 6.5)
}
