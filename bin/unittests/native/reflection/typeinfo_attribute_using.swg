#global private
using Swag

struct AttributeUsingScope {}

impl AttributeUsingScope
{
    #[AttrUsage(AttributeUsage.StructVariable)]
    attr ScopedLabel(value: string)
}

#[Swag.Using(AttributeUsingScope)]
struct AttributeUsingRecord
{
    {
        #[ScopedLabel("grouped")]
        grouped = 1
    }

    #[ScopedLabel("direct")]
    direct: s32
}

const ATTRIBUTE_USING_INFO = cast(const *Swag.TypeInfoStruct) #typeof(AttributeUsingRecord)

#test
{
    @assert(@countof(ATTRIBUTE_USING_INFO.fields) == 2)

    var foundGrouped = false
    var foundDirect  = false

    for field in ATTRIBUTE_USING_INFO.fields
    {
        for attribute in field.attributes
        {
            if attribute.type != #typeof(AttributeUsingScope.ScopedLabel) do
                continue

            @assert(@countof(attribute.params) == 1)
            @assert(attribute.params[0].name == "value")

            if field.name == "grouped"
            {
                foundGrouped = true
                @assert(cast(#null string) attribute.params[0].value == "grouped")
            }

            if field.name == "direct"
            {
                foundDirect = true
                @assert(cast(#null string) attribute.params[0].value == "direct")
            }
        }
    }

    @assert(foundGrouped)
    @assert(foundDirect)
}
