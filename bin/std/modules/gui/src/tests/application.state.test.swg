#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Application state uses SCC and rewrites a legacy raw TagBin state on the next save.
#test
{
    let path = Testing.tempFilePath("gui-state-", ".scc")
    defer discard catch File.delete(path)

    var app: Application
    app.setStatePath(path)
    expect app.saveState()
    Swag.assert(expect Scc.hasSignature(path))

    var reader: Scc.Reader
    expect reader.initialize(path)
    Swag.assert(reader.kind() == expect Guid128.parse("89c98d18-11dc-42a0-910c-4bb64b3e2776"))
    Swag.assert((reader.chunks()).count == 1)
    Swag.assert(reader.manifest().name == Path.fileName(path))
    var legacy = expect reader.readChunk(reader.chunks()[0].id)
    reader.close()

    expect File.writeAllBytes(path, legacy.toSlice())
    Swag.assert(!(expect Scc.hasSignature(path)))
    expect app.loadState()
    expect app.saveState()
    Swag.assert(expect Scc.hasSignature(path))
}
