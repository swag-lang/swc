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

const SIMPLE_INFO        = cast(const *Swag.TypeInfoStruct) #typeof(SimpleMethodProbe)
const GENERIC_INFO       = cast(const *Swag.TypeInfoStruct) #typeof(GenericMethodProbe)
const ARRAY_INFO         = cast(const *Swag.TypeInfoStruct) #typeof(GenericMethodProbe's32)
const SIMPLE_METHOD_INFO = SIMPLE_INFO.methods[0]
const ARRAY_METHOD_INFO  = ARRAY_INFO.methods[0]
const SIMPLE_METHOD_TYPE = cast(const *Swag.TypeInfoFunc) SIMPLE_METHOD_INFO.pointedType
const ARRAY_METHOD_TYPE  = cast(const *Swag.TypeInfoFunc) ARRAY_METHOD_INFO.pointedType

func hasExpectedMethodReflection(type: typeinfo, expectedCount: s32, expectedName: string)->bool
{
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
    return method(&probe) == seed + 1
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
    return result == next and probe.value == next
}

func compileTimeMethodReflectionWorks()->bool
{
    var result = true
    result = hasExpectedMethodReflection(#typeof(SimpleMethodProbe), 1, "ping") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe), 0, "") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe's32), 1, "copyFrom") and result
    result = callReflectedSimpleMethod(#typeof(SimpleMethodProbe), 41) and result
    result = callReflectedGenericMethod(#typeof(GenericMethodProbe's32), 1, 17) and result
    return result
}

const COMPILE_TIME_METHOD_REFLECTION_OK = #run compileTimeMethodReflectionWorks()

#assert(@countof(SIMPLE_INFO.methods) == 1)
#assert(SIMPLE_METHOD_INFO.name == "ping")
#assert(SIMPLE_METHOD_INFO.pointedType.kind == .Func)
#assert(@countof(SIMPLE_METHOD_TYPE.parameters) == 1)
#assert(SIMPLE_METHOD_TYPE.parameters[0].pointedType == #type const &SimpleMethodProbe)
#assert(SIMPLE_METHOD_TYPE.returnType == s32)

#assert(GENERIC_INFO.name == "GenericMethodProbe")
#assert(@countof(GENERIC_INFO.methods) == 0)

#assert(@countof(ARRAY_INFO.methods) == 1)
#assert(ARRAY_METHOD_INFO.name == "copyFrom")
#assert(ARRAY_METHOD_INFO.pointedType.kind == .Func)
#assert(@countof(ARRAY_METHOD_TYPE.parameters) == 2)
#assert(ARRAY_METHOD_TYPE.parameters[0].pointedType == #type &GenericMethodProbe's32)
#assert(ARRAY_METHOD_TYPE.parameters[1].pointedType == #type const [..] s32)
#assert(ARRAY_METHOD_TYPE.returnType == s32)
#assert(COMPILE_TIME_METHOD_REFLECTION_OK)
