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
    expectVec2(Math.Vector2.Zero, {0, 0})
    expectVec2(Math.Vector2.One, {1, 1})
    expectVec2(Math.Vector2.UnitX, {1, 0})
    expectVec2(Math.Vector2.UnitY, {0, 1})
    expectVec2(Math.Vector2.NegUnitX, {-1, 0})
    expectVec2(Math.Vector2.NegUnitY, {0, -1})
    Swag.assert(Math.Vector2.Max.x == Swag.F32.Max and Math.Vector2.Max.y == Swag.F32.Max)
    Swag.assert(Math.Vector2.Min.x == -Swag.F32.Max and Math.Vector2.Min.y == -Swag.F32.Max)

    var vec: Math.Vector2 = 2.0
    expectVec2(vec, {2, 2})

    vec.set(3, -4)
    expectVec2(vec, {3, -4})
}

#test
{
    var vec = Math.Vector2{6, -8}
    vec += Math.Vector2{1, 2}
    expectVec2(vec, {7, -6})

    vec -= Math.Vector2{3, -4}
    expectVec2(vec, {4, -2})

    vec *= Math.Vector2{2, -3}
    expectVec2(vec, {8, 6})

    vec /= Math.Vector2{4, 2}
    expectVec2(vec, {2, 3})

    vec += 1
    expectVec2(vec, {3, 4})

    vec -= 2
    expectVec2(vec, {1, 2})

    vec *= 3
    expectVec2(vec, {3, 6})

    vec /= 3
    expectVec2(vec, {1, 2})
}

#test
{
    let vec = Math.Vector2{6, -8}
    expectVec2(vec + Math.Vector2{1, 2}, {7, -6})
    expectVec2(vec - Math.Vector2{1, 2}, {5, -10})
    expectVec2(vec * Math.Vector2{2, -3}, {12, 24})
    expectVec2(vec / Math.Vector2{3, -2}, {2, 4})

    expectVec2(vec + 1, {7, -7})
    expectVec2(1 + vec, {7, -7})
    expectVec2(vec - 1, {5, -9})
    expectVec2(vec * 2, {12, -16})
    expectVec2(2 * vec, {12, -16})
    expectVec2(vec / 2, {3, -4})
    expectVec2(-vec, {-6, 8})
}

#test
{
    let vec = Math.Vector2{3, 4}
    Swag.assert(vec.length() == 5)
    Swag.assert(vec.lengthSquared() == 25)
    Swag.assert(vec.dot({2, 1}) == 10)
    expectVec2(vec.cross(2), {8, -6})
    Swag.assert(vec.cross({2, 1}) == -5)
    Swag.assert(vec.distanceTo({6, 8}) == 5)
    Swag.assert(vec.distanceSquaredTo({6, 8}) == 25)

    var normalized = vec
    normalized.normalize()
    expectVec2(normalized, {0.6, 0.8})
    expectVec2(vec.normalized(), {0.6, 0.8})

    var safe = Math.Vector2.Zero
    safe.normalizeOrZero()
    expectVec2(safe, Math.Vector2.Zero)
    expectVec2(Math.Vector2.Zero.normalizedOrZero(), Math.Vector2.Zero)

    safe = {3, 4}
    safe.normalizeOrZero()
    expectVec2(safe, {0.6, 0.8})
    expectVec2(Math.Vector2{3, 4}.normalizedOrZero(), {0.6, 0.8})
}

#test
{
    var vec = Math.Vector2{3, 4}
    vec.setLength(10)
    expectVec2(vec, {6, 8})

    vec = {3, 4}
    vec.setLengthOrZero(2)
    expectVec2(vec, {1.2, 1.6})

    vec = Math.Vector2.Zero
    vec.setLengthOrZero(5)
    expectVec2(vec, Math.Vector2.Zero)

    vec = {1, -2}
    Swag.assert(not vec.isZero())
    vec.setZero()
    Swag.assert(vec.isZero())
    Swag.assert(vec.isZeroEpsilon())
    Swag.assert(not Math.Vector2{0.01, 0}.isZeroEpsilon(0.001))

    vec = {1, -2}
    vec.negate()
    expectVec2(vec, {-1, 2})
    Swag.assert(Math.Vector2{1, 1}.isEqualEpsilon({1.00001, 0.99999}, 0.001))
    Swag.assert(not Math.Vector2{1, 1}.isEqualEpsilon({1.01, 1}, 0.001))
}

#test
{
    expectVec2(Math.Vector2.min({1, 5}, {2, 4}), {1, 4})
    expectVec2(Math.Vector2.max({1, 5}, {2, 4}), {2, 5})

    var vec = Math.Vector2{1.75, -1.25}
    vec.floor()
    expectVec2(vec, {1, -2})

    vec = {1.25, -1.75}
    vec.ceil()
    expectVec2(vec, {2, -1})

    vec = {1.25, -1.75}
    vec.round()
    expectVec2(vec, {1, -2})
}

#test
{
    var vec = Math.Vector2{1, 0}
    vec.rotateBy(90.0'deg)
    expectVec2(vec, {0, 1})

    Swag.assert(Math.isZeroEpsilon(Math.Vector2.UnitX.angleCosineTo(Math.Vector2.UnitY), 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2.UnitX.angleTo(Math.Vector2.UnitY), Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2.UnitX.orientedAngleTo(Math.Vector2.UnitY), Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2.UnitY.orientedAngleTo(Math.Vector2.UnitX), Math.ConstF32.TwoPi - Math.ConstF32.PiBy2, 0.001))

    expectVec2(Math.Vector2.lerp({0, 0}, {10, -20}, 0.25), {2.5, -5})

    vec = {-2, 6}
    vec.clamp({0, 0}, {4, 4})
    expectVec2(vec, {0, 4})
    expectVec2(Math.Vector2{-2, 6}.clamped({0, 0}, {4, 4}), {0, 4})

    vec = {3, 4}
    vec.clampLength(6, 10)
    expectVec2(vec, {3.6, 4.8})

    vec = {6, 8}
    vec.clampLength(2, 5)
    expectVec2(vec, {3, 4})
    expectVec2(Math.Vector2{3, 4}.clampedLength(6, 10), {3.6, 4.8})
    expectVec2(Math.Vector2{6, 8}.clampedLength(2, 5), {3, 4})
    expectVec2(Math.Vector2{3, 4}.clampedLength(2, 6), {3, 4})
}

#test
{
    let vec = Math.Vector2{2, -4}
    expectVec2(vec.absolute(), {2, 4})
    expectVec2(vec.perpendicular(), {4, 2})
    expectVec2(vec.perpendicularClockwise(), {-4, -2})
    expectVec2(vec.projectedOnto({1, 0}), {2, 0})
    expectVec2(vec.projectedOnto(Math.Vector2.Zero), Math.Vector2.Zero)
    expectVec2(Math.Vector2{2, -3}.reflected({0, 1}), {2, 3})
    expectVec2(Math.Vector2{2, -4}.sign(), {1, -1})
    Swag.assert(vec.isFinite())
    Swag.assert(not Math.Vector2{Swag.F32.Inf, 0}.isFinite())
    Swag.assert(Math.Vector2{Swag.F32.NaN, 0}.isNaN())
    Swag.assert(not vec.isNaN())

    var absVec = vec
    absVec.makeAbsolute()
    expectVec2(absVec, {2, 4})

    var moved = Math.Vector2{0, 0}
    moved.moveTowards({10, 0}, 3)
    expectVec2(moved, {3, 0})
    moved.moveTowards({4, 0}, 3)
    expectVec2(moved, {4, 0})
    expectVec2(Math.Vector2{0, 0}.movedTowards({10, 0}, 3), {3, 0})
    expectVec2(Math.Vector2{8, 0}.movedTowards({10, 0}, 3), {10, 0})

    var velocity = Math.Vector2.Zero
    let smoothed = Math.Vector2.smoothDamp(Math.Vector2.Zero, {10, 20}, &velocity, 0.5, 0.1)
    Swag.assert(smoothed.x > 0 and smoothed.x < 10)
    Swag.assert(smoothed.y > 0 and smoothed.y < 20)
    Swag.assert(velocity.x > 0 and velocity.y > 0)
}

#test
{
    expectVec2(Math.Vector2.fromPolar(Math.ConstF32.PiBy2, 2), {0, 2})

    let polar = Math.Vector2{0, 2}.toPolar()
    Swag.assert(Math.isEqualEpsilon(polar.angle, Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(polar.radius, 2, 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector2{0, 2}.toAngle(), Math.ConstF32.PiBy2, 0.001))

    var vec = Math.Vector2{2, 0}
    vec.setAngle(Math.ConstF32.PiBy2)
    expectVec2(vec, {0, 2})
}

#test
{
    expectVec3(Math.Vector3.Zero, {0, 0, 0})
    expectVec3(Math.Vector3.One, {1, 1, 1})
    expectVec3(Math.Vector3.UnitX, {1, 0, 0})
    expectVec3(Math.Vector3.UnitY, {0, 1, 0})
    expectVec3(Math.Vector3.UnitZ, {0, 0, 1})
    expectVec3(Math.Vector3.NegUnitX, {-1, 0, 0})
    expectVec3(Math.Vector3.NegUnitY, {0, -1, 0})
    expectVec3(Math.Vector3.NegUnitZ, {0, 0, -1})
    Swag.assert(Math.Vector3.Max.x == Swag.F32.Max and
                Math.Vector3.Max.y == Swag.F32.Max and
                Math.Vector3.Max.z == Swag.F32.Max)
    Swag.assert(Math.Vector3.Min.x == -Swag.F32.Max and
                Math.Vector3.Min.y == -Swag.F32.Max and
                Math.Vector3.Min.z == -Swag.F32.Max)

    var vec: Math.Vector3 = 2.0
    expectVec3(vec, {2, 2, 2})

    vec.set(3, -4, 5)
    expectVec3(vec, {3, -4, 5})
}

#test
{
    var vec = Math.Vector3{6, -8, 10}
    vec += Math.Vector3{1, 2, 3}
    expectVec3(vec, {7, -6, 13})

    vec -= Math.Vector3{3, -4, 5}
    expectVec3(vec, {4, -2, 8})

    vec *= Math.Vector3{2, -3, 0.5}
    expectVec3(vec, {8, 6, 4})

    vec /= Math.Vector3{4, 2, 2}
    expectVec3(vec, {2, 3, 2})

    vec += 1
    expectVec3(vec, {3, 4, 3})

    vec -= 2
    expectVec3(vec, {1, 2, 1})

    vec *= 3
    expectVec3(vec, {3, 6, 3})

    vec /= 3
    expectVec3(vec, {1, 2, 1})
}

#test
{
    let vec = Math.Vector3{6, -8, 10}
    expectVec3(vec + Math.Vector3{1, 2, 3}, {7, -6, 13})
    expectVec3(vec - Math.Vector3{1, 2, 3}, {5, -10, 7})
    expectVec3(vec * Math.Vector3{2, -3, 0.5}, {12, 24, 5})
    expectVec3(vec / Math.Vector3{3, -2, 5}, {2, 4, 2})

    expectVec3(vec + 1, {7, -7, 11})
    expectVec3(1 + vec, {7, -7, 11})
    expectVec3(vec - 1, {5, -9, 9})
    expectVec3(vec * 2, {12, -16, 20})
    expectVec3(2 * vec, {12, -16, 20})
    expectVec3(vec / 2, {3, -4, 5})
    expectVec3(-vec, {-6, 8, -10})
}

#test
{
    let vec = Math.Vector3{2, 3, 6}
    Swag.assert(vec.length() == 7)
    Swag.assert(vec.lengthSquared() == 49)
    Swag.assert(vec.dot({4, -2, 1}) == 8)
    expectVec3(Math.Vector3.UnitX.cross(Math.Vector3.UnitY), Math.Vector3.UnitZ)
    Swag.assert(vec.distanceTo({4, 6, 12}) == 7)
    Swag.assert(vec.distanceSquaredTo({4, 6, 12}) == 49)

    var normalized = vec
    normalized.normalize()
    expectVec3(normalized, {2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})
    expectVec3(vec.normalized(), {2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})

    var safe = Math.Vector3.Zero
    safe.normalizeOrZero()
    expectVec3(safe, Math.Vector3.Zero)
    expectVec3(Math.Vector3.Zero.normalizedOrZero(), Math.Vector3.Zero)

    safe = vec
    safe.normalizeOrZero()
    expectVec3(safe, {2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})
    expectVec3(vec.normalizedOrZero(), {2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0})
}

#test
{
    var vec = Math.Vector3{2, 3, 6}
    vec.setLength(14)
    expectVec3(vec, {4, 6, 12})

    vec = {2, 3, 6}
    vec.setLengthOrZero(3.5)
    expectVec3(vec, {1, 1.5, 3})

    vec = Math.Vector3.Zero
    vec.setLengthOrZero(5)
    expectVec3(vec, Math.Vector3.Zero)

    vec = {1, -2, 3}
    Swag.assert(not vec.isZero())
    vec.setZero()
    Swag.assert(vec.isZero())
    Swag.assert(vec.isZeroEpsilon())
    Swag.assert(not Math.Vector3{0.01, 0, 0}.isZeroEpsilon(0.001))

    vec = {1, -2, 3}
    vec.negate()
    expectVec3(vec, {-1, 2, -3})
    Swag.assert(Math.Vector3{1, 1, 1}.isEqualEpsilon({1.00001, 0.99999, 1.00002}, 0.001))
    Swag.assert(not Math.Vector3{1, 1, 1}.isEqualEpsilon({1.01, 1, 1}, 0.001))
}

#test
{
    expectVec3(Math.Vector3.min({1, 5, -2}, {2, 4, -3}), {1, 4, -3})
    expectVec3(Math.Vector3.max({1, 5, -2}, {2, 4, -3}), {2, 5, -2})

    var vec = Math.Vector3{1.75, -1.25, 2.25}
    vec.floor()
    expectVec3(vec, {1, -2, 2})

    vec = {1.25, -1.75, 2.25}
    vec.ceil()
    expectVec3(vec, {2, -1, 3})

    vec = {1.25, -1.75, 2.25}
    vec.round()
    expectVec3(vec, {1, -2, 2})
}

#test
{
    Swag.assert(Math.isZeroEpsilon(Math.Vector3.UnitX.angleCosineTo(Math.Vector3.UnitY), 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector3.UnitX.angleTo(Math.Vector3.UnitY), Math.ConstF32.PiBy2, 0.001))
    expectVec3(Math.Vector3.lerp({0, 0, 0}, {10, -20, 30}, 0.25), {2.5, -5, 7.5})

    var vec = Math.Vector3{-2, 6, 3}
    vec.clamp({0, 0, 0}, {4, 4, 2})
    expectVec3(vec, {0, 4, 2})
    expectVec3(Math.Vector3{-2, 6, 3}.clamped({0, 0, 0}, {4, 4, 2}), {0, 4, 2})

    vec = {2, 3, 6}
    vec.clampLength(8, 14)
    expectVec3(vec, {16.0 / 7.0, 24.0 / 7.0, 48.0 / 7.0})

    vec = {4, 6, 12}
    vec.clampLength(2, 7)
    expectVec3(vec, {2, 3, 6})
    expectVec3(Math.Vector3{2, 3, 6}.clampedLength(8, 14), {16.0 / 7.0, 24.0 / 7.0, 48.0 / 7.0})
    expectVec3(Math.Vector3{4, 6, 12}.clampedLength(2, 7), {2, 3, 6})
    expectVec3(Math.Vector3{2, 3, 6}.clampedLength(2, 8), {2, 3, 6})
}

#test
{
    let vec = Math.Vector3{2, -4, 6}
    expectVec3(vec.absolute(), {2, 4, 6})
    expectVec3(vec.projectedOnto({1, 0, 0}), {2, 0, 0})
    expectVec3(vec.projectedOnto(Math.Vector3.Zero), Math.Vector3.Zero)
    expectVec3(Math.Vector3{2, -3, 4}.reflected({0, 1, 0}), {2, 3, 4})
    expectVec3(Math.Vector3{2, -4, 6}.sign(), {1, -1, 1})
    Swag.assert(vec.isFinite())
    Swag.assert(not Math.Vector3{Swag.F32.Inf, 0, 0}.isFinite())
    Swag.assert(Math.Vector3{Swag.F32.NaN, 0, 0}.isNaN())
    Swag.assert(not vec.isNaN())

    var absVec = vec
    absVec.makeAbsolute()
    expectVec3(absVec, {2, 4, 6})

    var moved = Math.Vector3{0, 0, 0}
    moved.moveTowards({10, 0, 0}, 3)
    expectVec3(moved, {3, 0, 0})
    moved.moveTowards({4, 0, 0}, 3)
    expectVec3(moved, {4, 0, 0})
    expectVec3(Math.Vector3{0, 0, 0}.movedTowards({10, 0, 0}, 3), {3, 0, 0})
    expectVec3(Math.Vector3{8, 0, 0}.movedTowards({10, 0, 0}, 3), {10, 0, 0})

    var velocity = Math.Vector3.Zero
    let smoothed = Math.Vector3.smoothDamp(Math.Vector3.Zero, {10, 20, 30}, &velocity, 0.5, 0.1)
    Swag.assert(smoothed.x > 0 and smoothed.x < 10)
    Swag.assert(smoothed.y > 0 and smoothed.y < 20)
    Swag.assert(smoothed.z > 0 and smoothed.z < 30)
    Swag.assert(velocity.x > 0 and velocity.y > 0 and velocity.z > 0)
}

#test
{
    expectVec3(Math.Vector3.fromSpherical(0, Math.ConstF32.PiBy2, 3), {3, 0, 0})
    let spherical = Math.Vector3{0, 3, 0}.toSpherical()
    Swag.assert(Math.isEqualEpsilon(spherical.theta, 0, 0.001))
    Swag.assert(Math.isEqualEpsilon(spherical.phi, 0, 0.001))
    Swag.assert(Math.isEqualEpsilon(spherical.radius, 3, 0.001))

    expectVec3(Math.Vector3.fromCylindrical(Math.ConstF32.PiBy2, 3, 4), {0, 4, 3})
    let cylindrical = Math.Vector3{0, 4, 3}.toCylindrical()
    Swag.assert(Math.isEqualEpsilon(cylindrical.theta, Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(cylindrical.radius, 3, 0.001))
    Swag.assert(cylindrical.height == 4)
}

#test
{
    expectVec4(Math.Vector4.Zero, {0, 0, 0, 0})
    expectVec4(Math.Vector4.One, {1, 1, 1, 1})
    expectVec4(Math.Vector4.UnitX, {1, 0, 0, 0})
    expectVec4(Math.Vector4.UnitY, {0, 1, 0, 0})
    expectVec4(Math.Vector4.UnitZ, {0, 0, 1, 0})
    expectVec4(Math.Vector4.UnitW, {0, 0, 0, 1})
    expectVec4(Math.Vector4.NegUnitX, {-1, 0, 0, 0})
    expectVec4(Math.Vector4.NegUnitY, {0, -1, 0, 0})
    expectVec4(Math.Vector4.NegUnitZ, {0, 0, -1, 0})
    expectVec4(Math.Vector4.NegUnitW, {0, 0, 0, -1})
    Swag.assert(Math.Vector4.Max.x == Swag.F32.Max and
                Math.Vector4.Max.y == Swag.F32.Max and
                Math.Vector4.Max.z == Swag.F32.Max and
                Math.Vector4.Max.w == Swag.F32.Max)
    Swag.assert(Math.Vector4.Min.x == -Swag.F32.Max and
                Math.Vector4.Min.y == -Swag.F32.Max and
                Math.Vector4.Min.z == -Swag.F32.Max and
                Math.Vector4.Min.w == -Swag.F32.Max)

    var vec: Math.Vector4 = 2.0
    expectVec4(vec, {2, 2, 2, 2})

    vec.set(3, -4, 5, -6)
    expectVec4(vec, {3, -4, 5, -6})
}

#test
{
    var vec = Math.Vector4{6, -8, 10, -12}
    vec += Math.Vector4{1, 2, 3, 4}
    expectVec4(vec, {7, -6, 13, -8})

    vec -= Math.Vector4{3, -4, 5, -6}
    expectVec4(vec, {4, -2, 8, -2})

    vec *= Math.Vector4{2, -3, 0.5, -4}
    expectVec4(vec, {8, 6, 4, 8})

    vec /= Math.Vector4{4, 2, 2, 4}
    expectVec4(vec, {2, 3, 2, 2})

    vec += 1
    expectVec4(vec, {3, 4, 3, 3})

    vec -= 2
    expectVec4(vec, {1, 2, 1, 1})

    vec *= 3
    expectVec4(vec, {3, 6, 3, 3})

    vec /= 3
    expectVec4(vec, {1, 2, 1, 1})
}

#test
{
    let vec = Math.Vector4{6, -8, 10, -12}
    expectVec4(vec + Math.Vector4{1, 2, 3, 4}, {7, -6, 13, -8})
    expectVec4(vec - Math.Vector4{1, 2, 3, 4}, {5, -10, 7, -16})
    expectVec4(vec * Math.Vector4{2, -3, 0.5, -4}, {12, 24, 5, 48})
    expectVec4(vec / Math.Vector4{3, -2, 5, -6}, {2, 4, 2, 2})

    expectVec4(vec + 1, {7, -7, 11, -11})
    expectVec4(1 + vec, {7, -7, 11, -11})
    expectVec4(vec - 1, {5, -9, 9, -13})
    expectVec4(vec * 2, {12, -16, 20, -24})
    expectVec4(2 * vec, {12, -16, 20, -24})
    expectVec4(vec / 2, {3, -4, 5, -6})
    expectVec4(-vec, {-6, 8, -10, 12})
}

#test
{
    let vec = Math.Vector4{2, 4, 5, 6}
    Swag.assert(vec.length() == 9)
    Swag.assert(vec.lengthSquared() == 81)
    Swag.assert(vec.dot({4, -2, 1, 3}) == 23)
    Swag.assert(vec.distanceTo({4, 8, 10, 12}) == 9)
    Swag.assert(vec.distanceSquaredTo({4, 8, 10, 12}) == 81)

    var normalized = vec
    normalized.normalize()
    expectVec4(normalized, {2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})
    expectVec4(vec.normalized(), {2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})

    var safe = Math.Vector4.Zero
    safe.normalizeOrZero()
    expectVec4(safe, Math.Vector4.Zero)
    expectVec4(Math.Vector4.Zero.normalizedOrZero(), Math.Vector4.Zero)

    safe = vec
    safe.normalizeOrZero()
    expectVec4(safe, {2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})
    expectVec4(vec.normalizedOrZero(), {2.0 / 9.0, 4.0 / 9.0, 5.0 / 9.0, 6.0 / 9.0})
}

#test
{
    var vec = Math.Vector4{2, 4, 5, 6}
    vec.setLength(18)
    expectVec4(vec, {4, 8, 10, 12})

    vec = {2, 4, 5, 6}
    vec.setLengthOrZero(4.5)
    expectVec4(vec, {1, 2, 2.5, 3})

    vec = Math.Vector4.Zero
    vec.setLengthOrZero(5)
    expectVec4(vec, Math.Vector4.Zero)

    vec = {1, -2, 3, -4}
    Swag.assert(not vec.isZero())
    vec.setZero()
    Swag.assert(vec.isZero())
    Swag.assert(vec.isZeroEpsilon())
    Swag.assert(not Math.Vector4{0.01, 0, 0, 0}.isZeroEpsilon(0.001))

    vec = {1, -2, 3, -4}
    vec.negate()
    expectVec4(vec, {-1, 2, -3, 4})
    Swag.assert(Math.Vector4{1, 1, 1, 1}.isEqualEpsilon({1.00001, 0.99999, 1.00002, 0.99998}, 0.001))
    Swag.assert(not Math.Vector4{1, 1, 1, 1}.isEqualEpsilon({1.01, 1, 1, 1}, 0.001))
}

#test
{
    expectVec4(Math.Vector4.min({1, 5, -2, 8}, {2, 4, -3, 9}), {1, 4, -3, 8})
    expectVec4(Math.Vector4.max({1, 5, -2, 8}, {2, 4, -3, 9}), {2, 5, -2, 9})

    var vec = Math.Vector4{1.75, -1.25, 2.25, -2.75}
    vec.floor()
    expectVec4(vec, {1, -2, 2, -3})

    vec = {1.25, -1.75, 2.25, -2.25}
    vec.ceil()
    expectVec4(vec, {2, -1, 3, -2})

    vec = {1.25, -1.75, 2.25, -2.25}
    vec.round()
    expectVec4(vec, {1, -2, 2, -2})
}

#test
{
    Swag.assert(Math.isZeroEpsilon(Math.Vector4.UnitX.angleCosineTo(Math.Vector4.UnitY), 0.001))
    Swag.assert(Math.isEqualEpsilon(Math.Vector4.UnitX.angleTo(Math.Vector4.UnitY), Math.ConstF32.PiBy2, 0.001))
    expectVec4(Math.Vector4.lerp({0, 0, 0, 0}, {10, -20, 30, -40}, 0.25), {2.5, -5, 7.5, -10})

    var vec = Math.Vector4{-2, 6, 3, -8}
    vec.clamp({0, 0, 0, -4}, {4, 4, 2, 4})
    expectVec4(vec, {0, 4, 2, -4})
    expectVec4(Math.Vector4{-2, 6, 3, -8}.clamped({0, 0, 0, -4}, {4, 4, 2, 4}), {0, 4, 2, -4})

    vec = {2, 4, 5, 6}
    vec.clampLength(10, 18)
    expectVec4(vec, {20.0 / 9.0, 40.0 / 9.0, 50.0 / 9.0, 60.0 / 9.0})

    vec = {4, 8, 10, 12}
    vec.clampLength(2, 9)
    expectVec4(vec, {2, 4, 5, 6})
    expectVec4(Math.Vector4{2, 4, 5, 6}.clampedLength(10, 18), {20.0 / 9.0, 40.0 / 9.0, 50.0 / 9.0, 60.0 / 9.0})
    expectVec4(Math.Vector4{4, 8, 10, 12}.clampedLength(2, 9), {2, 4, 5, 6})
    expectVec4(Math.Vector4{2, 4, 5, 6}.clampedLength(2, 10), {2, 4, 5, 6})
}

#test
{
    let vec = Math.Vector4{2, -4, 6, -8}
    expectVec4(vec.absolute(), {2, 4, 6, 8})
    expectVec4(vec.projectedOnto({1, 0, 0, 0}), {2, 0, 0, 0})
    expectVec4(vec.projectedOnto(Math.Vector4.Zero), Math.Vector4.Zero)
    expectVec4(Math.Vector4{2, -3, 4, -5}.reflected({0, 1, 0, 0}), {2, 3, 4, -5})
    expectVec4(Math.Vector4{2, -4, 6, -8}.sign(), {1, -1, 1, -1})
    Swag.assert(vec.isFinite())
    Swag.assert(not Math.Vector4{Swag.F32.Inf, 0, 0, 0}.isFinite())
    Swag.assert(Math.Vector4{Swag.F32.NaN, 0, 0, 0}.isNaN())
    Swag.assert(not vec.isNaN())

    var absVec = vec
    absVec.makeAbsolute()
    expectVec4(absVec, {2, 4, 6, 8})

    var moved = Math.Vector4{0, 0, 0, 0}
    moved.moveTowards({10, 0, 0, 0}, 3)
    expectVec4(moved, {3, 0, 0, 0})
    moved.moveTowards({4, 0, 0, 0}, 3)
    expectVec4(moved, {4, 0, 0, 0})
    expectVec4(Math.Vector4{0, 0, 0, 0}.movedTowards({10, 0, 0, 0}, 3), {3, 0, 0, 0})
    expectVec4(Math.Vector4{8, 0, 0, 0}.movedTowards({10, 0, 0, 0}, 3), {10, 0, 0, 0})

    var velocity = Math.Vector4.Zero
    let smoothed = Math.Vector4.smoothDamp(Math.Vector4.Zero, {10, 20, 30, 40}, &velocity, 0.5, 0.1)
    Swag.assert(smoothed.x > 0 and smoothed.x < 10)
    Swag.assert(smoothed.y > 0 and smoothed.y < 20)
    Swag.assert(smoothed.z > 0 and smoothed.z < 30)
    Swag.assert(smoothed.w > 0 and smoothed.w < 40)
    Swag.assert(velocity.x > 0 and velocity.y > 0 and velocity.z > 0 and velocity.w > 0)
}

#test
{
    expectVec3(Math.Vector4{2, 4, 6, 2}.toVector3(), {1, 2, 3})
    expectVec3(Math.Vector4{2, 4, 6, 0}.toVector3(), {2, 4, 6})
    expectVec3(Math.Vector4{2, 4, 6, 2}.xyz(), {2, 4, 6})
    expectVec2(Math.Vector4{2, 4, 6, 2}.xy(), {2, 4})
    expectVec4(Math.Vector4.fromVector3({1, 2, 3}, 4), {1, 2, 3, 4})
    expectVec4(Math.Vector4.fromVector2({1, 2}, 3, 4), {1, 2, 3, 4})
}
