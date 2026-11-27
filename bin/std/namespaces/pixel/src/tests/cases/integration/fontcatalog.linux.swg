#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

#[Swag.TestTag("integration.fonts")]
#test
{
    let root     = makeTempImagePath("-catalog")
    let external = makeTempImagePath("-external-fonts")
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    expect Directory.create(external)
    defer catch Directory.delete(external, recurse: true)
    let bytes = expect File.readAllBytes(getTestDataPath("segoeui.ttf"))
    discard expect File.writeAllBytes(Path.combine(root, "font.ttf"), bytes.toSlice())
    discard expect File.writeAllBytes(Path.combine(external, "font.ttf"), bytes.toSlice())
    let cycle   = Path.combine(root, "cycle")
    let outside = Path.combine(root, "outside")
    Swag.require(Linux.symlinkat(root.storage(), Linux.AT_FDCWD, cycle.storage()) == 0)
    Swag.require(Linux.symlinkat(external.storage(), Linux.AT_FDCWD, outside.storage()) == 0)
    var catalog: FontCatalog
    Swag.require((expect catalog.addDirectory(root)) == 1)
    Swag.require(catalog.toSlice().count == 1)
    Swag.require((expect catalog.addDirectory(external)) == 1)
    Swag.require(catalog.toSlice().count == 2)
}
