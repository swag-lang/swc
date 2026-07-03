#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func expectVec2(actual, expected: Math.Vector2)
{
    @assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectTransform(actual, expected: Math.Transform2)
{
    @assert(Math.isEqualEpsilon(actual.m11, expected.m11, 0.001))
    @assert(Math.isEqualEpsilon(actual.m12, expected.m12, 0.001))
    @assert(Math.isEqualEpsilon(actual.m21, expected.m21, 0.001))
    @assert(Math.isEqualEpsilon(actual.m22, expected.m22, 0.001))
    @assert(Math.isEqualEpsilon(actual.tx, expected.tx, 0.001))
    @assert(Math.isEqualEpsilon(actual.ty, expected.ty, 0.001))
}

#test
{
    let identity = Math.Transform2.Identity
    @assert(identity.isIdentity())
    expectTransform(identity, Math.Transform2{1, 0, 0, 1, 0, 0})
    expectVec2(identity.transformPoint(Math.Vector2{3, -4}), Math.Vector2{3, -4})
    expectVec2(identity.getTranslation(), Math.Vector2.Zero)

    @assert(identity.m[0, 0] == identity.m11)
    @assert(identity.m[0, 1] == identity.m12)
    @assert(identity.m[1, 0] == identity.m21)
    @assert(identity.m[1, 1] == identity.m22)

    var transform = Math.Transform2{2, 3, 4, 5, 6, 7}
    @assert(!transform.isIdentity())
    transform.setIdentity()
    @assert(transform.isIdentity())
    expectTransform(transform, Math.Transform2.Identity)
}

#test
{
    var transform = Math.Transform2.createTranslation(3, -4)
    expectTransform(transform, Math.Transform2{1, 0, 0, 1, 3, -4})
    expectVec2(transform.getTranslation(), Math.Vector2{3, -4})
    expectVec2(transform.transformPoint(Math.Vector2{1, 2}), Math.Vector2{4, -2})

    transform.setTranslation(Math.Vector2{-5, 6})
    expectVec2(transform.getTranslation(), Math.Vector2{-5, 6})
    expectVec2(transform.transformPoint(Math.Vector2{1, 2}), Math.Vector2{-4, 8})
    @assert(transform.m31 == transform.tx)
    @assert(transform.m32 == transform.ty)
}

#test
{
    let scale = Math.Transform2.createScale(2, 3, 10, 20)
    expectTransform(scale, Math.Transform2{2, 0, 0, 3, -10, -40})
    expectVec2(scale.transformPoint(Math.Vector2{10, 20}), Math.Vector2{10, 20})
    expectVec2(scale.transformPoint(Math.Vector2{11, 21}), Math.Vector2{12, 23})

    let mirror = Math.Transform2.createScale(-1, 1, 2, 0)
    expectTransform(mirror, Math.Transform2{-1, 0, 0, 1, 4, 0})
    expectVec2(mirror.transformPoint(Math.Vector2{3, 5}), Math.Vector2{1, 5})
}

#test
{
    let rotate = Math.Transform2.createRotation(Math.ConstF32.PiBy2, 0, 0)
    expectTransform(rotate, Math.Transform2{0, 1, -1, 0, 0, 0})
    expectVec2(rotate.transformPoint(Math.Vector2{1, 0}), Math.Vector2{0, 1})
    expectVec2(rotate.transformPoint(Math.Vector2{0, 1}), Math.Vector2{-1, 0})

    let centered = Math.Transform2.createRotation(Math.ConstF32.PiBy2, 10, 20)
    expectVec2(centered.transformPoint(Math.Vector2{10, 20}), Math.Vector2{10, 20})
    expectVec2(centered.transformPoint(Math.Vector2{11, 20}), Math.Vector2{10, 21})
}

#test
{
    var transform = Math.Transform2.createTranslation(2, 3)
    transform.multiply(Math.Transform2.createScale(2, 2, 0, 0))
    expectTransform(transform, Math.Transform2{2, 0, 0, 2, 4, 6})
    expectVec2(transform.transformPoint(Math.Vector2{1, 1}), Math.Vector2{6, 8})

    var selfMul = Math.Transform2.createScale(2, 3, 0, 0)
    selfMul.multiply(selfMul)
    expectTransform(selfMul, Math.Transform2{4, 0, 0, 9, 0, 0})
    expectVec2(selfMul.transformPoint(Math.Vector2{1, 1}), Math.Vector2{4, 9})
}
