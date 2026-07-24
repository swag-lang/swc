#global private
using Swag

alias SimplePingFn = func(const &SimpleMethodProbe)->s32
alias GenericCopyFromFn = func(&GenericMethodProbe's32, const [..] s32)->s32
alias ExportedScaleValueFn = func(s32, s32)->s32
alias ExportedAddFn = func(&ExportedMethodProbe, s32)->s32
alias ExportedScaledFn = func(const &ExportedMethodProbe, s32)->s32
alias ExportedScoreFn = func(&ExportedMethodProbe, s32)->s32

struct HiddenMethodProbe
{
    value: s32
}

impl HiddenMethodProbe
{
    mtd hidden()->s32
    {
        return .value
    }
}

#[Swag.ExportType(.Methods)]
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
    mtd visitMacro(stmt: #code)
    {
        #inject(stmt)
    }
}

#[Swag.ExportType(.Methods)]
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

#[Swag.ExportType(.Methods)]
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
    func injectStmt(stmt: #code)
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

var RuntimeMethodReflectionCalls: s32
var RuntimeMethodPointerCalls:    s32

func hasExpectedMethodReflection(type: typeinfo, expectedCount: s32, expectedName: string)->bool
{
    RuntimeMethodReflectionCalls += 1

    let info = cast(const *Swag.TypeInfoStruct) type
    if @countof(info.methods) != expectedCount do
        return false

    if expectedCount == 0 do
        return true

    let methods = notnull info.methods
    let m0Type  = methods[0].pointedType
    return methods[0].name == expectedName and
           m0Type != null and m0Type.kind == .Func and
           methods[0].value != null
}

func hasMethodNamed(type: typeinfo, expectedName: string)->bool
{
    let info = cast(const *Swag.TypeInfoStruct) type
    for &methodInfo in info.methods
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

    let methodInfo = (notnull info.methods)[0]
    let methodType = cast(#null const *Swag.TypeInfoFunc) methodInfo.pointedType
    if methodType == null do
        return false
    let params = methodType.parameters
    if methodInfo.name != "ping" or
       methodType.kind != .Func or
       params == null or
       @countof(params) != 1 or
       params[0].pointedType != #type const &SimpleMethodProbe or
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

    let methodInfo = (notnull info.methods)[0]
    let methodType = cast(#null const *Swag.TypeInfoFunc) methodInfo.pointedType
    if methodType == null do
        return false
    let params = methodType.parameters
    if methodInfo.name != "copyFrom" or
       methodType.kind != .Func or
       params == null or
       @countof(params) != 2 or
       params[0].pointedType != #type &GenericMethodProbe's32 or
       params[1].pointedType != #type const [..] s32 or
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

func callReflectedExportedMethods(type: typeinfo, seed: s32)->bool
{
    let info = cast(const *Swag.TypeInfoStruct) type
    if @countof(info.methods) != 4 do
        return false

    let methods    = notnull info.methods
    let scaleInfo  = methods[0]
    let addInfo    = methods[1]
    let scaledInfo = methods[2]
    let scoreInfo  = methods[3]

    let scaleType  = cast(#null const *Swag.TypeInfoFunc) scaleInfo.pointedType
    let addType    = cast(#null const *Swag.TypeInfoFunc) addInfo.pointedType
    let scaledType = cast(#null const *Swag.TypeInfoFunc) scaledInfo.pointedType
    let scoreType  = cast(#null const *Swag.TypeInfoFunc) scoreInfo.pointedType
    if scaleType == null or addType == null or scaledType == null or scoreType == null do
        return false

    let scaleParams = scaleType.parameters
    if scaleInfo.name != "scaleValue" or
       scaleType.kind != .Func or
       scaleParams == null or
       @countof(scaleParams) != 2 or
       scaleParams[0].pointedType != s32 or
       scaleParams[1].pointedType != s32 or
       scaleType.returnType != s32 or
       scaleInfo.value == null do
        return false

    let addParams = addType.parameters
    if addInfo.name != "add" or
       addType.kind != .Func or
       addParams == null or
       @countof(addParams) != 2 or
       addParams[0].pointedType != #type &ExportedMethodProbe or
       addParams[1].pointedType != s32 or
       addType.returnType != s32 or
       addInfo.value == null do
        return false

    let scaledParams = scaledType.parameters
    if scaledInfo.name != "scaled" or
       scaledType.kind != .Func or
       scaledParams == null or
       @countof(scaledParams) != 2 or
       scaledParams[0].pointedType != #type const &ExportedMethodProbe or
       scaledParams[1].pointedType != s32 or
       scaledType.returnType != s32 or
       scaledInfo.value == null do
        return false

    let scoreParams = scoreType.parameters
    if scoreInfo.name != "score" or
       scoreType.kind != .Func or
       scoreParams == null or
       @countof(scoreParams) != 2 or
       scoreParams[0].pointedType != #type &ExportedMethodProbe or
       scoreParams[1].pointedType != s32 or
       scoreType.returnType != s32 or
       scoreInfo.value == null do
        return false

    let scaleValue = cast(ExportedScaleValueFn) scaleInfo.value
    if scaleValue(seed, 3) != seed * 3 do
        return false
    RuntimeMethodPointerCalls += 1

    var probe: ExportedMethodProbe = {value: seed}

    let add = cast(ExportedAddFn) addInfo.value
    if add(&probe, 5) != seed + 5 or probe.value != seed + 5 do
        return false
    RuntimeMethodPointerCalls += 1

    let scaled = cast(ExportedScaledFn) scaledInfo.value
    if scaled(&probe, 2) != (seed + 5) * 2 do
        return false
    RuntimeMethodPointerCalls += 1

    let score = cast(ExportedScoreFn) scoreInfo.value
    if score(&probe, 7) != seed + 12 do
        return false
    RuntimeMethodPointerCalls += 1

    return !hasMethodNamed(type, "injectStmt") and !hasMethodNamed(type, "compilerOnly")
}

func runtimeMethodReflectionWorks()->bool
{
    RuntimeMethodReflectionCalls = 0
    RuntimeMethodPointerCalls    = 0

    var result = true
    result = hasExpectedMethodReflection(#typeof(HiddenMethodProbe), 0, "") and result
    result = hasExpectedMethodReflection(#typeof(SimpleMethodProbe), 1, "ping") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe), 0, "") and result
    result = hasExpectedMethodReflection(#typeof(GenericMethodProbe's32), 1, "copyFrom") and result
    result = hasExpectedMethodReflection(#typeof(ExportedMethodProbe), 4, "scaleValue") and result
    result = callReflectedSimpleMethod(#typeof(SimpleMethodProbe), 41) and result
    result = callReflectedGenericMethod(#typeof(GenericMethodProbe's32), 1, 17) and result
    result = callReflectedExportedMethods(#typeof(ExportedMethodProbe), 10) and result
    return result and RuntimeMethodReflectionCalls == 5 and RuntimeMethodPointerCalls == 6
}

#test
{
    @assert(runtimeMethodReflectionWorks())
}
