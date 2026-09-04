#global private
using Swag

struct(T, N: s32) GenericBuffer
{
    values: [N] T
}

const STRUCT_INFO = cast(const *Swag.TypeInfoStruct) #typeof(GenericBuffer'(u16, 7))
const COUNT_VALUE = cast(const *s32?) STRUCT_INFO.generics[1].value

#assert(STRUCT_INFO.fromGeneric != null)
#assert(STRUCT_INFO.generics.count == 2)
#assert(STRUCT_INFO.generics[0].name == "T")
#assert(STRUCT_INFO.generics[0].pointedType == u16)
#assert(STRUCT_INFO.generics[1].name == "N")
#assert(STRUCT_INFO.generics[1].pointedType == s32)
#assert(COUNT_VALUE[] == 7)

#test
{
    Swag.assert(STRUCT_INFO.fromGeneric != null)
    Swag.assert(STRUCT_INFO.generics.count == 2)
    Swag.assert(STRUCT_INFO.generics[0].pointedType == u16)
    Swag.assert(STRUCT_INFO.generics[1].pointedType == s32)
    Swag.assert(COUNT_VALUE[] == 7)
}
