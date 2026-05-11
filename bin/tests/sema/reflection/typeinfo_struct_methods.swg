#global fileprivate
using Swag

alias SimplePingFn = func(const &SimpleMethodProbe)->s32
alias GenericCopyFromFn = func(&GenericMethodProbe's32, const [..] s32)->s32
alias ExportedScaleValueFn = func(s32, s32)->s32
alias ExportedAddFn = func(&ExportedMethodProbe, s32)->s32
alias ExportedScaledFn = func(const &ExportedMethodProbe, s32)->s32
alias ExportedScoreFn = func(&ExportedMethodProbe, s32)->s32

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

interface IExportedMethodScore
{
    mtd score(bonus: s32)->s32;
}

struct ExportedMethodProbe
{
    value: s32
}

impl ExportedMethodProbe
{
    func scaleValue(value, factor: s32)->s32
    {
        return value * factor
    }

    mtd add(delta: s32)->s32
    {
        .value += delta
        return .value
    }

    mtd const scaled(factor: s32)->s32
    {
        return .value * factor
    }

    #[Mixin]
    func injectStmt(stmt: #code void)
    {
        #inject(stmt)
    }

    #[Compiler]
    func compilerOnly()->s32
    {
        return 77
    }
}

impl IExportedMethodScore for ExportedMethodProbe
{
    mtd impl score(bonus: s32)->s32
    {
        return .value + bonus
    }
}

const SIMPLE_INFO        = cast(const *Swag.TypeInfoStruct) #typeof(SimpleMethodProbe)
const GENERIC_INFO       = cast(const *Swag.TypeInfoStruct) #typeof(GenericMethodProbe)
const ARRAY_INFO         = cast(const *Swag.TypeInfoStruct) #typeof(GenericMethodProbe's32)
const EXPORTED_INFO      = cast(const *Swag.TypeInfoStruct) #typeof(ExportedMethodProbe)
const SIMPLE_METHOD_INFO = SIMPLE_INFO.methods[0]
const ARRAY_METHOD_INFO  = ARRAY_INFO.methods[0]
const EXPORTED_SCALE_INFO  = EXPORTED_INFO.methods[0]
const EXPORTED_ADD_INFO    = EXPORTED_INFO.methods[1]
const EXPORTED_SCALED_INFO = EXPORTED_INFO.methods[2]
const EXPORTED_SCORE_INFO  = EXPORTED_INFO.methods[3]
const SIMPLE_METHOD_TYPE = cast(const *Swag.TypeInfoFunc) SIMPLE_METHOD_INFO.pointedType
const ARRAY_METHOD_TYPE  = cast(const *Swag.TypeInfoFunc) ARRAY_METHOD_INFO.pointedType
const EXPORTED_SCALE_TYPE  = cast(const *Swag.TypeInfoFunc) EXPORTED_SCALE_INFO.pointedType
const EXPORTED_ADD_TYPE    = cast(const *Swag.TypeInfoFunc) EXPORTED_ADD_INFO.pointedType
const EXPORTED_SCALED_TYPE = cast(const *Swag.TypeInfoFunc) EXPORTED_SCALED_INFO.pointedType
const EXPORTED_SCORE_TYPE  = cast(const *Swag.TypeInfoFunc) EXPORTED_SCORE_INFO.pointedType

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

func hasMethodNamed(type: typeinfo, expectedName: string)->bool
{
    let info = cast(const *Swag.TypeInfoStruct) type
    foreach &methodInfo in info.methods
    {
        if methodInfo.name == expectedName do
            return true
    }

    return false
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

func callReflectedExportedMethods(type: typeinfo, seed: s32)->bool
{
    let info = cast(const *Swag.TypeInfoStruct) type
    if @countof(info.methods) != 4 do
        return false

    let scaleInfo = info.methods[0]
    let addInfo = info.methods[1]
    let scaledInfo = info.methods[2]
    let scoreInfo = info.methods[3]

    let scaleType = cast(const *Swag.TypeInfoFunc) scaleInfo.pointedType
    let addType = cast(const *Swag.TypeInfoFunc) addInfo.pointedType
    let scaledType = cast(const *Swag.TypeInfoFunc) scaledInfo.pointedType
    let scoreType = cast(const *Swag.TypeInfoFunc) scoreInfo.pointedType

    if scaleInfo.name != "scaleValue" or
       scaleInfo.pointedType.kind != .Func or
       @countof(scaleType.parameters) != 2 or
       scaleType.parameters[0].pointedType != s32 or
       scaleType.parameters[1].pointedType != s32 or
       scaleType.returnType != s32 or
       scaleInfo.value == null do
        return false

    if addInfo.name != "add" or
       addInfo.pointedType.kind != .Func or
       @countof(addType.parameters) != 2 or
       addType.parameters[0].pointedType != #type &ExportedMethodProbe or
       addType.parameters[1].pointedType != s32 or
       addType.returnType != s32 or
       addInfo.value == null do
        return false

    if scaledInfo.name != "scaled" or
       scaledInfo.pointedType.kind != .Func or
       @countof(scaledType.parameters) != 2 or
       scaledType.parameters[0].pointedType != #type const &ExportedMethodProbe or
       scaledType.parameters[1].pointedType != s32 or
       scaledType.returnType != s32 or
       scaledInfo.value == null do
        return false

    if scoreInfo.name != "score" or
       scoreInfo.pointedType.kind != .Func or
       @countof(scoreType.parameters) != 2 or
       scoreType.parameters[0].pointedType != #type &ExportedMethodProbe or
       scoreType.parameters[1].pointedType != s32 or
       scoreType.returnType != s32 or
       scoreInfo.value == null do
        return false

    let scaleValue = cast(ExportedScaleValueFn) scaleInfo.value
    if scaleValue(seed, 3) != seed * 3 do
        return false

    var probe: ExportedMethodProbe = {value: seed}

    let add = cast(ExportedAddFn) addInfo.value
    if add(&probe, 5) != seed + 5 or probe.value != seed + 5 do
        return false

    let scaled = cast(ExportedScaledFn) scaledInfo.value
    if scaled(&probe, 2) != (seed + 5) * 2 do
        return false

    let score = cast(ExportedScoreFn) scoreInfo.value
    if score(&probe, 7) != seed + 12 do
        return false

    return !hasMethodNamed(type, "injectStmt") and !hasMethodNamed(type, "compilerOnly")
}

func compileTimeMethodReflectionWorks()->bool
{
    var result = true
    result = hasExpectedMethodReflection(#typeof(SimpleMethodProbe), 1, "ping") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe), 0, "") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe's32), 1, "copyFrom") and result
    result = hasExpectedMethodReflection(#typeof(ExportedMethodProbe), 4, "scaleValue") and result
    result = callReflectedSimpleMethod(#typeof(SimpleMethodProbe), 41) and result
    result = callReflectedGenericMethod(#typeof(GenericMethodProbe's32), 1, 17) and result
    result = callReflectedExportedMethods(#typeof(ExportedMethodProbe), 10) and result
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

#assert(@countof(EXPORTED_INFO.methods) == 4)
#assert(EXPORTED_SCALE_INFO.name == "scaleValue")
#assert(EXPORTED_SCALE_INFO.pointedType.kind == .Func)
#assert(@countof(EXPORTED_SCALE_TYPE.parameters) == 2)
#assert(EXPORTED_SCALE_TYPE.parameters[0].pointedType == s32)
#assert(EXPORTED_SCALE_TYPE.parameters[1].pointedType == s32)
#assert(EXPORTED_SCALE_TYPE.returnType == s32)

#assert(EXPORTED_ADD_INFO.name == "add")
#assert(EXPORTED_ADD_INFO.pointedType.kind == .Func)
#assert(@countof(EXPORTED_ADD_TYPE.parameters) == 2)
#assert(EXPORTED_ADD_TYPE.parameters[0].pointedType == #type &ExportedMethodProbe)
#assert(EXPORTED_ADD_TYPE.parameters[1].pointedType == s32)
#assert(EXPORTED_ADD_TYPE.returnType == s32)

#assert(EXPORTED_SCALED_INFO.name == "scaled")
#assert(EXPORTED_SCALED_INFO.pointedType.kind == .Func)
#assert(@countof(EXPORTED_SCALED_TYPE.parameters) == 2)
#assert(EXPORTED_SCALED_TYPE.parameters[0].pointedType == #type const &ExportedMethodProbe)
#assert(EXPORTED_SCALED_TYPE.parameters[1].pointedType == s32)
#assert(EXPORTED_SCALED_TYPE.returnType == s32)

#assert(EXPORTED_SCORE_INFO.name == "score")
#assert(EXPORTED_SCORE_INFO.pointedType.kind == .Func)
#assert(@countof(EXPORTED_SCORE_TYPE.parameters) == 2)
#assert(EXPORTED_SCORE_TYPE.parameters[0].pointedType == #type &ExportedMethodProbe)
#assert(EXPORTED_SCORE_TYPE.parameters[1].pointedType == s32)
#assert(EXPORTED_SCORE_TYPE.returnType == s32)

#assert(!hasMethodNamed(#typeof(ExportedMethodProbe), "injectStmt"))
#assert(!hasMethodNamed(#typeof(ExportedMethodProbe), "compilerOnly"))
#assert(COMPILE_TIME_METHOD_REFLECTION_OK)
