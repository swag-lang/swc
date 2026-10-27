#global private

// Every implementation of 'interface I is Base' starts with 'Base', so an 'I' value converts to
// a pointer to it and reads its members directly.

struct ItfBase
{
    x:      s32 = 4
    frozen: bool
}

impl ItfBase
{
    mtd twice()->s32 => .x * 2
}

interface IItfShape is ItfBase
{
    mtd area()->s32
}

struct ItfSquare
{
    using base: ItfBase
    side:       s32 = 3
}

impl IItfShape for ItfSquare
{
    mtd area()->s32 => .side * .side
}

// The base can sit deeper, as long as each step is the first field.
struct ItfArrow
{
    using square: ItfSquare
    tip: s32 = 1
}

impl IItfShape for ItfArrow
{
    mtd area()->s32 => .tip
}

func itfReadBase(base: *ItfBase)->s32 => base.x

#test
{
    var square: ItfSquare
    let shape = cast(IItfShape, &square)
    Swag.assert(shape.area() == 9)
    Swag.assert(shape.x == 4)
    Swag.assert(shape.twice() == 8)

    shape.frozen = true
    Swag.assert(square.frozen)
    Swag.assert(itfReadBase(shape) == 4)
}

#test
{
    var arrow: ItfArrow
    let shape = cast(IItfShape, &arrow)
    let base:  *ItfBase = shape
    Swag.assert(base == &arrow.square.base)

    shape.x = 7
    Swag.assert(arrow.x == 7)
    Swag.assert(shape.area() == 1)
}
