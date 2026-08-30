#global private
using Swag

attr ReflectionMarker()
attr ReflectionTypeAttr(tag: s32, label: string)
attr DefaultedAttr(priority: s32, enabled: bool = true)
attr VariadicAttr(values: s32...)

#[AttrUsage(AttributeUsage.Variable)]
attr ParamReflectionAttr(name: string)

#[AttrUsage(AttributeUsage.StructVariable)]
attr FieldReflectionAttr(weight: s32)

#[AttrUsage(AttributeUsage.Enum)]
attr EnumReflectionAttr(label: string)

#[AttrUsage(AttributeUsage.EnumValue)]
attr EnumValueReflectionAttr(weight: s32)

#[AttrUsage(AttributeUsage.Struct)]
attr StructReflectionAttr(name: string)

#[StructReflectionAttr("demo")]
struct ReflectedStruct
{
    #[FieldReflectionAttr(11)]
    value: s32
}

#[EnumReflectionAttr("state")]
enum ReflectedEnum: u8
{
    #[EnumValueReflectionAttr(1)]
    First = 1

    #[EnumValueReflectionAttr(2)]
    Second = 2
}

#[ReflectionTypeAttr(7, "hello"), ReflectionMarker, DefaultedAttr(5), VariadicAttr(3, 5, 8)]
func reflectedFunction( #[ParamReflectionAttr("payload")]
value: s32) {}

const REFLECTED_FUNCTION_INFO = cast(const *Swag.TypeInfoFunc) #typeof(reflectedFunction)
const REFLECTED_STRUCT_INFO   = cast(const *Swag.TypeInfoStruct) #typeof(ReflectedStruct)
const REFLECTED_ENUM_INFO     = cast(const *Swag.TypeInfoEnum) #typeof(ReflectedEnum)

#test
{
    Swag.assert(REFLECTED_FUNCTION_INFO.attributes.count == 4)

    var foundTyped     = false
    var foundMarker    = false
    var foundDefaulted = false
    var foundVariadic  = false

    for attribute in REFLECTED_FUNCTION_INFO.attributes
    {
        if attribute.type == #typeof(ReflectionTypeAttr)
        {
            foundTyped = true
            Swag.assert(attribute.params.count == 2)
            let params = attribute.params!
            Swag.assert(params[0].name == "tag")
            Swag.assert(cast(s32) params[0].value == 7)
            Swag.assert(params[1].name == "label")
            Swag.assert(cast(#null string) params[1].value == "hello")
            continue
        }

        if attribute.type == #typeof(ReflectionMarker)
        {
            foundMarker = true
            Swag.assert(attribute.params.count == 0)
            continue
        }

        if attribute.type == #typeof(DefaultedAttr)
        {
            foundDefaulted = true
            Swag.assert(attribute.params.count == 2)
            let params = attribute.params!
            Swag.assert(params[0].name == "priority")
            Swag.assert(cast(s32) params[0].value == 5)
            Swag.assert(params[1].name == "enabled")
            Swag.assert(cast(bool) params[1].value)
            continue
        }

        if attribute.type == #typeof(VariadicAttr)
        {
            foundVariadic = true
            Swag.assert(attribute.params.count == 3)
            let params = attribute.params!
            Swag.assert(params[0].name == "values")
            Swag.assert(params[1].name == "values")
            Swag.assert(params[2].name == "values")
            Swag.assert(cast(s32) params[0].value == 3)
            Swag.assert(cast(s32) params[1].value == 5)
            Swag.assert(cast(s32) params[2].value == 8)
        }
    }

    Swag.assert(foundTyped)
    Swag.assert(foundMarker)
    Swag.assert(foundDefaulted)
    Swag.assert(foundVariadic)
}

#test
{
    Swag.assert(REFLECTED_FUNCTION_INFO.parameters.count == 1)

    var foundParamAttribute = false
    let parameters          = REFLECTED_FUNCTION_INFO.parameters!
    for attribute in parameters[0].attributes
    {
        if attribute.type != #typeof(ParamReflectionAttr) do
            continue

        foundParamAttribute = true
        Swag.assert(attribute.params.count == 1)
        let params = attribute.params!
        Swag.assert(params[0].name == "name")
        Swag.assert(cast(#null string) params[0].value == "payload")
    }

    Swag.assert(foundParamAttribute)
}

#test
{
    Swag.assert(REFLECTED_STRUCT_INFO.attributes.count == 1)

    let attribute = REFLECTED_STRUCT_INFO.attributes![0]
    Swag.assert(attribute.type == #typeof(StructReflectionAttr))
    Swag.assert(attribute.params.count == 1)
    let params = attribute.params!
    Swag.assert(params[0].name == "name")
    Swag.assert(cast(#null string) params[0].value == "demo")

    Swag.assert(REFLECTED_STRUCT_INFO.fields.count == 1)

    var foundFieldAttribute = false
    let fields              = REFLECTED_STRUCT_INFO.fields!
    for fieldAttribute in fields[0].attributes
    {
        if fieldAttribute.type != #typeof(FieldReflectionAttr) do
            continue

        foundFieldAttribute = true
        Swag.assert(fieldAttribute.params.count == 1)
        let fieldParams = fieldAttribute.params!
        Swag.assert(fieldParams[0].name == "weight")
        Swag.assert(cast(s32) fieldParams[0].value == 11)
    }

    Swag.assert(foundFieldAttribute)
}

#test
{
    Swag.assert(REFLECTED_ENUM_INFO.attributes.count == 1)
    Swag.assert(REFLECTED_ENUM_INFO.values.count == 2)

    let enumAttribute = REFLECTED_ENUM_INFO.attributes![0]
    Swag.assert(enumAttribute.type == #typeof(EnumReflectionAttr))
    Swag.assert(enumAttribute.params.count == 1)
    let enumParams = enumAttribute.params!
    Swag.assert(enumParams[0].name == "label")
    Swag.assert(cast(#null string) enumParams[0].value == "state")

    var foundFirstValueAttribute  = false
    var foundSecondValueAttribute = false
    for enumValue in REFLECTED_ENUM_INFO.values
    {
        for enumValueAttribute in enumValue.attributes
        {
            if enumValueAttribute.type != #typeof(EnumValueReflectionAttr) do
                continue

            Swag.assert(enumValueAttribute.params.count == 1)
            let valueParams = enumValueAttribute.params!
            Swag.assert(valueParams[0].name == "weight")

            if enumValue.name == "First"
            {
                foundFirstValueAttribute = true
                Swag.assert(cast(s32) valueParams[0].value == 1)
                continue
            }

            if enumValue.name == "Second"
            {
                foundSecondValueAttribute = true
                Swag.assert(cast(s32) valueParams[0].value == 2)
            }
        }
    }

    Swag.assert(foundFirstValueAttribute)
    Swag.assert(foundSecondValueAttribute)
}
