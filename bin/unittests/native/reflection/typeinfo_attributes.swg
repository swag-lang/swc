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
    @assert(@countof(REFLECTED_FUNCTION_INFO.attributes) == 4)

    var foundTyped     = false
    var foundMarker    = false
    var foundDefaulted = false
    var foundVariadic  = false

    for attribute in REFLECTED_FUNCTION_INFO.attributes
    {
        if attribute.type == #typeof(ReflectionTypeAttr)
        {
            foundTyped = true
            @assert(@countof(attribute.params) == 2)
            let params = notnull attribute.params
            @assert(params[0].name == "tag")
            @assert(cast(s32) params[0].value == 7)
            @assert(params[1].name == "label")
            @assert(cast(#null string) params[1].value == "hello")
            continue
        }

        if attribute.type == #typeof(ReflectionMarker)
        {
            foundMarker = true
            @assert(@countof(attribute.params) == 0)
            continue
        }

        if attribute.type == #typeof(DefaultedAttr)
        {
            foundDefaulted = true
            @assert(@countof(attribute.params) == 2)
            let params = notnull attribute.params
            @assert(params[0].name == "priority")
            @assert(cast(s32) params[0].value == 5)
            @assert(params[1].name == "enabled")
            @assert(cast(bool) params[1].value)
            continue
        }

        if attribute.type == #typeof(VariadicAttr)
        {
            foundVariadic = true
            @assert(@countof(attribute.params) == 3)
            let params = notnull attribute.params
            @assert(params[0].name == "values")
            @assert(params[1].name == "values")
            @assert(params[2].name == "values")
            @assert(cast(s32) params[0].value == 3)
            @assert(cast(s32) params[1].value == 5)
            @assert(cast(s32) params[2].value == 8)
        }
    }

    @assert(foundTyped)
    @assert(foundMarker)
    @assert(foundDefaulted)
    @assert(foundVariadic)
}

#test
{
    @assert(@countof(REFLECTED_FUNCTION_INFO.parameters) == 1)

    var foundParamAttribute = false
    let parameters = notnull REFLECTED_FUNCTION_INFO.parameters
    for attribute in parameters[0].attributes
    {
        if attribute.type != #typeof(ParamReflectionAttr) do
            continue

        foundParamAttribute = true
        @assert(@countof(attribute.params) == 1)
        let params = notnull attribute.params
        @assert(params[0].name == "name")
        @assert(cast(#null string) params[0].value == "payload")
    }

    @assert(foundParamAttribute)
}

#test
{
    @assert(@countof(REFLECTED_STRUCT_INFO.attributes) == 1)

    let attribute = (notnull REFLECTED_STRUCT_INFO.attributes)[0]
    @assert(attribute.type == #typeof(StructReflectionAttr))
    @assert(@countof(attribute.params) == 1)
    let params = notnull attribute.params
    @assert(params[0].name == "name")
    @assert(cast(#null string) params[0].value == "demo")

    @assert(@countof(REFLECTED_STRUCT_INFO.fields) == 1)

    var foundFieldAttribute = false
    let fields = notnull REFLECTED_STRUCT_INFO.fields
    for fieldAttribute in fields[0].attributes
    {
        if fieldAttribute.type != #typeof(FieldReflectionAttr) do
            continue

        foundFieldAttribute = true
        @assert(@countof(fieldAttribute.params) == 1)
        let fieldParams = notnull fieldAttribute.params
        @assert(fieldParams[0].name == "weight")
        @assert(cast(s32) fieldParams[0].value == 11)
    }

    @assert(foundFieldAttribute)
}

#test
{
    @assert(@countof(REFLECTED_ENUM_INFO.attributes) == 1)
    @assert(@countof(REFLECTED_ENUM_INFO.values) == 2)

    let enumAttribute = (notnull REFLECTED_ENUM_INFO.attributes)[0]
    @assert(enumAttribute.type == #typeof(EnumReflectionAttr))
    @assert(@countof(enumAttribute.params) == 1)
    let enumParams = notnull enumAttribute.params
    @assert(enumParams[0].name == "label")
    @assert(cast(#null string) enumParams[0].value == "state")

    var foundFirstValueAttribute  = false
    var foundSecondValueAttribute = false
    for enumValue in REFLECTED_ENUM_INFO.values
    {
        for enumValueAttribute in enumValue.attributes
        {
            if enumValueAttribute.type != #typeof(EnumValueReflectionAttr) do
                continue

            @assert(@countof(enumValueAttribute.params) == 1)
            let valueParams = notnull enumValueAttribute.params
            @assert(valueParams[0].name == "weight")

            if enumValue.name == "First"
            {
                foundFirstValueAttribute = true
                @assert(cast(s32) valueParams[0].value == 1)
                continue
            }

            if enumValue.name == "Second"
            {
                foundSecondValueAttribute = true
                @assert(cast(s32) valueParams[0].value == 2)
            }
        }
    }

    @assert(foundFirstValueAttribute)
    @assert(foundSecondValueAttribute)
}
