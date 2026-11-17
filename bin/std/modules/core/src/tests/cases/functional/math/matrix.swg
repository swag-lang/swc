#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

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
}
