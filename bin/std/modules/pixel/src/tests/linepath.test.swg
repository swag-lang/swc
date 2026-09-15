#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math

// Returns the radius of every arc the path holds, in the order the path builds them.
func arcRadii(path: const *LinePath)->Array'f32
{
    var result: retval
    for element in path.elements where element.type == .Arc do
        result.add(element.p2.x)
    return result
}

// Each corner keeps the radius it was given, and the arcs come out clockwise from the top left.
#test
{
    var path: LinePath
    path.setRoundRectRaw(0, 0, 200, 120, 4, 8, 12, 16)

    let radii = arcRadii(&path)
    Swag.assert(radii.count == 4)
    Swag.assert(radii[0] == 4 and radii[1] == 8 and radii[2] == 12 and radii[3] == 16)

    // The path opens on the left edge, one top-left radius below the top.
    Swag.assert(path.startPoint.x == 0 and path.startPoint.y == 4)
    Swag.assert(path.isClosed)
}

// A corner with no radius stays square: it contributes no arc at all.
#test
{
    var path: LinePath
    path.setRoundRectRaw(0, 0, 200, 120, 0, 10, 0, 0)

    let radii = arcRadii(&path)
    Swag.assert(radii.count == 1 and radii[0] == 10)
    Swag.assert(path.startPoint.x == 0 and path.startPoint.y == 0)
}

// Two radii sharing a side cannot exceed it. All four shrink by one common factor, so the shape
// stays even instead of one corner swallowing another.
#test
{
    var path: LinePath
    path.setRoundRectRaw(0, 0, 200, 40, 30, 30, 30, 30)

    // The short sides are 40 long and carry 30 + 30, so the factor is 40 / 60 and every radius
    // lands on 20.
    let radii = arcRadii(&path)
    Swag.assert(radii.count == 4)
    for radius in radii do
        Swag.assert(Math.abs(radius - 20) <= 0.001)
}

// One oversized corner scales its neighbours down with it rather than being clamped alone.
#test
{
    var path: LinePath
    path.setRoundRectRaw(0, 0, 100, 100, 80, 20, 0, 0)

    // The top side carries 80 + 20 against 100, so nothing scales; the left side carries 80 + 0
    // against 100 and does not either.
    var radii = arcRadii(&path)
    Swag.assert(radii.count == 2)
    Swag.assert(Math.abs(radii[0] - 80) <= 0.001 and Math.abs(radii[1] - 20) <= 0.001)

    // Widening the top corners past the side scales both, keeping their 4:1 proportion.
    path.setRoundRectRaw(0, 0, 100, 400, 160, 40, 0, 0)
    radii = arcRadii(&path)
    Swag.assert(radii.count == 2)
    Swag.assert(Math.abs(radii[0] - 80) <= 0.001 and Math.abs(radii[1] - 20) <= 0.001)
}

// A negative radius is read as no radius rather than turning the corner inside out.
#test
{
    var path: LinePath
    path.setRoundRectRaw(0, 0, 200, 120, -5, 10, 0, 0)

    let radii = arcRadii(&path)
    Swag.assert(radii.count == 1 and radii[0] == 10)
    Swag.assert(path.startPoint.y == 0)
}

// The uniform form and the per-corner form describe the same shape when every corner agrees.
#test
{
    var uniform: LinePath
    uniform.setRoundRectRaw(10, 20, 200, 120, 12, 12)

    var corners: LinePath
    corners.setRoundRectRaw(10, 20, 200, 120, 12, 12, 12, 12)

    Swag.assert(uniform.elements.count == corners.elements.count)
    Swag.assert(uniform.startPoint == corners.startPoint)
    for index in uniform.elements.count
    {
        Swag.assert(uniform.elements[index].type == corners.elements[index].type)
        Swag.assert(uniform.elements[index].position == corners.elements[index].position)
        Swag.assert(uniform.elements[index].p2 == corners.elements[index].p2)
    }
}
