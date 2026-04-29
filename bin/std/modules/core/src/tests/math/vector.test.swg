#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var vec = Math.Vector2{3, 4}
    @assert(vec.length() == 5)
    @assert(vec.lengthSquared() == 25)
    @assert(vec.dot(Math.Vector2{2, 1}) == 10)
    @assert(vec.cross(Math.Vector2{2, 1}) == -5)

    let normalized = vec.toNormalized()
    @assert(normalized.isEqualEpsilon(Math.Vector2{0.6, 0.8}, 0.001))

    vec.normalizeSafe()
    @assert(vec.isEqualEpsilon(normalized, 0.001))

    let projected = Math.Vector2{3, 4}.toProject(Math.Vector2{1, 0})
    @assert(projected.isEqualEpsilon(Math.Vector2{3, 0}, 0.001))

    let reflected = Math.Vector2{2, -3}.toReflect(Math.Vector2{0, 1})
    @assert(reflected.isEqualEpsilon(Math.Vector2{2, 3}, 0.001))
}

#test
{
    var vec = Math.Vector2{1, 0}
    vec.rotateBy(90.0'deg)
    @assert(vec.isEqualEpsilon(Math.Vector2{0, 1}, 0.001))

    let moved = Math.Vector2{0, 0}.toMovedTowards(Math.Vector2{10, 0}, 3)
    @assert(moved.isEqualEpsilon(Math.Vector2{3, 0}, 0.001))

    let polar = Math.Vector2.fromPolar(Math.ConstF32.PiBy2, 2)
    @assert(polar.isEqualEpsilon(Math.Vector2{0, 2}, 0.001))

    let polarValues = Math.Vector2{0, 2}.toPolar()
    @assert(Math.isEqualEpsilon(polarValues.angle, Math.ConstF32.PiBy2, 0.001))
    @assert(Math.isEqualEpsilon(polarValues.radius, 2, 0.001))
}

#test
{
    let x = Math.Vector3.UnitX
    let y = Math.Vector3.UnitY
    let z = x.cross(y)
    @assert(z.isEqualEpsilon(Math.Vector3.UnitZ, 0.001))
    @assert(x.dot(y) == 0)

    let vector = Math.Vector3{2, -4, 6}
    @assert(vector.toAbs().isEqualEpsilon(Math.Vector3{2, 4, 6}, 0.001))
    @assert(vector.toSign().isEqualEpsilon(Math.Vector3{1, -1, 1}, 0.001))

    let cylindrical = Math.Vector3.fromCylindrical(0, 3, 4)
    @assert(cylindrical.isEqualEpsilon(Math.Vector3{3, 4, 0}, 0.001))

    let cylindricalValues = Math.Vector3{0, 4, 3}.toCylindrical()
    @assert(Math.isEqualEpsilon(cylindricalValues.theta, Math.ConstF32.PiBy2, 0.001))
    @assert(Math.isEqualEpsilon(cylindricalValues.radius, 3, 0.001))
    @assert(cylindricalValues.height == 4)
}

#test
{
    let vector = Math.Vector4{2, 4, 6, 2}
    @assert(vector.toVector3().isEqualEpsilon(Math.Vector3{1, 2, 3}, 0.001))
    @assert(vector.xyz().isEqualEpsilon(Math.Vector3{2, 4, 6}, 0.001))
    @assert(vector.xy().isEqualEpsilon(Math.Vector2{2, 4}, 0.001))

    let from3 = Math.Vector4.fromVector3(Math.Vector3{1, 2, 3}, 4)
    @assert(from3.isEqualEpsilon(Math.Vector4{1, 2, 3, 4}, 0.001))

    let from2 = Math.Vector4.fromVector2(Math.Vector2{1, 2}, 3, 4)
    @assert(from2.isEqualEpsilon(Math.Vector4{1, 2, 3, 4}, 0.001))
}
