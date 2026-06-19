#global fileprivate
using Swag

struct(T, N: s32) GenericBuffer
{
    values: [N] T
}

const STRUCT_INFO = cast(const *Swag.TypeInfoStruct) #typeof(GenericBuffer'(u16, 7))
const COUNT_VALUE = cast(const *s32) STRUCT_INFO.generics[1].value

#assert(STRUCT_INFO.fromGeneric != null)
#assert(@countof(STRUCT_INFO.generics) == 2)
#assert(STRUCT_INFO.generics[0].name == "T")
#assert(STRUCT_INFO.generics[0].pointedType == u16)
#assert(STRUCT_INFO.generics[1].name == "N")
#assert(STRUCT_INFO.generics[1].pointedType == s32)
#assert(dref COUNT_VALUE == 7)

#test
{
    @assert(STRUCT_INFO.fromGeneric != null)
    @assert(@countof(STRUCT_INFO.generics) == 2)
    @assert(STRUCT_INFO.generics[0].pointedType == u16)
    @assert(STRUCT_INFO.generics[1].pointedType == s32)
    @assert(dref COUNT_VALUE == 7)
}
