#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func addOffsetRect(list: #nonull *Pixel.LinePathList, serial: s32, x, y: f32)
{
    let path = list.newPath()
    path.serial = serial
    path.setRect(x, y, 20, 12)
}

func assertOffsetCleanPreservesPathIdentity()
{
    var paths: Pixel.LinePathList
    addOffsetRect(&paths, 10, 0, 0)
    addOffsetRect(&paths, 20, 100, 0)

    paths.flatten(.Normal)
    paths.offset(2)
    @assert(paths.paths.count == 2)

    @assert(paths.paths[0].serial == 10)
    @assert(paths.paths[1].serial == 20)
    @assert(paths.paths[0].polygon.points.count != 0)
    @assert(paths.paths[1].polygon.points.count != 0)
}

#test
{
    assertOffsetCleanPreservesPathIdentity()
}
