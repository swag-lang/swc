#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectVec2(actual, expected: Math.Vector2)
{
    Swag.assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectVec3(actual, expected: Math.Vector3)
{
    Swag.assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectVec4(actual, expected: Math.Vector4)
{
    Swag.assert(actual.isEqualEpsilon(expected, 0.001))
}

#test
{
    expectVec2(Math.Vector2.Zero, Math.Vector2{0, 0})
    expectVec2(Math.Vector2.One, Math.Vector2{1, 1})
    expectVec2(Math.Vector2.UnitX, Math.Vector2{1, 0})
    expectVec2(Math.Vector2.UnitY, Math.Vector2{0, 1})
    expectVec2(Math.Vector2.NegUnitX, Math.Vector2{-1, 0})
    expectVec2(Math.Vector2.NegUnitY, Math.Vector2{0, -1})
    Swag.assert(Math.Vector2.Max.x == Swag.F32.Max and Math.Vector2.Max.y == Swag.F32.Max)
    Swag.assert(Math.Vector2.NegMax.x == -Swag.F32.Max and Math.Vector2.NegMax.y == -Swag.F32.Max)
    Swag.assert(Math.Vector2.Min.x == Swag.F32.Min and Math.Vector2.Min.y == Swag.F32.Min)

    var vec: Math.Vector2 = 2.0
    expectVec2(vec, Math.Vector2{2, 2})

    vec.set(3, -4)
    expectVec2(vec, Math.Vector2{3, -4})
}

#test
{
    var vec = Math.Vector2{6, -8}
    vec += Math.Vector2{1, 2}
    expectVec2(vec, Math.Vector2{7, -6})

    vec -= Math.Vector2{3, -4}
    expectVec2(vec, Math.Vector2{4, -2})

    vec *= Math.Vector2{2, -3}
    expectVec2(vec, Math.Vector2{8, 6})

    vec /= Math.Vector2{4, 2}
    expectVec2(vec, Math.Vector2{2, 3})

    vec += 1
    expectVec2(vec, Math.Vector2{3, 4})

    vec -= 2
    expectVec2(vec, Math.Vector2{1, 2})

    vec *= 3
    expectVec2(vec, Math.Vector2{3, 6})

    vec /= 3
    expectVec2(vec, Math.Vector2{1, 2})
}

#test
{
    let vec = Math.Vector2{6, -8}
    expectVec2(vec + Math.Vector2{1, 2}, Math.Vector2{7, -6})
    expectVec2(vec - Math.Vector2{1, 2}, Math.Vector2{5, -10})
    expectVec2(vec * Math.Vector2{2, -3}, Math.Vector2{12, 24})
    expectVec2(vec / Math.Vector2{3, -2}, Math.Vector2{2, 4})

    expectVec2(vec + 1, Math.Vector2{7, -7})
    expectVec2(1 + vec, Math.Vector2{7, -7})
    expectVec2(vec - 1, Math.Vector2{5, -9})
    expectVec2(vec * 2, Math.Vector2{12, -16})
    expectVec2(2 * vec, Math.Vector2{12, -16})
    expectVec2(vec / 2, Math.Vector2{3, -4})
    expectVec2(-vec, Math.Vector2{-6, 8})
}

#test
{
    let vec = Math.Vector2{3, 4}
    Swag.assert(vec.length() == 5)
    Swag.assert(vec.lengthSquared() == 25)
    Swag.assert(vec.dot(Math.Vector2{2, 1}) == 10)
    expectVec2(vec.cross(2), Math.Vector2{8, -6})
    Swag.assert(vec.cross(Math.Vector2{2, 1}) == -5)
    Swag.assert(vec.distanceTo(Math.Vector2{6, 8}) == 5)
    Swag.assert(vec.distanceSquaredTo(Math.Vector2{6, 8}) == 25)

    var normalized = vec
    normalized.normalize()
    expectVec2(normalized, Math.Vector2{0.6, 0.8})
    expectVec2(vec.normalized(), Math.Vector2{0.6, 0.8})

    var safe = Math.Vector2.Zero
    safe.normalizeOrZero()
    expectVec2(safe, Math.Vector2.Zero)
    expectVec2(Math.Vector2.Zero.normalizedOrZero(), Math.Vector2.Zero)

    safe = Math.Vector2{3, 4}
    safe.normalizeOrZero()
    expectVec2(safe, Math.Vector2{0.6, 0.8})
    expectVec2(Math.Vector2{3, 4}.normalizedOrZero(), Math.Vector2{0.6, 0.8})
}

#test
{
    var vec = Math.Vector2{3, 4}
    vec.setLength(10)
    expectVec2(vec, Math.Vector2{6, 8})

    vec = Math.Vector2{3, 4}
    vec.setLengthOrZero(2)
    expectVec2(vec, Math.Vector2{1.2, 1.6})

    vec = Math.Vector2.Zero
    vec.setLengthOrZero(5)
    expectVec2(vec, Math.Vector2.Zero)

    vec = Math.Vector2{1, -2}
    Swag.assert(!vec.isZero())
    vec.setZero()
    Swag.assert(vec.isZero())
    Swag.assert(vec.isZeroEpsilon())
    Swag.assert(!Math.Vector2{0.01, 0}.isZeroEpsilon(0.001))

    vec = Math.Vector2{1, -2}
    vec.negate()
    expectVec2(vec, Math.Vector2{-1, 2})
    Swag.assert(Math.Vector2{1, 1}.isEqualEpsilon(Math.Vector2{1.00001, 0.99999}, 0.001))
    Swag.assert(!Math.Vector2{1, 1}.isEqualEpsilon(Math.Vector2{1.01, 1}, 0.001))
}

#test
{
    expectVec2(Math.Vector2.min(Math.Vector2{1, 5}, Math.Vector2{2, 4}), Math.Vector2{1, 4})
    expectVec2(Math.Vector2.max(Math.Vector2{1, 5}, Math.Vector2{2, 4}), Math.Vector2{2, 5})

    var vec = Math.Vector2{1.75, -1.25}
    vec.floor()
    expectVec2(vec, Math.Vector2{1, -2})

    vec = Math.Vector2{1.25, -1.75}
    vec.ceil()
    expectVec2(vec, Math.Vector2{2, -1})

    vec = Math.Vector2{1.25, -1.75}
    vec.round()
    expectVec2(vec, Math.Vector2{1, -2})
}

#test
{
    var vec = Math.Vector2{1, 0}
    vec.rotateBy(90.0'deg)
    expectVec2(vec, Math.Vector2{0, 1})

    Swag.assert(Math.isZeroEpsilon(Math.Vector2.UnitX.angleCosineTo(Math.Vector2.UnitY), 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2.UnitX.angleTo(Math.Vector2.UnitY), Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2.UnitX.orientedAngleTo(Math.Vector2.UnitY), Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2.UnitY.orientedAngleTo(Math.Vector2.UnitX), Math.ConstF32.TwoPi - Math.ConstF32.PiBy2, 0.001))

    expectVec2(Math.Vector2.lerp(Math.Vector2{0, 0}, Math.Vector2{10, -20}, 0.25), Math.Vector2{2.5, -5})

    vec = Math.Vector2{-2, 6}
    vec.clamp(Math.Vector2{0, 0}, Math.Vector2{4, 4})
    expectVec2(vec, Math.Vector2{0, 4})
    expectVec2(Math.Vector2{-2, 6}.clamped(Math.Vector2{0, 0}, Math.Vector2{4, 4}), Math.Vector2{0, 4})

    vec = Math.Vector2{3, 4}
    vec.clampLength(6, 10)
    expectVec2(vec, Math.Vector2{3.6, 4.8})

    vec = Math.Vector2{6, 8}
    vec.clampLength(2, 5)
    expectVec2(vec, Math.Vector2{3, 4})
    expectVec2(Math.Vector2{3, 4}.clampedLength(6, 10), Math.Vector2{3.6, 4.8})
    expectVec2(Math.Vector2{6, 8}.clampedLength(2, 5), Math.Vector2{3, 4})
    expectVec2(Math.Vector2{3, 4}.clampedLength(2, 6), Math.Vector2{3, 4})
}

#test
{
    let vec = Math.Vector2{2, -4}
    expectVec2(vec.absolute(), Math.Vector2{2, 4})
    expectVec2(vec.perpendicular(), Math.Vector2{4, 2})
    expectVec2(vec.perpendicularClockwise(), Math.Vector2{-4, -2})
    expectVec2(vec.projectedOnto(Math.Vector2{1, 0}), Math.Vector2{2, 0})
    expectVec2(vec.projectedOnto(Math.Vector2.Zero), Math.Vector2.Zero)
    expectVec2(Math.Vector2{2, -3}.reflected(Math.Vector2{0, 1}), Math.Vector2{2, 3})
    expectVec2(Math.Vector2{2, -4}.sign(), Math.Vector2{1, -1})
    Swag.assert(vec.isFinite())
    Swag.assert(!Math.Vector2{Swag.F32.Inf, 0}.isFinite())
    Swag.assert(Math.Vector2{Swag.F32.NaN, 0}.isNaN())
    Swag.assert(!vec.isNaN())

    var absVec = vec
    absVec.makeAbsolute()
    expectVec2(absVec, Math.Vector2{2, 4})

    var moved = Math.Vector2{0, 0}
    moved.moveTowards(Math.Vector2{10, 0}, 3)
    expectVec2(moved, Math.Vector2{3, 0})
    moved.moveTowards(Math.Vector2{4, 0}, 3)
    expectVec2(moved, Math.Vector2{4, 0})
    expectVec2(Math.Vector2{0, 0}.movedTowards(Math.Vector2{10, 0}, 3), Math.Vector2{3, 0})
    expectVec2(Math.Vector2{8, 0}.movedTowards(Math.Vector2{10, 0}, 3), Math.Vector2{10, 0})

    var velocity = Math.Vector2.Zero
    let smoothed = Math.Vector2.smoothDamp(Math.Vector2.Zero, Math.Vector2{10, 20}, &velocity, 0.5, 0.1)
    Swag.assert(smoothed.x > 0 and smoothed.x < 10)
    Swag.assert(smoothed.y > 0 and smoothed.y < 20)
    Swag.assert(velocity.x > 0 and velocity.y > 0)
}

#test
{
    expectVec2(Math.Vector2.fromPolar(Math.ConstF32.PiBy2, 2), Math.Vector2{0, 2})

    let polar = Math.Vector2{0, 2}.toPolar()
    Swag.assert(Math.isEqualEpsilon(polar.angle, Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(polar.radius, 2, 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2{0, 2}.toAngle(), Math.ConstF32.PiBy2, 0.001))

    var vec = Math.Vector2{2, 0}
    vec.setAngle(Math.ConstF32.PiBy2)
    expectVec2(vec, Math.Vector2{0, 2})
}

#test
{
    expectVec3(Math.Vector3.Zero, Math.Vector3{0, 0, 0})
    expectVec3(Math.Vector3.One, Math.Vector3{1, 1, 1})
    expectVec3(Math.Vector3.UnitX, Math.Vector3{1, 0, 0})
    expectVec3(Math.Vector3.UnitY, Math.Vector3{0, 1, 0})
    expectVec3(Math.Vector3.UnitZ, Math.Vector3{0, 0, 1})
    expectVec3(Math.Vector3.NegUnitX, Math.Vector3{-1, 0, 0})
    expectVec3(Math.Vector3.NegUnitY, Math.Vector3{0, -1, 0})
    expectVec3(Math.Vector3.NegUnitZ, Math.Vector3{0, 0, -1})
    Swag.assert(Math.Vector3.Max.x == Swag.F32.Max and Math.Vector3.Max.y == Swag.F32.Max and Math.Vector3.Max.z == Swag.F32.Max)
    Swag.assert(Math.Vector3.NegMax.x == -Swag.F32.Max and Math.Vector3.NegMax.y == -Swag.F32.Max and Math.Vector3.NegMax.z == -Swag.F32.Max)
    Swag.assert(Math.Vector3.Min.x == Swag.F32.Min and Math.Vector3.Min.y == Swag.F32.Min and Math.Vector3.Min.z == Swag.F32.Min)

    var vec: Math.Vector3 = 2.0
    expectVec3(vec, Math.Vector3{2, 2, 2})

    vec.set(3, -4, 5)
    expectVec3(vec, Math.Vector3{3, -4, 5})
}

#test
{
    var vec = Math.Vector3{6, -8, 10}
    vec += Math.Vector3{1, 2, 3}
    expectVec3(vec, Math.Vector3{7, -6, 13})

    vec -= Math.Vector3{3, -4, 5}
    expectVec3(vec, Math.Vector3{4, -2, 8})

    vec *= Math.Vector3{2, -3, 0.5}
    expectVec3(vec, Math.Vector3{8, 6, 4})

    vec /= Math.Vector3{4, 2, 2}
    expectVec3(vec, Math.Vector3{2, 3, 2})

    vec += 1
    expectVec3(vec, Math.Vector3{3, 4, 3})

    vec -= 2
    expectVec3(vec, Math.Vector3{1, 2, 1})

    vec *= 3
    expectVec3(vec, Math.Vector3{3, 6, 3})

    vec /= 3
    expectVec3(vec, Math.Vector3{1, 2, 1})
}

#test
{
    let vec = Math.Vector3{6, -8, 10}
    expectVec3(vec + Math.Vector3{1, 2, 3}, Math.Vector3{7, -6, 13})
    expectVec3(vec - Math.Vector3{1, 2, 3}, Math.Vector3{5, -10, 7})
    expectVec3(vec * Math.Vector3{2, -3, 0.5}, Math.Vector3{12, 24, 5})
    expectVec3(vec / Math.Vector3{3, -2, 5}, Math.Vector3{2, 4, 2})

    expectVec3(vec + 1, Math.Vector3{7, -7, 11})
    expectVec3(1 + vec, Math.Vector3{7, -7, 11})
    expectVec3(vec - 1, Math.Vector3{5, -9, 9})
    expectVec3(vec * 2, Math.Vector3{12, -16, 20})
    expectVec3(2 * vec, Math.Vector3{12, -16, 20})
    expectVec3(vec / 2, Math.Vector3{3, -4, 5})
    expectVec3(-vec, Math.Vector3{-6, 8, -10})
}

#test
{
    let vec = Math.Vector3{2, 3, 6}
    Swag.assert(vec.length() == 7)
    Swag.assert(vec.lengthSquared() == 49)
    Swag.assert(vec.dot(Math.Vector3{4, -2, 1}) == 8)
    expectVec3(Math.Vector3.UnitX.cross(Math.Vector3.UnitY), Math.Vector3.UnitZ)
    Swag.assert(vec.distanceTo(Math.Vector3{4, 6, 12}) == 7)
    Swag.assert(vec.distanceSquaredTo(Math.Vector3{4, 6, 12}) == 49)

    var normalized = vec
    normalized.normalize()
    expectVec3(normalized, Math.Vector3{2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})
    expectVec3(vec.normalized(), Math.Vector3{2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})

    var safe = Math.Vector3.Zero
    safe.normalizeOrZero()
    expectVec3(safe, Math.Vector3.Zero)
    expectVec3(Math.Vector3.Zero.normalizedOrZero(), Math.Vector3.Zero)

    safe = vec
    safe.normalizeOrZero()
    expectVec3(safe, Math.Vector3{2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})
    expectVec3(vec.normalizedOrZero(), Math.Vector3{2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})
}

#test
{
    var vec = Math.Vector3{2, 3, 6}
    vec.setLength(14)
    expectVec3(vec, Math.Vector3{4, 6, 12})

    vec = Math.Vector3{2, 3, 6}
    vec.setLengthOrZero(3.5)
    expectVec3(vec, Math.Vector3{1, 1.5, 3})

    vec = Math.Vector3.Zero
    vec.setLengthOrZero(5)
    expectVec3(vec, Math.Vector3.Zero)

    vec = Math.Vector3{1, -2, 3}
    Swag.assert(!vec.isZero())
    vec.setZero()
    Swag.assert(vec.isZero())
    Swag.assert(vec.isZeroEpsilon())
    Swag.assert(!Math.Vector3{0.01, 0, 0}.isZeroEpsilon(0.001))

    vec = Math.Vector3{1, -2, 3}
    vec.negate()
    expectVec3(vec, Math.Vector3{-1, 2, -3})
    Swag.assert(Math.Vector3{1, 1, 1}.isEqualEpsilon(Math.Vector3{1.00001, 0.99999, 1.00002}, 0.001))
    Swag.assert(!Math.Vector3{1, 1, 1}.isEqualEpsilon(Math.Vector3{1.01, 1, 1}, 0.001))
}

#test
{
    expectVec3(Math.Vector3.min(Math.Vector3{1, 5, -2}, Math.Vector3{2, 4, -3}), Math.Vector3{1, 4, -3})
    expectVec3(Math.Vector3.max(Math.Vector3{1, 5, -2}, Math.Vector3{2, 4, -3}), Math.Vector3{2, 5, -2})

    var vec = Math.Vector3{1.75, -1.25, 2.25}
    vec.floor()
    expectVec3(vec, Math.Vector3{1, -2, 2})

    vec = Math.Vector3{1.25, -1.75, 2.25}
    vec.ceil()
    expectVec3(vec, Math.Vector3{2, -1, 3})

    vec = Math.Vector3{1.25, -1.75, 2.25}
    vec.round()
    expectVec3(vec, Math.Vector3{1, -2, 2})
}

#test
{
    Swag.assert(Math.isZeroEpsilon(Math.Vector3.UnitX.angleCosineTo(Math.Vector3.UnitY), 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector3.UnitX.angleTo(Math.Vector3.UnitY), Math.ConstF32.PiBy2, 0.001))
    expectVec3(Math.Vector3.lerp(Math.Vector3{0, 0, 0}, Math.Vector3{10, -20, 30}, 0.25), Math.Vector3{2.5, -5, 7.5})

    var vec = Math.Vector3{-2, 6, 3}
    vec.clamp(Math.Vector3{0, 0, 0}, Math.Vector3{4, 4, 2})
    expectVec3(vec, Math.Vector3{0, 4, 2})
    expectVec3(Math.Vector3{-2, 6, 3}.clamped(Math.Vector3{0, 0, 0}, Math.Vector3{4, 4, 2}), Math.Vector3{0, 4, 2})

    vec = Math.Vector3{2, 3, 6}
    vec.clampLength(8, 14)
    expectVec3(vec, Math.Vector3{16.0 / 7.0, 24.0 / 7.0, 48.0 / 7.0})

    vec = Math.Vector3{4, 6, 12}
    vec.clampLength(2, 7)
    expectVec3(vec, Math.Vector3{2, 3, 6})
    expectVec3(Math.Vector3{2, 3, 6}.clampedLength(8, 14), Math.Vector3{16.0 / 7.0, 24.0 / 7.0, 48.0 / 7.0})
    expectVec3(Math.Vector3{4, 6, 12}.clampedLength(2, 7), Math.Vector3{2, 3, 6})
    expectVec3(Math.Vector3{2, 3, 6}.clampedLength(2, 8), Math.Vector3{2, 3, 6})
}

#test
{
    let vec = Math.Vector3{2, -4, 6}
    expectVec3(vec.absolute(), Math.Vector3{2, 4, 6})
    expectVec3(vec.projectedOnto(Math.Vector3{1, 0, 0}), Math.Vector3{2, 0, 0})
    expectVec3(vec.projectedOnto(Math.Vector3.Zero), Math.Vector3.Zero)
    expectVec3(Math.Vector3{2, -3, 4}.reflected(Math.Vector3{0, 1, 0}), Math.Vector3{2, 3, 4})
    expectVec3(Math.Vector3{2, -4, 6}.sign(), Math.Vector3{1, -1, 1})
    Swag.assert(vec.isFinite())
    Swag.assert(!Math.Vector3{Swag.F32.Inf, 0, 0}.isFinite())
    Swag.assert(Math.Vector3{Swag.F32.NaN, 0, 0}.isNaN())
    Swag.assert(!vec.isNaN())

    var absVec = vec
    absVec.makeAbsolute()
    expectVec3(absVec, Math.Vector3{2, 4, 6})

    var moved = Math.Vector3{0, 0, 0}
    moved.moveTowards(Math.Vector3{10, 0, 0}, 3)
    expectVec3(moved, Math.Vector3{3, 0, 0})
    moved.moveTowards(Math.Vector3{4, 0, 0}, 3)
    expectVec3(moved, Math.Vector3{4, 0, 0})
    expectVec3(Math.Vector3{0, 0, 0}.movedTowards(Math.Vector3{10, 0, 0}, 3), Math.Vector3{3, 0, 0})
    expectVec3(Math.Vector3{8, 0, 0}.movedTowards(Math.Vector3{10, 0, 0}, 3), Math.Vector3{10, 0, 0})

    var velocity = Math.Vector3.Zero
    let smoothed = Math.Vector3.smoothDamp(Math.Vector3.Zero, Math.Vector3{10, 20, 30}, &velocity, 0.5, 0.1)
    Swag.assert(smoothed.x > 0 and smoothed.x < 10)
    Swag.assert(smoothed.y > 0 and smoothed.y < 20)
    Swag.assert(smoothed.z > 0 and smoothed.z < 30)
    Swag.assert(velocity.x > 0 and velocity.y > 0 and velocity.z > 0)
}

#test
{
    expectVec3(Math.Vector3.fromSpherical(0, Math.ConstF32.PiBy2, 3), Math.Vector3{3, 0, 0})
    let spherical = Math.Vector3{0, 3, 0}.toSpherical()
    Swag.assert(Math.isEqualEpsilon(spherical.theta, 0, 0.001))
    Swag.assert(Math.isEqualEpsilon(spherical.phi, 0, 0.001))
    Swag.assert(Math.isEqualEpsilon(spherical.radius, 3, 0.001))

    expectVec3(Math.Vector3.fromCylindrical(Math.ConstF32.PiBy2, 3, 4), Math.Vector3{0, 4, 3})
    let cylindrical = Math.Vector3{0, 4, 3}.toCylindrical()
    Swag.assert(Math.isEqualEpsilon(cylindrical.theta, Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(cylindrical.radius, 3, 0.001))
    Swag.assert(cylindrical.height == 4)
}

#test
{
    expectVec4(Math.Vector4.Zero, Math.Vector4{0, 0, 0, 0})
    expectVec4(Math.Vector4.One, Math.Vector4{1, 1, 1, 1})
    expectVec4(Math.Vector4.UnitX, Math.Vector4{1, 0, 0, 0})
    expectVec4(Math.Vector4.UnitY, Math.Vector4{0, 1, 0, 0})
    expectVec4(Math.Vector4.UnitZ, Math.Vector4{0, 0, 1, 0})
    expectVec4(Math.Vector4.UnitW, Math.Vector4{0, 0, 0, 1})
    expectVec4(Math.Vector4.NegUnitX, Math.Vector4{-1, 0, 0, 0})
    expectVec4(Math.Vector4.NegUnitY, Math.Vector4{0, -1, 0, 0})
    expectVec4(Math.Vector4.NegUnitZ, Math.Vector4{0, 0, -1, 0})
    expectVec4(Math.Vector4.NegUnitW, Math.Vector4{0, 0, 0, -1})
    Swag.assert(Math.Vector4.Max.x == Swag.F32.Max and Math.Vector4.Max.y == Swag.F32.Max and Math.Vector4.Max.z == Swag.F32.Max and Math.Vector4.Max.w == Swag.F32.Max)
    Swag.assert(Math.Vector4.NegMax.x == -Swag.F32.Max and Math.Vector4.NegMax.y == -Swag.F32.Max and Math.Vector4.NegMax.z == -Swag.F32.Max and Math.Vector4.NegMax.w == -Swag.F32.Max)
    Swag.assert(Math.Vector4.Min.x == Swag.F32.Min and Math.Vector4.Min.y == Swag.F32.Min and Math.Vector4.Min.z == Swag.F32.Min and Math.Vector4.Min.w == Swag.F32.Min)

    var vec: Math.Vector4 = 2.0
    expectVec4(vec, Math.Vector4{2, 2, 2, 2})

    vec.set(3, -4, 5, -6)
    expectVec4(vec, Math.Vector4{3, -4, 5, -6})
}

#test
{
    var vec = Math.Vector4{6, -8, 10, -12}
    vec += Math.Vector4{1, 2, 3, 4}
    expectVec4(vec, Math.Vector4{7, -6, 13, -8})

    vec -= Math.Vector4{3, -4, 5, -6}
    expectVec4(vec, Math.Vector4{4, -2, 8, -2})

    vec *= Math.Vector4{2, -3, 0.5, -4}
    expectVec4(vec, Math.Vector4{8, 6, 4, 8})

    vec /= Math.Vector4{4, 2, 2, 4}
    expectVec4(vec, Math.Vector4{2, 3, 2, 2})

    vec += 1
    expectVec4(vec, Math.Vector4{3, 4, 3, 3})

    vec -= 2
    expectVec4(vec, Math.Vector4{1, 2, 1, 1})

    vec *= 3
    expectVec4(vec, Math.Vector4{3, 6, 3, 3})

    vec /= 3
    expectVec4(vec, Math.Vector4{1, 2, 1, 1})
}

#test
{
    let vec = Math.Vector4{6, -8, 10, -12}
    expectVec4(vec + Math.Vector4{1, 2, 3, 4}, Math.Vector4{7, -6, 13, -8})
    expectVec4(vec - Math.Vector4{1, 2, 3, 4}, Math.Vector4{5, -10, 7, -16})
    expectVec4(vec * Math.Vector4{2, -3, 0.5, -4}, Math.Vector4{12, 24, 5, 48})
    expectVec4(vec / Math.Vector4{3, -2, 5, -6}, Math.Vector4{2, 4, 2, 2})

    expectVec4(vec + 1, Math.Vector4{7, -7, 11, -11})
    expectVec4(1 + vec, Math.Vector4{7, -7, 11, -11})
    expectVec4(vec - 1, Math.Vector4{5, -9, 9, -13})
    expectVec4(vec * 2, Math.Vector4{12, -16, 20, -24})
    expectVec4(2 * vec, Math.Vector4{12, -16, 20, -24})
    expectVec4(vec / 2, Math.Vector4{3, -4, 5, -6})
    expectVec4(-vec, Math.Vector4{-6, 8, -10, 12})
}

#test
{
    let vec = Math.Vector4{2, 4, 5, 6}
    Swag.assert(vec.length() == 9)
    Swag.assert(vec.lengthSquared() == 81)
    Swag.assert(vec.dot(Math.Vector4{4, -2, 1, 3}) == 23)
    Swag.assert(vec.distanceTo(Math.Vector4{4, 8, 10, 12}) == 9)
    Swag.assert(vec.distanceSquaredTo(Math.Vector4{4, 8, 10, 12}) == 81)

    var normalized = vec
    normalized.normalize()
    expectVec4(normalized, Math.Vector4{2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})
    expectVec4(vec.normalized(), Math.Vector4{2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})

    var safe = Math.Vector4.Zero
    safe.normalizeOrZero()
    expectVec4(safe, Math.Vector4.Zero)
    expectVec4(Math.Vector4.Zero.normalizedOrZero(), Math.Vector4.Zero)

    safe = vec
    safe.normalizeOrZero()
    expectVec4(safe, Math.Vector4{2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})
    expectVec4(vec.normalizedOrZero(), Math.Vector4{2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})
}

#test
{
    var vec = Math.Vector4{2, 4, 5, 6}
    vec.setLength(18)
    expectVec4(vec, Math.Vector4{4, 8, 10, 12})

    vec = Math.Vector4{2, 4, 5, 6}
    vec.setLengthOrZero(4.5)
    expectVec4(vec, Math.Vector4{1, 2, 2.5, 3})

    vec = Math.Vector4.Zero
    vec.setLengthOrZero(5)
    expectVec4(vec, Math.Vector4.Zero)

    vec = Math.Vector4{1, -2, 3, -4}
    Swag.assert(!vec.isZero())
    vec.setZero()
    Swag.assert(vec.isZero())
    Swag.assert(vec.isZeroEpsilon())
    Swag.assert(!Math.Vector4{0.01, 0, 0, 0}.isZeroEpsilon(0.001))

    vec = Math.Vector4{1, -2, 3, -4}
    vec.negate()
    expectVec4(vec, Math.Vector4{-1, 2, -3, 4})
    Swag.assert(Math.Vector4{1, 1, 1, 1}.isEqualEpsilon(Math.Vector4{1.00001, 0.99999, 1.00002, 0.99998}, 0.001))
    Swag.assert(!Math.Vector4{1, 1, 1, 1}.isEqualEpsilon(Math.Vector4{1.01, 1, 1, 1}, 0.001))
}

#test
{
    expectVec4(Math.Vector4.min(Math.Vector4{1, 5, -2, 8}, Math.Vector4{2, 4, -3, 9}), Math.Vector4{1, 4, -3, 8})
    expectVec4(Math.Vector4.max(Math.Vector4{1, 5, -2, 8}, Math.Vector4{2, 4, -3, 9}), Math.Vector4{2, 5, -2, 9})

    var vec = Math.Vector4{1.75, -1.25, 2.25, -2.75}
    vec.floor()
    expectVec4(vec, Math.Vector4{1, -2, 2, -3})

    vec = Math.Vector4{1.25, -1.75, 2.25, -2.25}
    vec.ceil()
    expectVec4(vec, Math.Vector4{2, -1, 3, -2})

    vec = Math.Vector4{1.25, -1.75, 2.25, -2.25}
    vec.round()
    expectVec4(vec, Math.Vector4{1, -2, 2, -2})
}

#test
{
    Swag.assert(Math.isZeroEpsilon(Math.Vector4.UnitX.angleCosineTo(Math.Vector4.UnitY), 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector4.UnitX.angleTo(Math.Vector4.UnitY), Math.ConstF32.PiBy2, 0.001))
    expectVec4(Math.Vector4.lerp(Math.Vector4{0, 0, 0, 0}, Math.Vector4{10, -20, 30, -40}, 0.25), Math.Vector4{2.5, -5, 7.5, -10})

    var vec = Math.Vector4{-2, 6, 3, -8}
    vec.clamp(Math.Vector4{0, 0, 0, -4}, Math.Vector4{4, 4, 2, 4})
    expectVec4(vec, Math.Vector4{0, 4, 2, -4})
    expectVec4(Math.Vector4{-2, 6, 3, -8}.clamped(Math.Vector4{0, 0, 0, -4}, Math.Vector4{4, 4, 2, 4}), Math.Vector4{0, 4, 2, -4})

    vec = Math.Vector4{2, 4, 5, 6}
    vec.clampLength(10, 18)
    expectVec4(vec, Math.Vector4{20.0 / 9.0, 40.0 / 9.0, 50.0 / 9.0, 60.0 / 9.0})

    vec = Math.Vector4{4, 8, 10, 12}
    vec.clampLength(2, 9)
    expectVec4(vec, Math.Vector4{2, 4, 5, 6})
    expectVec4(Math.Vector4{2, 4, 5, 6}.clampedLength(10, 18), Math.Vector4{20.0 / 9.0, 40.0 / 9.0, 50.0 / 9.0, 60.0 / 9.0})
    expectVec4(Math.Vector4{4, 8, 10, 12}.clampedLength(2, 9), Math.Vector4{2, 4, 5, 6})
    expectVec4(Math.Vector4{2, 4, 5, 6}.clampedLength(2, 10), Math.Vector4{2, 4, 5, 6})
}

#test
{
    let vec = Math.Vector4{2, -4, 6, -8}
    expectVec4(vec.absolute(), Math.Vector4{2, 4, 6, 8})
    expectVec4(vec.projectedOnto(Math.Vector4{1, 0, 0, 0}), Math.Vector4{2, 0, 0, 0})
    expectVec4(vec.projectedOnto(Math.Vector4.Zero), Math.Vector4.Zero)
    expectVec4(Math.Vector4{2, -3, 4, -5}.reflected(Math.Vector4{0, 1, 0, 0}), Math.Vector4{2, 3, 4, -5})
    expectVec4(Math.Vector4{2, -4, 6, -8}.sign(), Math.Vector4{1, -1, 1, -1})
    Swag.assert(vec.isFinite())
    Swag.assert(!Math.Vector4{Swag.F32.Inf, 0, 0, 0}.isFinite())
    Swag.assert(Math.Vector4{Swag.F32.NaN, 0, 0, 0}.isNaN())
    Swag.assert(!vec.isNaN())

    var absVec = vec
    absVec.makeAbsolute()
    expectVec4(absVec, Math.Vector4{2, 4, 6, 8})

    var moved = Math.Vector4{0, 0, 0, 0}
    moved.moveTowards(Math.Vector4{10, 0, 0, 0}, 3)
    expectVec4(moved, Math.Vector4{3, 0, 0, 0})
    moved.moveTowards(Math.Vector4{4, 0, 0, 0}, 3)
    expectVec4(moved, Math.Vector4{4, 0, 0, 0})
    expectVec4(Math.Vector4{0, 0, 0, 0}.movedTowards(Math.Vector4{10, 0, 0, 0}, 3), Math.Vector4{3, 0, 0, 0})
    expectVec4(Math.Vector4{8, 0, 0, 0}.movedTowards(Math.Vector4{10, 0, 0, 0}, 3), Math.Vector4{10, 0, 0, 0})

    var velocity = Math.Vector4.Zero
    let smoothed = Math.Vector4.smoothDamp(Math.Vector4.Zero, Math.Vector4{10, 20, 30, 40}, &velocity, 0.5, 0.1)
    Swag.assert(smoothed.x > 0 and smoothed.x < 10)
    Swag.assert(smoothed.y > 0 and smoothed.y < 20)
    Swag.assert(smoothed.z > 0 and smoothed.z < 30)
    Swag.assert(smoothed.w > 0 and smoothed.w < 40)
    Swag.assert(velocity.x > 0 and velocity.y > 0 and velocity.z > 0 and velocity.w > 0)
}

#test
{
    expectVec3(Math.Vector4{2, 4, 6, 2}.toVector3(), Math.Vector3{1, 2, 3})
    expectVec3(Math.Vector4{2, 4, 6, 0}.toVector3(), Math.Vector3{2, 4, 6})
    expectVec3(Math.Vector4{2, 4, 6, 2}.xyz(), Math.Vector3{2, 4, 6})
    expectVec2(Math.Vector4{2, 4, 6, 2}.xy(), Math.Vector2{2, 4})
    expectVec4(Math.Vector4.fromVector3(Math.Vector3{1, 2, 3}, 4), Math.Vector4{1, 2, 3, 4})
    expectVec4(Math.Vector4.fromVector2(Math.Vector2{1, 2}, 3, 4), Math.Vector4{1, 2, 3, 4})
}
