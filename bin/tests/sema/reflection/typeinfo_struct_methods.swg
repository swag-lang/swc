#global fileprivate
using Swag

struct SimpleMethodProbe
{
    value: s32
}

impl SimpleMethodProbe
{
    mtd ping()->s32
    {
        return .value + 1
    }
}

struct(T) GenericMethodProbe
{
    value: T
}

impl GenericMethodProbe
{
    mtd copyFrom(values: const [..] T)
    {
        discard values
    }
}

const SIMPLE_INFO  = cast(const *Swag.TypeInfoStruct) #typeof(SimpleMethodProbe)
const GENERIC_INFO = cast(const *Swag.TypeInfoStruct) #typeof(GenericMethodProbe)
const ARRAY_INFO   = cast(const *Swag.TypeInfoStruct) #typeof(GenericMethodProbe's32)

#assert(@countof(SIMPLE_INFO.methods) == 1)
#assert(SIMPLE_INFO.methods[0].name == "ping")
#assert(SIMPLE_INFO.methods[0].pointedType.kind == .Func)

#assert(GENERIC_INFO.name == "GenericMethodProbe")

#assert(@countof(ARRAY_INFO.methods) == 1)
#assert(ARRAY_INFO.methods[0].name == "copyFrom")
#assert(ARRAY_INFO.methods[0].pointedType.kind == .Func)
