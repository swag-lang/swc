#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Reuse the existing font fixture. The second copy declares bold in head.macStyle,
// making index selection observable without adding another font binary.
func makeTypeFaceCollection()->Array'u8
{
    func read32(bytes: *Array'u8, offset: u64)->u32 => cast(u32, bytes[offset]) << 24 |
                                                    cast(u32, bytes[offset + 1]) << 16 |
                                                    cast(u32, bytes[offset + 2]) << 8 |
                                                    bytes[offset + 3]
    func write32(bytes: *Array'u8, offset: u64, value: u32)
    {
        for index in 4 do
            bytes[offset + index] = cast(u8, (value >> ((3 - index) * 8)) & 255)
    }

    let source = expect File.readAllBytes(getTestDataPath("segoeui.ttf"))
    var bytes: Array'u8
    bytes.resize(20)
    write32(&bytes, 0, 0x74746366)
    write32(&bytes, 4, 0x00010000)
    write32(&bytes, 8, 2)
    for index in 2
    {
        bytes.resize((bytes.count + 3) & ~3'u64)
        let offset = cast(u32, bytes.count)
        write32(&bytes, 12 + index * 4, offset)
        bytes.add(source.toSlice())
        let tables = cast(u32, bytes[offset + 4]) << 8 | bytes[offset + 5]
        var foundHead = false
        for table in tables
        {
            let record = cast(u64, offset) + 12 + table * 16
            let target = read32(&bytes, record + 8) + offset
            write32(&bytes, record + 8, target)
            if read32(&bytes, record) == 0x68656164
            {
                bytes[target + 44] = 0
                bytes[target + 45] = cast(u8, index)
                foundHead = true
            }
        }
        Swag.assert(foundHead)
    }
    return bytes
}

#test
{
    var bytes = makeTypeFaceCollection()
    const Name = "pixel-test-indexed-font"
    let regular = expect TypeFace.create(Name, bytes.toSlice())
    let bold = expect TypeFace.createAt(Name, bytes.toSlice(), 1)
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
    let path = makeTempImagePath(".ttc")
    discard expect File.writeAllBytes(path.toString(), bytes.toSlice())
    defer discard catch File.delete(path.toString())
    let regular = expect TypeFace.load(path.toString())
    let bold = expect TypeFace.loadAt(path.toString(), 1)
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
