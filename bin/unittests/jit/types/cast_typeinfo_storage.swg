#global private

struct CastTypeInfoFirst { value: s32 }
struct CastTypeInfoSecond { value: u64 }

func replaceType(value: *typeinfo)
{
    value[] = CastTypeInfoSecond
}

#test
{
    var type: typeinfo = CastTypeInfoFirst
    replaceType(&type)
    let raw = cast(const *void, type)
    let expected: typeinfo = CastTypeInfoSecond
    Swag.require(raw == cast(const *void, expected))
    let info = cast(const *Swag.TypeInfoStruct, raw)
    Swag.require(info.sizeof == #sizeof(CastTypeInfoSecond))
}
