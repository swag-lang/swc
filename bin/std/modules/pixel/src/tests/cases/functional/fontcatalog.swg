#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let bytes = makeTypeFaceCollection()
    let path  = makeTempImagePath(".ttc")
    discard expect File.writeAllBytes(path.toString(), bytes.toSlice())
    defer discard catch File.delete(path.toString())
    var catalog: FontCatalog
    Swag.require((expect catalog.addFile(path.toString())) == 2)
    Swag.require((expect catalog.addFile(path.toString())) == 0)
    Swag.require(catalog.toSlice().count == 2)
    let families = catalog.familyNames()
    Swag.require(families.count == 1 and families[0] == "Segoe UI")
    let regular = unwrap catalog.findFace("segoe ui")
    let bold    = unwrap catalog.findFace("Segoe UI", .Bold)
    Swag.require(regular.faceIndex == 0 and bold.faceIndex == 1)
    Swag.require((unwrap catalog.findFace("Segoe UI", .Italic)).faceIndex == 0)
    Swag.require((unwrap catalog.findFace("Segoe UI", .BoldItalic)).faceIndex == 1)
    Swag.require((unwrap catalog.findFace("Segoe UI", .Light)).faceIndex == 0)
    Swag.require((unwrap catalog.findFace("Segoe UI", .SemiBold)).faceIndex == 1)
    Swag.require(catalog.findFace("Missing family") == null)
    let loaded = expect bold.load()
    Swag.require(loaded.isBold())
    Swag.require((expect loaded.renderGlyph('A', 16)).width != 0)
    catalog.clear()
    Swag.require(catalog.toSlice().count == 0 and catalog.findFace("Segoe UI") == null)
    Swag.require(families[0] == "Segoe UI")
}

// A broken later collection face must not leave the earlier face in the catalog.
#test
{
    var bytes = makeTypeFaceCollection()
    let path  = makeTempImagePath(".ttc")
    for index in 4 do
        bytes[16 + index] = 255
    discard expect File.writeAllBytes(path.toString(), bytes.toSlice())
    defer discard catch File.delete(path.toString())
    var catalog: FontCatalog
    discard expect catalog.addFile(getTestDataPath("segoeui.ttf"))
    var outcome: Swag.Error
    discard catch catalog.addFile(path.toString()) as outcome
    Swag.require(outcome.value() != null and catalog.toSlice().count == 1)
    outcome = {}
    discard catch catalog.addFile(makeTempImagePath(".missing")) as outcome
    Swag.require(outcome.value() != null and catalog.toSlice().count == 1)
}

// Enumeration order cannot decide which duplicate family/style wins.
#test
{
    let bytes  = expect File.readAllBytes(getTestDataPath("segoeui.ttf"))
    let first  = makeTempImagePath(".ttf")
    let second = makeTempImagePath(".ttf")
    discard expect File.writeAllBytes(first.toString(), bytes.toSlice())
    defer discard catch File.delete(first.toString())
    discard expect File.writeAllBytes(second.toString(), bytes.toSlice())
    defer discard catch File.delete(second.toString())
    var forward, backward: FontCatalog
    discard expect forward.addFile(first.toString())
    discard expect forward.addFile(second.toString())
    discard expect backward.addFile(second.toString())
    discard expect backward.addFile(first.toString())
    let a = unwrap forward.findFace("Segoe UI")
    let b = unwrap backward.findFace("Segoe UI")
    Swag.require(a.path == b.path)
    let names      = forward.familyNames()
    let otherNames = backward.familyNames()
    Swag.require(names.count == 1 and otherNames.count == 1 and names[0] == otherNames[0])
    Swag.require(forward.toSlice().count == 2)
}

// Exercise selection through real metadata, including style tables that disagree with the name.
#test
{
    func fixture(weight, width: u16, italic: bool)->String
    {
        func read32(bytes: *Array'u8, offset: u64)->u32 => cast(u32, bytes[offset]) << 24 |
                                                           cast(u32, bytes[offset + 1]) << 16 |
                                                           cast(u32, bytes[offset + 2]) << 8 |
                                                           bytes[offset + 3]

        func write16(bytes: *Array'u8, offset: u64, value: u16)
        {
            bytes[offset]     = cast(u8, value >> 8)
            bytes[offset + 1] = cast(u8, value & 255)
        }

        var bytes      = expect File.readAllBytes(getTestDataPath("segoeui.ttf"))
        let tables     = cast(u32, bytes[4]) << 8 | bytes[5]
        var foundStyle = false
        for table in tables
        {
            let record = 12'u64 + table * 16
            let offset = read32(&bytes, record + 8)
            let tag    = read32(&bytes, record)
            if tag == 0x68656164
            {
                write16(&bytes, offset + 44, italic ? 2'u16 : 0'u16)
            }
            elif tag == 0x4F532F32
            {
                write16(&bytes, offset + 4, weight)
                write16(&bytes, offset + 6, width)
                write16(&bytes, offset + 62, italic ? 1'u16 : 0'u16)
                foundStyle = true
            }
        }

        Swag.require(foundStyle)
        let path = makeTempImagePath(".ttf")
        discard expect File.writeAllBytes(path.toString(), bytes.toSlice())
        return path
    }

    let paths = [fixture(400, 5, false), fixture(700, 3, false), fixture(400, 5, true),
                 fixture(600, 5, false), fixture(300, 5, false), fixture(700, 5, false)]
    defer
    {
        for path in paths do
            discard catch File.delete(path.toString())
    }

    var catalog: FontCatalog
    for path in paths do
        discard expect catalog.addFile(path.toString())
    Swag.require((unwrap catalog.findFace("Segoe UI")).path == paths[0])
    Swag.require((unwrap catalog.findFace("Segoe UI", .Bold)).path == paths[5])
    Swag.require((unwrap catalog.findFace("Segoe UI", .Italic)).path == paths[2])
    Swag.require((unwrap catalog.findFace("Segoe UI", .BoldItalic)).path == paths[2])
    Swag.require((unwrap catalog.findFace("Segoe UI", .SemiBold)).path == paths[3])
    Swag.require((unwrap catalog.findFace("Segoe UI", .Light)).path == paths[4])
}
