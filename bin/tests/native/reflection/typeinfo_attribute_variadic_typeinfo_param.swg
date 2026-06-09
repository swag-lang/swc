#global fileprivate
using Swag

attr VariadicTypeInfoParamAttr(value: typeinfo...)

struct VariadicTypeInfoParamPayload
{
    value: s32
}

#[VariadicTypeInfoParamAttr(VariadicTypeInfoParamPayload)]
struct VariadicTypeInfoParamReflected
{
    value: s32
}

const VARIADIC_TYPE_INFO_PARAM_INFO = cast(const *TypeInfoStruct) #typeof(VariadicTypeInfoParamReflected)

#test
{
    @assert(@countof(VARIADIC_TYPE_INFO_PARAM_INFO.attributes) == 1)

    let attribute = VARIADIC_TYPE_INFO_PARAM_INFO.attributes[0]
    let value = cast(typeinfo) attribute.params[0].value

    @assert(attribute.type == #typeof(VariadicTypeInfoParamAttr))
    @assert(attribute.params[0].name == "value")
    @assert(value == VariadicTypeInfoParamPayload)
}
