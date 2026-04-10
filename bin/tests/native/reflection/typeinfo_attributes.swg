#global fileprivate
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
func reflectedFunction(#[ParamReflectionAttr("payload")] value: s32)
{
}

#test
{
    let type = cast(const *Swag.TypeInfoFunc) #typeof(reflectedFunction)
    @assert(@countof(type.attributes) == 4)

    var foundTyped     = false
    var foundMarker    = false
    var foundDefaulted = false
    var foundVariadic  = false

    foreach attribute in type.attributes
    {
        if attribute.type == #typeof(ReflectionTypeAttr)
        {
            foundTyped = true
            @assert(@countof(attribute.params) == 2)
            @assert(attribute.params[0].name == "tag")
            @assert(cast(s32) attribute.params[0].value == 7)
            @assert(attribute.params[1].name == "label")
            @assert(cast(string) attribute.params[1].value == "hello")
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
            @assert(attribute.params[0].name == "priority")
            @assert(cast(s32) attribute.params[0].value == 5)
            @assert(attribute.params[1].name == "enabled")
            @assert(cast(bool) attribute.params[1].value)
            continue
        }

        if attribute.type == #typeof(VariadicAttr)
        {
            foundVariadic = true
            @assert(@countof(attribute.params) == 3)
            @assert(attribute.params[0].name == "values")
            @assert(attribute.params[1].name == "values")
            @assert(attribute.params[2].name == "values")
            @assert(cast(s32) attribute.params[0].value == 3)
            @assert(cast(s32) attribute.params[1].value == 5)
            @assert(cast(s32) attribute.params[2].value == 8)
        }
    }

    @assert(foundTyped)
    @assert(foundMarker)
    @assert(foundDefaulted)
    @assert(foundVariadic)
}

#test
{
    let type = cast(const *Swag.TypeInfoFunc) #typeof(reflectedFunction)
    @assert(@countof(type.parameters) == 1)

    var foundParamAttribute = false
    foreach attribute in type.parameters[0].attributes
    {
        if attribute.type != #typeof(ParamReflectionAttr) do
            continue

        foundParamAttribute = true
        @assert(@countof(attribute.params) == 1)
        @assert(attribute.params[0].name == "name")
        @assert(cast(string) attribute.params[0].value == "payload")
    }

    @assert(foundParamAttribute)
}

#test
{
    let type = cast(const *Swag.TypeInfoStruct) #typeof(ReflectedStruct)
    @assert(@countof(type.attributes) == 1)

    let attribute = type.attributes[0]
    @assert(attribute.type == #typeof(StructReflectionAttr))
    @assert(@countof(attribute.params) == 1)
    @assert(attribute.params[0].name == "name")
    @assert(cast(string) attribute.params[0].value == "demo")

    @assert(@countof(type.fields) == 1)

    var foundFieldAttribute = false
    foreach fieldAttribute in type.fields[0].attributes
    {
        if fieldAttribute.type != #typeof(FieldReflectionAttr) do
            continue

        foundFieldAttribute = true
        @assert(@countof(fieldAttribute.params) == 1)
        @assert(fieldAttribute.params[0].name == "weight")
        @assert(cast(s32) fieldAttribute.params[0].value == 11)
    }

    @assert(foundFieldAttribute)
}

#test
{
    let type = cast(const *Swag.TypeInfoEnum) #typeof(ReflectedEnum)
    @assert(@countof(type.attributes) == 1)
    @assert(@countof(type.values) == 2)

    let enumAttribute = type.attributes[0]
    @assert(enumAttribute.type == #typeof(EnumReflectionAttr))
    @assert(@countof(enumAttribute.params) == 1)
    @assert(enumAttribute.params[0].name == "label")
    @assert(cast(string) enumAttribute.params[0].value == "state")

    var foundFirstValueAttribute  = false
    var foundSecondValueAttribute = false
    foreach enumValue in type.values
    {
        foreach enumValueAttribute in enumValue.attributes
        {
            if enumValueAttribute.type != #typeof(EnumValueReflectionAttr) do
                continue

            @assert(@countof(enumValueAttribute.params) == 1)
            @assert(enumValueAttribute.params[0].name == "weight")

            if enumValue.name == "First"
            {
                foundFirstValueAttribute = true
                @assert(cast(s32) enumValueAttribute.params[0].value == 1)
                continue
            }

            if enumValue.name == "Second"
            {
                foundSecondValueAttribute = true
                @assert(cast(s32) enumValueAttribute.params[0].value == 2)
            }
        }
    }

    @assert(foundFirstValueAttribute)
    @assert(foundSecondValueAttribute)
}
