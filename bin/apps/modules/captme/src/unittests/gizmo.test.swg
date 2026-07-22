#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Gizmo rotation math stays stable without painting.
#test
{
    var g: GizmoRect
    g.rect = {10, 20, 100, 50}

    @assert(Math.abs(g.computeRotate({60, -10}) - 0) < 0.001)
    @assert(Math.abs(g.computeRotate({110, 45}) - 90) < 0.001)
    @assert(Math.abs(g.computeRotate({60, 100}) - 180) < 0.001)
    @assert(Math.abs(g.computeRotate({10, 45}) - 270) < 0.001)

    @assert(g.toLocal({110, 45}) == Math.Point{110, 45})

    g.rotateEnabled = true
    g.rotateValue = 90
    let local = g.toLocal({110, 45})
    @assert(Math.abs(local.x - 60) < 0.001)
    @assert(Math.abs(local.y + 5) < 0.001)

    let rotated = GizmoRect.rotateVec({10, 0}, Math.toRadians(90.0'f32))
    @assert(Math.abs(rotated.x) < 0.001)
    @assert(Math.abs(rotated.y - 10) < 0.001)
}

