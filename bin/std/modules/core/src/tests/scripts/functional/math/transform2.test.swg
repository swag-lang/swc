#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectVec2(actual, expected: Math.Vector2)
{
    Swag.assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectTransform(actual, expected: Math.Transform2)
{
    Swag.assert(Math.isEqualEpsilon(actual.m11, expected.m11, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.m12, expected.m12, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.m21, expected.m21, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.m22, expected.m22, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.tx, expected.tx, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.ty, expected.ty, 0.001))
}

#test
{
    let identity = Math.Transform2.Identity
    Swag.assert(identity.isIdentity())
    expectTransform(identity, {1, 0, 0, 1, 0, 0})
    expectVec2(identity.transformPoint({3, -4}), {3, -4})
    expectVec2(identity.translation(), Math.Vector2.Zero)

    Swag.assert(identity.m[0, 0] == identity.m11)
    Swag.assert(identity.m[0, 1] == identity.m12)
    Swag.assert(identity.m[1, 0] == identity.m21)
    Swag.assert(identity.m[1, 1] == identity.m22)

    var transform = Math.Transform2{2, 3, 4, 5, 6, 7}
    Swag.assert(not transform.isIdentity())
    transform.setIdentity()
    Swag.assert(transform.isIdentity())
    expectTransform(transform, Math.Transform2.Identity)
}

#test
{
    var transform = Math.Transform2.createTranslation(3, -4)
    expectTransform(transform, {1, 0, 0, 1, 3, -4})
    expectVec2(transform.translation(), {3, -4})
    expectVec2(transform.transformPoint({1, 2}), {4, -2})

    transform.setTranslation({-5, 6})
    expectVec2(transform.translation(), {-5, 6})
    expectVec2(transform.transformPoint({1, 2}), {-4, 8})
    Swag.assert(transform.m31 == transform.tx)
    Swag.assert(transform.m32 == transform.ty)
}

#test
{
    let scale = Math.Transform2.createScale(2, 3, 10, 20)
    expectTransform(scale, {2, 0, 0, 3, -10, -40})
    expectVec2(scale.transformPoint({10, 20}), {10, 20})
    expectVec2(scale.transformPoint({11, 21}), {12, 23})

    let mirror = Math.Transform2.createScale(-1, 1, 2, 0)
    expectTransform(mirror, {-1, 0, 0, 1, 4, 0})
    expectVec2(mirror.transformPoint({3, 5}), {1, 5})
}

#test
{
    let rotate = Math.Transform2.createRotation(Math.ConstF32.PiBy2, 0, 0)
    expectTransform(rotate, {0, 1, -1, 0, 0, 0})
    expectVec2(rotate.transformPoint({1, 0}), {0, 1})
    expectVec2(rotate.transformPoint({0, 1}), {-1, 0})

    let centered = Math.Transform2.createRotation(Math.ConstF32.PiBy2, 10, 20)
    expectVec2(centered.transformPoint({10, 20}), {10, 20})
    expectVec2(centered.transformPoint({11, 20}), {10, 21})
}

// A vector goes through the rotation and the scale, but the translation that moves a point leaves it alone.
#test
{
    var transform = Math.Transform2.createRotation(Math.ConstF32.PiBy2, 0, 0)
    transform.multiply(Math.Transform2.createScale(2, 3, 0, 0))
    transform.multiply(Math.Transform2.createTranslation(5, 7))
    expectVec2(transform.transformVector({1, 0}), {0, 3})
    expectVec2(transform.transformVector({0, 1}), {-2, 0})
    expectVec2(transform.transformPoint({1, 0}), {5, 10})
    expectVec2(Math.Transform2.createTranslation(5, 7).transformVector({3, -4}), {3, -4})
}

#test
{
    var transform = Math.Transform2.createTranslation(2, 3)
    transform.multiply(Math.Transform2.createScale(2, 2, 0, 0))
    expectTransform(transform, {2, 0, 0, 2, 4, 6})
    expectVec2(transform.transformPoint({1, 1}), {6, 8})

    var selfMul = Math.Transform2.createScale(2, 3, 0, 0)
    selfMul.multiplyBorrowed(&selfMul)
    expectTransform(selfMul, {4, 0, 0, 9, 0, 0})
    expectVec2(selfMul.transformPoint({1, 1}), {4, 9})
}

func expectRect(actual, expected: Math.Rectangle)
{
    Swag.assert(Math.isEqualEpsilon(actual.x, expected.x, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.y, expected.y, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.width, expected.width, 0.001))
    Swag.assert(Math.isEqualEpsilon(actual.height, expected.height, 0.001))
}

// Transformed bounds hold the mapped corners, whatever the transform does to them.
#test
{
    const Source = Math.Rectangle{10, 20, 30, 40}

    expectRect(Math.Transform2.Identity.transformBounds(Source), Source)
    expectRect(Math.Transform2.createTranslation(5, -7).transformBounds(Source), {15, 13, 30, 40})
    expectRect(Math.Transform2.createScale(2, 3, 0, 0).transformBounds(Source), {20, 60, 60, 120})

    // A negative scale keeps the rectangle positive: the corners are ordered again.
    expectRect(Math.Transform2.createScale(-1, 1, 0, 0).transformBounds(Source), {-40, 20, 30, 40})

    // A quarter turn about the origin swaps the extents.
    let quarter = Math.Transform2.createRotation(Math.ConstF32.PiBy2, 0, 0)
    expectRect(quarter.transformBounds(Source), {-60, 10, 40, 30})
}

// The inverse undoes a general affine transform, and a singular one answers the identity.
#test
{
    let transform = Math.Transform2{2, 1, -0.5, 3, 10, -7}
    let point     = Math.Vector2{3, 5}
    expectVec2(transform.inverse().transformPoint(transform.transformPoint(point)), point)

    var composed = transform.inverse()
    composed.multiply(transform)
    expectTransform(composed, Math.Transform2.Identity)

    expectTransform(Math.Transform2.Identity.inverse(), Math.Transform2.Identity)
    expectTransform(Math.Transform2.createTranslation(4, -9).inverse(), Math.Transform2.createTranslation(-4, 9))

    // A transform that collapses the plane onto a line cannot be undone.
    expectTransform(Math.Transform2{1, 2, 2, 4, 5, 6}.inverse(), Math.Transform2.Identity)
}

// Multiplying a transform by itself reads every factor before writing the result.
#test
{
    var quarter = Math.Transform2.createRotation(Math.ConstF32.PiBy2, 0, 0)
    quarter.multiplyBorrowed(&quarter)
    expectTransform(quarter, Math.Transform2.createRotation(Math.ConstF32.Pi, 0, 0))

    var skew     = Math.Transform2{1, 0.5, 0.25, 1, 3, -2}
    var expected = skew
    expected.multiply({1, 0.5, 0.25, 1, 3, -2})
    skew.multiplyBorrowed(&skew)
    expectTransform(skew, expected)
}

// A tiny scale is not singular: it inverts to the matching large scale.
#test
{
    let tiny = Math.Transform2.createScale(0.0005, 0.0005, 0, 0)
    expectVec2(tiny.inverse().transformPoint({1, 1}), {2000, 2000})
}
