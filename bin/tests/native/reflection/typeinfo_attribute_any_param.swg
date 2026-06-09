#global fileprivate
using Swag

attr AnyTypeInfoParamAttr(value: any)

struct AnyTypeInfoParamPayload
{
    value: s32
}

#[AnyTypeInfoParamAttr(AnyTypeInfoParamPayload)]
struct AnyTypeInfoParamReflected
{
    value: s32
}

const ANY_TYPE_INFO_PARAM_INFO = cast(const *TypeInfoStruct) #typeof(AnyTypeInfoParamReflected)

#test
{
    @assert(@countof(ANY_TYPE_INFO_PARAM_INFO.attributes) == 1)

    let attribute = ANY_TYPE_INFO_PARAM_INFO.attributes[0]
    let value = cast(typeinfo) attribute.params[0].value

    @assert(attribute.type == #typeof(AnyTypeInfoParamAttr))
    @assert(attribute.params[0].name == "value")
    @assert(value == AnyTypeInfoParamPayload)
}
