#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let identity = Math.Matrix2x2.createIdentity()
    let rotation = Math.Matrix2x2.createRotation(Math.Angle.fromRadians(Math.ConstF32.PiBy2))
    Swag.require(rotation.transformVector(Math.Vector2.UnitX).isEqualEpsilon(Math.Vector2.UnitY, 0.001))
    let scaled = Math.Matrix2x2.createScale({2, 3}).multiplied(rotation)
    Swag.require(scaled.transformVector({1, 0}).isEqualEpsilon({0, 2}, 0.001))
    Swag.require(identity.m[0, 0] == 1 and identity.m[1, 1] == 1)

    let value = Math.Matrix2x2{[[1, 2], [3, 4]]}
    Swag.require(value.determinant() == -2)
    let inverse = value.inverted()
    let product = value.multiplied(inverse)
    Swag.require(Math.isEqualEpsilon(product.m[0, 0], 1'f32, 0.001))
    Swag.require(Math.isZeroEpsilon(product.m[0, 1], 0.001))
    Swag.require(Math.isZeroEpsilon(product.m[1, 0], 0.001))
    Swag.require(Math.isEqualEpsilon(product.m[1, 1], 1'f32, 0.001))
}

#test
{
    let identity = Math.Matrix3x3.createIdentity()
    Swag.require(identity.m[0, 0] == 1)
    Swag.require(identity.m[1, 1] == 1)
    Swag.require(identity.m[2, 2] == 1)

    var matrix: Math.Matrix3x3
    for y in 3
    {
        for x in 3 do
            matrix.m[x, y] = 7
    }

    matrix.setIdentity()

    Swag.require(matrix.m[0, 0] == 1)
    Swag.require(matrix.m[0, 1] == 0)
    Swag.require(matrix.m[0, 2] == 0)
    Swag.require(matrix.m[1, 0] == 0)
    Swag.require(matrix.m[1, 1] == 1)
    Swag.require(matrix.m[1, 2] == 0)
    Swag.require(matrix.m[2, 0] == 0)
    Swag.require(matrix.m[2, 1] == 0)
    Swag.require(matrix.m[2, 2] == 1)

    var value: Math.Matrix3x3
    value.m[0, 0] = 1
    value.m[1, 0] = 2
    value.m[2, 0] = 3
    value.m[0, 1] = 0
    value.m[1, 1] = 1
    value.m[2, 1] = 4
    value.m[0, 2] = 5
    value.m[1, 2] = 6
    value.m[2, 2] = 0
    Swag.require(value.determinant() == 1)
    let inverse = value.inverted()
    var mutableInverse = value
    mutableInverse.invert()
    for row in 3
    {
        for column in 3 do
            Swag.require(Math.isEqualEpsilon(mutableInverse.m[row, column], inverse.m[row, column], 0.0001))
    }
    let product = value.multiplied(inverse)
    for y in 3
    {
        for x in 3
        {
            if x == y do
                Swag.require(Math.isEqualEpsilon(product.m[x, y], 1'f32, 0.0001))
            else do
                Swag.require(Math.isZeroEpsilon(product.m[x, y], 0.0001))
        }
    }
    Swag.require(value.transposed().m[0, 1] == value.m[1, 0])
}

#test
{
    var matrix: Math.Matrix3x3
    matrix.m = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    let vector = matrix.transformVector(Math.Vector3{1, 2, 3})
    Swag.require(vector.x == 30 and vector.y == 36 and vector.z == 42)

    let other = Math.Matrix3x3{
        [[9, 6, 3],
         [8, 5, 2],
         [7, 4, 1]]}
    let product = matrix.multiplied(other)
    Swag.require(product.m[0, 0] == 46 and product.m[0, 1] == 28 and product.m[0, 2] == 10)
    Swag.require(product.m[1, 0] == 118 and product.m[1, 1] == 73 and product.m[1, 2] == 28)
    Swag.require(product.m[2, 0] == 190 and product.m[2, 1] == 118 and product.m[2, 2] == 46)
    let identityProduct = matrix.multiplied(Math.Matrix3x3.createIdentity())
    for row in 3
    {
        for column in 3 do
            Swag.require(identityProduct.m[row, column] == matrix.m[row, column])
    }

    let affine = Math.Matrix3x3{[[1, 0, 0], [0, 1, 0], [8, 9, 1]]}
    let position = affine.transformVector({2, 3, 1})
    let direction = affine.transformVector({2, 3, 0})
    Swag.require(position.x == 10 and position.y == 12 and position.z == 1)
    Swag.require(direction.x == 2 and direction.y == 3 and direction.z == 0)
    Swag.require(affine.transformPoint({2, 3}).isEqualEpsilon({10, 12}, 0.001))
    Swag.require(affine.transformDirection({2, 3}).isEqualEpsilon({2, 3}, 0.001))
    let rotation = Math.Matrix3x3.createRotation(Math.Angle.fromRadians(Math.ConstF32.PiBy2))
    Swag.require(rotation.transformDirection(Math.Vector2.UnitX).isEqualEpsilon(Math.Vector2.UnitY, 0.001))
    let normalTransform = Math.Matrix3x3.createScale({2, 3}).transformNormal({1, 1})
    Swag.require(Math.isEqualEpsilon(normalTransform.x, 0.5'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(normalTransform.y, 1'f32 / 3, 0.001))
    let scaled = Math.Matrix3x3.createScale({2, 3}).multiplied(rotation)
    let composed = scaled.multiplied(Math.Matrix3x3.createTranslation({4, 5}))
    Swag.require(composed.transformPoint({1, 0}).isEqualEpsilon({4, 7}, 0.001))
}

#test
{
    let value = Math.Matrix4x4{
        [[1, 2, 3, 4],
         [0, 1, 4, 2],
         [5, 6, 0, 1],
         [1, 0, 2, 1]]}
    Swag.require(Math.isEqualEpsilon(value.determinant(), 78'f32, 0.001))
    let inverse = value.inverted()
    var mutableInverse = value
    mutableInverse.invert()
    for row in 4
    {
        for column in 4 do
            Swag.require(Math.isEqualEpsilon(mutableInverse.m[row, column], inverse.m[row, column], 0.001))
    }
    let identity = value.multiplied(inverse)
    for row in 4
    {
        for column in 4
        {
            if row == column do
                Swag.require(Math.isEqualEpsilon(identity.m[row, column], 1'f32, 0.001))
            else do
                Swag.require(Math.isZeroEpsilon(identity.m[row, column], 0.001))
        }
    }
}

#test
{
    var matrix: Math.Matrix4x4
    matrix.m = [[1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15], [4, 8, 12, 16]]
    let vector = matrix.transformVector(Math.Vector4{1, 2, 3, 4})
    Swag.require(vector.x == 30 and vector.y == 70 and vector.z == 110 and vector.w == 150)

    let scale = Math.Matrix4x4{
        [[1, 0, 0, 0],
         [0, 2, 0, 0],
         [0, 0, 3, 0],
         [0, 0, 0, 4]]}
    let product = matrix.multiplied(scale)
    Swag.require(product.m[0, 0] == 1 and product.m[0, 1] == 10 and product.m[0, 2] == 27 and product.m[0, 3] == 52)
    Swag.require(product.m[1, 0] == 2 and product.m[1, 1] == 12 and product.m[1, 2] == 30 and product.m[1, 3] == 56)
    Swag.require(product.m[2, 0] == 3 and product.m[2, 1] == 14 and product.m[2, 2] == 33 and product.m[2, 3] == 60)
    Swag.require(product.m[3, 0] == 4 and product.m[3, 1] == 16 and product.m[3, 2] == 36 and product.m[3, 3] == 64)
    let identityProduct = matrix.multiplied(Math.Matrix4x4.createIdentity())
    for row in 4
    {
        for column in 4 do
            Swag.require(identityProduct.m[row, column] == matrix.m[row, column])
    }

    let affine = Math.Matrix4x4{
        [[1, 0, 0, 0],
         [0, 1, 0, 0],
         [0, 0, 1, 0],
         [5, 6, 7, 1]]}
    let position = affine.transformVector({1, 2, 3, 1})
    let direction = affine.transformVector({1, 2, 3, 0})
    Swag.require(position.x == 6 and position.y == 8 and position.z == 10 and position.w == 1)
    Swag.require(direction.x == 1 and direction.y == 2 and direction.z == 3 and direction.w == 0)
}

#test
{
    let identity = Math.Matrix4x4.createIdentity()
    Swag.require(identity.m[0, 0] == 1)
    Swag.require(identity.m[1, 1] == 1)
    Swag.require(identity.m[2, 2] == 1)
    Swag.require(identity.m[3, 3] == 1)

    var matrix: Math.Matrix4x4
    for y in 4
    {
        for x in 4 do
            matrix.m[x, y] = 7
    }

    matrix.setIdentity()

    Swag.require(matrix.m[0, 0] == 1)
    Swag.require(matrix.m[0, 1] == 0)
    Swag.require(matrix.m[0, 2] == 0)
    Swag.require(matrix.m[0, 3] == 0)
    Swag.require(matrix.m[1, 0] == 0)
    Swag.require(matrix.m[1, 1] == 1)
    Swag.require(matrix.m[1, 2] == 0)
    Swag.require(matrix.m[1, 3] == 0)
    Swag.require(matrix.m[2, 0] == 0)
    Swag.require(matrix.m[2, 1] == 0)
    Swag.require(matrix.m[2, 2] == 1)
    Swag.require(matrix.m[2, 3] == 0)
    Swag.require(matrix.m[3, 0] == 0)
    Swag.require(matrix.m[3, 1] == 0)
    Swag.require(matrix.m[3, 2] == 0)
    Swag.require(matrix.m[3, 3] == 1)

    let translation = Math.Matrix4x4.createTranslation({3, -4, 5})
    let moved = translation.transformPoint({1, 2, 3})
    Swag.require(moved.x == 4 and moved.y == -2 and moved.z == 8)
    let direction = translation.transformDirection({1, 2, 3})
    Swag.require(direction.x == 1 and direction.y == 2 and direction.z == 3)

    let scale = Math.Matrix4x4.createScale({2, 3, 4})
    Swag.require(scale.m[0, 0] == 2 and scale.m[1, 1] == 3 and scale.m[2, 2] == 4 and scale.m[3, 3] == 1)
    Swag.require(scale.m[0, 3] == 0 and scale.m[1, 3] == 0 and scale.m[2, 3] == 0)
    let scaledOrigin = scale.transformPoint(Math.Vector3.Zero)
    Swag.require(scaledOrigin.isZero())
    let scaledPoint = scale.transformPoint({1, 1, 1})
    Swag.require(scaledPoint.z == 4)
    let transformedNormal = scale.transformNormal({1, 1, 0})
    Swag.require(Math.isEqualEpsilon(transformedNormal.x, 0.5'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(transformedNormal.y, 1'f32 / 3, 0.001))
    Swag.require(transformedNormal.z == 0)
    let composed = Math.Matrix4x4.multiply(scale, translation)
    Swag.require(composed.m[2, 2] == 4 and composed.m[3, 2] == 5)
    Swag.require(composed.m[0, 1] == 0)
    Swag.require(composed.m[1, 1] == 3)
    Swag.require(composed.m[2, 1] == 0)
    Swag.require(composed.m[3, 1] == -4)
    Swag.require(Math.isEqualEpsilon(composed.determinant(), 24'f32, 0.001))
    let transformed = composed.transformPoint({1, 1, 1})
    Swag.require(transformed.x == 5)
    Swag.require(transformed.y == -1)
    Swag.require(transformed.z == 9)
    let restored = composed.inverted().transformPoint(transformed)
    Swag.require(restored.isEqualEpsilon({1, 1, 1}, 0.001))
    Swag.require(Math.isEqualEpsilon(
        Math.Matrix4x4.createPerspective(Math.ConstF32.PiBy2, 1, 1, 10).m[1, 1], 1, 0.0001))

    let view = Math.Matrix4x4.createLookAt({0, 0, 1}, {0, 0, 0}, Math.Vector3.UnitY)
    Swag.require(view.transformPoint({0, 0, 1}).isEqualEpsilon(Math.Vector3.Zero, 0.001))
    Swag.require(view.transformPoint(Math.Vector3.Zero).isEqualEpsilon({0, 0, -1}, 0.001))
    let trs = Math.Matrix4x4.createTRS(
        {1, 0, 0}, Math.Quaternion.fromAxisAngle(Math.Vector3.UnitZ, Math.ConstF32.PiBy2), {2, 1, 1})
    Swag.require(trs.transformPoint({1, 0, 0}).isEqualEpsilon({1, 2, 0}, 0.001))
    let orthographic = Math.Matrix4x4.createOrthographic(-1, 1, -1, 1, 1, 10)
    let nearPoint = orthographic.transformPoint({0, 0, -1})
    let farPoint = orthographic.transformPoint({0, 0, -10})
    Swag.require(Math.isZeroEpsilon(nearPoint.x, 0.001))
    Swag.require(Math.isZeroEpsilon(nearPoint.y, 0.001))
    Swag.require(Math.isEqualEpsilon(nearPoint.z, -1'f32, 0.001))
    Swag.require(Math.isZeroEpsilon(farPoint.x, 0.001))
    Swag.require(Math.isZeroEpsilon(farPoint.y, 0.001))
    Swag.require(Math.isEqualEpsilon(farPoint.z, 1'f32, 0.001))
}
