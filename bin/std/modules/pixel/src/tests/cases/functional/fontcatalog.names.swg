#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func makeNamedFontFile(family, style, typographicFamily, typographicStyle: string, weight: u16)->String
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

    func write32(bytes: *Array'u8, offset: u64, value: u32)
    {
        for index in 4 do
            bytes[offset + index] = cast(u8, (value >> ((3 - index) * 8)) & 255)
    }

    var names: Array'u8
    names.resize(54)
    write16(&names, 2, 4)
    write16(&names, 4, 54)
    const Ids = [1'u16, 2, 16, 17]
    for text, index in [family, style, typographicFamily, typographicStyle]
    {
        let record = 6 + index * 12
        write16(&names, record, 3)
        write16(&names, record + 2, 1)
        write16(&names, record + 4, 0x409)
        write16(&names, record + 6, Ids[index])
        write16(&names, record + 8, cast(u16, text.count * 2))
        write16(&names, record + 10, cast(u16, names.count - 54))
        for byte in text
        {
            names.add(0'u8)
            names.add(byte)
        }
    }

    var bytes      = expect File.readAllBytes(getTestDataPath("segoeui.ttf"))
    let tableCount = cast(u32, bytes[4]) << 8 | bytes[5]
    var foundNames, foundWeight: bool
    for table in tableCount
    {
        let record = 12'u64 + table * 16
        let offset = read32(&bytes, record + 8)
        let tag    = read32(&bytes, record)
        if tag == 0x6E616D65
        {
            write32(&bytes, record + 8, cast(u32, bytes.count))
            write32(&bytes, record + 12, cast(u32, names.count))
            bytes.add(names.toSlice())
            foundNames = true
        }
        elif tag == 0x4F532F32
        {
            write16(&bytes, offset + 4, weight)
            foundWeight = true
        }
    }

    Swag.require(foundNames and foundWeight)
    let path = makeTempImagePath(".ttf")
    discard expect File.writeAllBytes(path, bytes.toSlice())
    return path
}

#test
{
    let regular = makeNamedFontFile("Catalog Sans", "Regular", "Catalog Sans", "Regular", 400)
    defer discard catch File.delete(regular)
    let light = makeNamedFontFile("Catalog Sans Light", "Regular", "Catalog Sans", "Light", 300)
    defer discard catch File.delete(light)
    let semibold = makeNamedFontFile("Catalog Sans SemiBold", "Regular", "Catalog Sans", "SemiBold", 600)
    defer discard catch File.delete(semibold)
    let unrelated = makeNamedFontFile("Catalog Sans", "Bold", "Another Family", "Bold", 700)
    defer discard catch File.delete(unrelated)
    var catalog: FontCatalog
    for path in [semibold, unrelated, light, regular] do
        discard expect catalog.addFile(path.toString())
    let names = catalog.familyNames()
    Swag.require(names.count == 2 and names[0] == "Another Family" and names[1] == "Catalog Sans")
    Swag.require((unwrap catalog.findFace("catalog sans")).path == regular)
    Swag.require((unwrap catalog.findFace("Catalog Sans", .Light)).path == light)
    Swag.require((unwrap catalog.findFace("Catalog Sans", .SemiBold)).path == semibold)
    Swag.require((unwrap catalog.findFace("Catalog Sans", .Bold)).path == semibold)
    let legacy = unwrap catalog.findFace("Catalog Sans Light")
    Swag.require(legacy.path == light and legacy.metadata.typographicStyleName == "Light")
    Swag.require((unwrap catalog.findFace("Catalog Sans SemiBold")).path == semibold)
    Swag.require((unwrap catalog.findFace("Another Family", .Bold)).path == unrelated)
}
