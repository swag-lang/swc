#global if #command == Swag.CompilerCommand.Test
#global private
using Core

// A rejected move into the source's descendants must preserve the replacement target.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault-rename-cycle-%.bin", Guid64.random()))
    defer discard catch File.delete(path)
    var volume = expect Volume.create(path, "rename cycle password", MinimumSize)
    let source = expect volume.createNode("/source", true, 0, "")
    discard expect volume.createNode("/source/child", true, 0, "")
    let destination = expect volume.createNode("/source/child/target", true, 0, "")
    var error: Swag.Error
    catch volume.renameNode(source, "/source/child/target", true) as error
    Swag.assert(error.value() is Error)
    let preserved = volume.resolve("/source/child/target")
    Swag.assert(preserved != null and preserved.id == destination)
    expect volume.commit()
    volume.close()
    volume = expect Volume.open(path, "rename cycle password")
    let reopened = volume.resolve("/source/child/target")
    Swag.assert(reopened != null and reopened.id == destination)
    volume.close()
}
