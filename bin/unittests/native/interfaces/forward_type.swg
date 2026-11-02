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
    Swag.assert(renderer.render(&painter).x == 1)
    Swag.assert(backend.calls == 1)
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
    Swag.assert(shape.area() == 16)
    Swag.assert(shape.width == 4)
}
