#global private

// Interface signatures can refer to later declarations, including a value that
// holds the interface itself. Completing the signature must not stop the file walk.
interface Renderer
{
    mtd render(painter: *Painter)->Point
}

struct Point { x: s32 }
struct Painter { renderer: Renderer? }
struct Backend { calls: s32 }

impl Renderer for Backend
{
    mtd impl render(painter: *Painter)->Point
    {
        Swag.assert(painter.renderer != null)
        .calls += 1
        return Point{.calls}
    }
}

#test
{
    var backend: Backend
    let renderer = cast(Renderer, &backend)
    var painter  = Painter{renderer}
    Swag.require(renderer.render(&painter).x == 1)
    Swag.require(backend.calls == 1)
}

interface Shape is Base
{
    mtd area()->s32
}

struct Base { width: s32 = 4 }
struct Square { using base: Base }

impl Shape for Square
{
    mtd impl area()->s32 => .width * .width
}

#test
{
    var square: Square
    let shape = cast(Shape, &square)
    Swag.require(shape.area() == 16)
    Swag.require(shape.width == 4)
}
