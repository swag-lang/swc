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
