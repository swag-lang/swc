#global fileprivate
using Swag

// The compiler exports TypeValue.crc as the standard CRC-32 of the value name (field,
// enum value, method, ...). Runtime reflection (Core.Reflection field/method lookup)
// relies on this matching Core.Hash.Crc32.compute, so the values below are the known
// standard CRC-32 of each name.

struct CrcProbe
{
    bar:   s32
    baz:   f32
    label: string
}

enum CrcEnum
{
    Alpha
    Beta
}

#test
{
    let ts = cast(const *Swag.TypeInfoStruct) #typeof(CrcProbe)
    @assert(@countof(ts.fields) == 3)

    @assert(ts.fields[0].name == "bar"   and ts.fields[0].crc == 1996459178)
    @assert(ts.fields[1].name == "baz"   and ts.fields[1].crc == 2015626392)
    @assert(ts.fields[2].name == "label" and ts.fields[2].crc == 245846248)

    // Distinct names hash to distinct, non-zero CRCs.
    @assert(ts.fields[0].crc != 0 and ts.fields[1].crc != 0 and ts.fields[2].crc != 0)
    @assert(ts.fields[0].crc != ts.fields[1].crc)

    // Enum value names get their CRC too.
    let te = cast(const *Swag.TypeInfoEnum) #typeof(CrcEnum)
    @assert(@countof(te.values) == 2)
    @assert(te.values[0].name == "Alpha" and te.values[0].crc == 287381102)
    @assert(te.values[1].name == "Beta"  and te.values[1].crc == 799255389)
}
