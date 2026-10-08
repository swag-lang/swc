#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Gizmo rotation math stays stable without painting.
#test
{
    var g: GizmoRect
    g.rect = {10, 20, 100, 50}

    Swag.assert(Math.abs(g.computeRotate({60, -10}) - 0) < 0.001)
    Swag.assert(Math.abs(g.computeRotate({110, 45}) - 90) < 0.001)
    Swag.assert(Math.abs(g.computeRotate({60, 100}) - 180) < 0.001)
    Swag.assert(Math.abs(g.computeRotate({10, 45}) - 270) < 0.001)

    Swag.assert(g.toLocal({110, 45}) == Math.Point{110, 45})

    g.rotateEnabled = true
    g.rotateValue   = 90
    let local = g.toLocal({110, 45})
    Swag.assert(Math.abs(local.x - 60) < 0.001)
    Swag.assert(Math.abs(local.y + 5) < 0.001)

    let rotated = GizmoRect.rotateVec({10, 0}, Math.toRadians(90.0'f32))
    Swag.assert(Math.abs(rotated.x) < 0.001)
    Swag.assert(Math.abs(rotated.y - 10) < 0.001)
}

// Each handle moves its own edges, a corner keeps the ratio along its diagonal, and no drag
// shrinks the box below its minimum size.
#test
{
    func start()->GizmoRect
    {
        var result: retval
        result.startRect  = {100, 100, 50, 40}
        result.movingRect = result.startRect
        return result
    }

    var g = start()
    g.resizeFrom(AnchorEdges[0], {10, 5}, false)
    Swag.assert(g.movingRect == Math.Rectangle{110, 105, 40, 35})

    g = start()
    g.resizeFrom(AnchorEdges[4], {10, 5}, false)
    Swag.assert(g.movingRect == Math.Rectangle{100, 100, 60, 40})

    g = start()
    g.resizeFrom(AnchorEdges[7], {10, 4}, true)
    Swag.assert(g.movingRect == Math.Rectangle{100, 100, 60, 50})

    g = start()
    g.resizeFrom(AnchorEdges[2], {10, 4}, true)
    Swag.assert(g.movingRect == Math.Rectangle{100, 90, 60, 50})

    g = start()
    g.resizeFrom(AnchorEdges[1], {0, 100}, false)
    Swag.assert(g.movingRect == Math.Rectangle{100, 138, 50, 2})

    g = start()
    g.resizeFrom(.Zero, {10, 10}, true)
    Swag.assert(g.movingRect == g.startRect)
}
