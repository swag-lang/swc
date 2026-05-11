#global fileprivate
using Swag

alias SimplePingFn = func(const &SimpleMethodProbe)->s32
alias GenericCopyFromFn = func(&GenericMethodProbe's32, const [..] s32)->s32

struct SimpleMethodProbe
{
    value: s32
}

impl SimpleMethodProbe
{
    mtd const ping()->s32
    {
        return .value + 1
    }

    #[Macro]
    mtd visitMacro(stmt: #code void)
    {
        #inject(stmt)
    }
}

struct(T) GenericMethodProbe
{
    value: T
}

impl GenericMethodProbe
{
    mtd copyFrom(values: const [..] T)->T
    {
        .value = values[0]
        return .value
    }
}

var RuntimeMethodReflectionCalls: s32
var RuntimeMethodPointerCalls: s32

func hasExpectedMethodReflection(type: typeinfo, expectedCount: s32, expectedName: string)->bool
{
    RuntimeMethodReflectionCalls += 1

    let info = cast(const *Swag.TypeInfoStruct) type
    if @countof(info.methods) != expectedCount do
        return false

    if expectedCount == 0 do
        return true

    return info.methods[0].name == expectedName and
           info.methods[0].pointedType.kind == .Func and
           info.methods[0].value != null
}

func callReflectedSimpleMethod(type: typeinfo, seed: s32)->bool
{
    let info = cast(const *Swag.TypeInfoStruct) type
    if @countof(info.methods) != 1 do
        return false

    let methodInfo = info.methods[0]
    let methodType = cast(const *Swag.TypeInfoFunc) methodInfo.pointedType
    if methodInfo.name != "ping" or
       methodInfo.pointedType.kind != .Func or
       @countof(methodType.parameters) != 1 or
       methodType.parameters[0].pointedType != #type const &SimpleMethodProbe or
       methodType.returnType != s32 or
       methodInfo.value == null do
        return false

    var probe: SimpleMethodProbe = {value: seed}
    let method = cast(SimplePingFn) methodInfo.value
    let result = method(&probe)
    RuntimeMethodPointerCalls += 1
    return result == seed + 1
}

func callReflectedGenericMethod(type: typeinfo, start: s32, next: s32)->bool
{
    let info = cast(const *Swag.TypeInfoStruct) type
    if @countof(info.methods) != 1 do
        return false

    let methodInfo = info.methods[0]
    let methodType = cast(const *Swag.TypeInfoFunc) methodInfo.pointedType
    if methodInfo.name != "copyFrom" or
       methodInfo.pointedType.kind != .Func or
       @countof(methodType.parameters) != 2 or
       methodType.parameters[0].pointedType != #type &GenericMethodProbe's32 or
       methodType.parameters[1].pointedType != #type const [..] s32 or
       methodType.returnType != s32 or
       methodInfo.value == null do
        return false

    var probe: GenericMethodProbe's32 = {value: start}
    let values = [next, start]
    let method = cast(GenericCopyFromFn) methodInfo.value
    let result = method(&probe, values)
    RuntimeMethodPointerCalls += 1
    return result == next and probe.value == next
}

func runtimeMethodReflectionWorks()->bool
{
    RuntimeMethodReflectionCalls = 0
    RuntimeMethodPointerCalls    = 0

    var result = true
    result = hasExpectedMethodReflection(#typeof(SimpleMethodProbe), 1, "ping") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe), 0, "") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe's32), 1, "copyFrom") and result
    result = callReflectedSimpleMethod(#typeof(SimpleMethodProbe), 41) and result
    result = callReflectedGenericMethod(#typeof(GenericMethodProbe's32), 1, 17) and result
    return result and RuntimeMethodReflectionCalls == 3 and RuntimeMethodPointerCalls == 2
}

#test
{
    @assert(runtimeMethodReflectionWorks())
}
