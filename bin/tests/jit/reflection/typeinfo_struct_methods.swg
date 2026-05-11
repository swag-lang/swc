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

var RuntimeMethodReflectionCalls: s32

func hasExpectedMethodReflection(type: typeinfo, expectedCount: s32, expectedName: string)->bool
{
    RuntimeMethodReflectionCalls += 1

    let info = cast(const *Swag.TypeInfoStruct) type
    if @countof(info.methods) != expectedCount do
        return false

    if expectedCount == 0 do
        return true

    return info.methods[0].name == expectedName and
           info.methods[0].pointedType.kind == .Func
}

func runtimeMethodReflectionWorks()->bool
{
    RuntimeMethodReflectionCalls = 0

    var result = true
    result = hasExpectedMethodReflection(#typeof(SimpleMethodProbe), 1, "ping") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe), 0, "") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe's32), 1, "copyFrom") and result
    return result and RuntimeMethodReflectionCalls == 3
}

#test
{
    @assert(runtimeMethodReflectionWorks())
}
