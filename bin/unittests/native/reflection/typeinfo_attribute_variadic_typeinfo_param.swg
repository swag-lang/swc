#global private
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
    Swag.assert(VARIADIC_TYPE_INFO_PARAM_INFO.attributes.count == 1)

    let attribute = VARIADIC_TYPE_INFO_PARAM_INFO.attributes[0]
    let value     = cast(#null typeinfo) attribute.params[0].value

    Swag.assert(attribute.type == #typeof(VariadicTypeInfoParamAttr))
    Swag.assert(attribute.params[0].name == "value")
    Swag.assert(value == VariadicTypeInfoParamPayload)
}
