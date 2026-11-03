#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    var bytes = makeTypeFaceCollection()
    const Name = "pixel-test-indexed-font"
    let regular = expect TypeFace.create(Name, bytes.toSlice())
    let bold    = expect TypeFace.createAt(Name, bytes.toSlice(), 1)
    Swag.assert(regular != bold and not regular.isBold() and bold.isBold())
    let ownedName = String.from(Name)
    Swag.assert((expect TypeFace.createAt(ownedName.toString(), bytes.toSlice(), 1)) == bold)
    Swag.assert((expect TypeFace.createAt(Name, bytes.toSlice(), 0)) == regular)

    // A failed index cannot replace a valid entry, and copying the bytes ends the borrow.
    var outcome: Swag.Error
    discard catch TypeFace.createAt(Name, bytes.toSlice(), 2) as outcome
    Swag.assert(outcome.value() != null)
    bytes.fill(0)
    bytes.free()
    Swag.assert((expect regular.renderGlyph('A', 16)).width > 0)
    Swag.assert((expect bold.renderGlyph('A', 16)).width > 0)
}

#test
{
    let bytes = makeTypeFaceCollection()
    let path  = makeTempImagePath(".ttc")
    discard expect File.writeAllBytes(path.toString(), bytes.toSlice())
    defer discard catch File.delete(path.toString())
    let regular = expect TypeFace.load(path.toString())
    let bold    = expect TypeFace.loadAt(path.toString(), 1)
    Swag.assert(regular != bold and not regular.isBold() and bold.isBold())
    Swag.assert((expect TypeFace.loadAt(path.toString(), 0)) == regular)
    Swag.assert((expect TypeFace.loadAt(path.toString(), 1)) == bold)
    var outcome: Swag.Error
    discard catch TypeFace.loadAt(path.toString(), 2) as outcome
    Swag.assert(outcome.value() != null)
    outcome = {}
    discard catch TypeFace.loadAt(getTestDataPath("segoeui.ttf").toString(), 1) as outcome
    Swag.assert(outcome.value() != null)
    discard expect File.delete(path.toString())
    Swag.assert((expect TypeFace.loadAt(path.toString(), 1)) == bold)
}
