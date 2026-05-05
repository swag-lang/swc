#global fileprivate
using Swag

struct StoredDefaultPair
{
    left: s16
    right: s16
}

const STORED_DEFAULT_TYPE = #typeof(StoredDefaultPair{left: 1, right: 2})

#[AttrUsage(AttributeUsage.Struct)]
attr StoredDefaultTypeAttr(t: typeinfo = STORED_DEFAULT_TYPE)

#[StoredDefaultTypeAttr]
struct ReflectedStoredDefaultType
{
    value: s32
}

const REFLECTED_STORED_DEFAULT_INFO = cast(const *TypeInfoStruct) #typeof(ReflectedStoredDefaultType)

#test
{
    @assert(@countof(REFLECTED_STORED_DEFAULT_INFO.attributes) == 1)

    let attribute = REFLECTED_STORED_DEFAULT_INFO.attributes[0]
    let value = cast(typeinfo) attribute.params[0].value

    @assert(attribute.params[0].name == "t")
    @assert(value == StoredDefaultPair)
}
