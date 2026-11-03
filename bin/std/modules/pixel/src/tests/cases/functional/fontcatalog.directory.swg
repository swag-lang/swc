#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let root  = makeTempImagePath("-fonts")
    let child = Path.combine(root, "child")
    expect Directory.create(child, recurse: true)
    defer catch Directory.delete(root, recurse: true)
    let bytes = makeTypeFaceCollection()
    let font  = Path.combine(child, "family.TTC")
    discard expect File.writeAllBytes(font, bytes.toSlice())
    let ignored = Path.combine(root, "font.bin")
    discard expect File.writeAllBytes(ignored, bytes.toSlice())
    let bad = Path.combine(root, "broken.ttf")
    discard expect File.writeAllBytes(bad, [0'u8, 1, 2, 3])
    var catalog: FontCatalog
    Swag.require((expect catalog.addDirectory(root)) == 2)
    Swag.require((expect catalog.addDirectory(child)) == 0)
    Swag.require(catalog.toSlice().count == 2)
    Swag.require((unwrap catalog.findFace("Segoe UI", .Bold)).faceIndex == 1)
    var outcome: Swag.Error
    discard catch catalog.addDirectory(Path.combine(root, "absent")) as outcome
    Swag.require(outcome.value() != null and catalog.toSlice().count == 2)
}
