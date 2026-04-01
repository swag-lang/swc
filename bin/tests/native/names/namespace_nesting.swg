#global fileprivate

// Nested namespaces, qualified access, and using.

namespace Outer
{
    const VALUE = 10

    namespace Inner
    {
        const VALUE = 20

        func get()->s32 => VALUE

        namespace Deep
        {
            const VALUE = 30
            func get()->s32 => VALUE
        }
    }

    func get()->s32 => VALUE
}

// Qualified access at each level.
#test
{
    @assert(Outer.VALUE == 10)
    @assert(Outer.Inner.VALUE == 20)
    @assert(Outer.Inner.Deep.VALUE == 30)
}

// Functions resolve to their own namespace constants.
#test
{
    @assert(Outer.get() == 10)
    @assert(Outer.Inner.get() == 20)
    @assert(Outer.Inner.Deep.get() == 30)
}

// Using a nested namespace.
namespace UseInner
{
    using Outer.Inner

    #test
    {
        @assert(get() == 20)
        @assert(Deep.get() == 30)
    }
}

// Namespace with struct and functions.
namespace Geometry
{
    struct Point { x, y: s32 }

    func origin()->Point => {x: 0, y: 0}

    namespace Transform
    {
        func translate(p: Point, dx: s32, dy: s32)->Point
        {
            return {x: p.x + dx, y: p.y + dy}
        }
    }
}

#test
{
    let o = Geometry.origin()
    @assert(o.x == 0 and o.y == 0)

    let moved = Geometry.Transform.translate(o, 3, 4)
    @assert(moved.x == 3 and moved.y == 4)
}

// Dotted namespace declaration.
namespace A.B.C
{
    const X = 42
    func getX()->s32 => X
}

#test
{
    @assert(A.B.C.X == 42)
    @assert(A.B.C.getX() == 42)
}
