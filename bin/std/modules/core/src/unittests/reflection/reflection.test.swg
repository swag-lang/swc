#global if #command == Swag.CompilerCommand.Test
#global private

attr TypeMeta(label: string, priority: s32 = 0)
attr FieldMeta(fieldAlias: string, rank: s32 = 0)
attr FuncMeta(label: string, arity: s32 = 0)
attr EnumMeta(label: string)

#[TypeMeta("probe", 3)]
#[Swag.ExportType(.Methods)]
struct ReflectionProbe
{
    #[FieldMeta("primary", 7)]
    x: s32 = 1

    #[FieldMeta("switch")]
    enabled: bool = true

    label: string = "seed"
}

impl ReflectionProbe
{
    mtd ping()->s32
    {
        return .x + 1
    }

    #[Macro]
    mtd visitMacro(stmt: #code)
    {
        #inject(stmt)
    }
}

alias ReflectionProbePingFn = func(&ReflectionProbe)->s32

struct PodProbe
{
    value: s32
}

struct LifecycleProbe
{
    value: s32
}

struct CopyProbe
{
    value:  s32
    copied: bool
}

interface IReflectionScore
{
    mtd score()->s32
}

struct InterfaceProbe
{
    value: s32 = 9
}

impl IReflectionScore for InterfaceProbe
{
    mtd impl score()->s32 => .value
}

#[EnumMeta("state")]
enum ProbeState: u32
{
    Idle
    Busy
    Done
}

#[Swag.EnumFlags]
#[EnumMeta("flags")]
enum ProbeFlags: u32
{
    Read  = 1
    Write = 2
    Exec  = 4
}

alias ReflectionProbeAlias  = ReflectionProbe
alias ReflectionProbeAlias2 = ReflectionProbeAlias
var ReflectionRuntimeMethodCalls:  s32
var ReflectionRuntimePointerCalls: s32

#[FuncMeta("repeat", 2)]
func(T, N: s32) makeRepeated(value: T)->[N] T
{
    var result: [N] T
    for [i] in N do
        result[i] = value
    return result
}

impl LifecycleProbe
{
    mtd opDrop() {}
    mtd opPostCopy() {}
    mtd opPostMove() {}
}

impl CopyProbe
{
    mtd opPostCopy()
    {
        .copied = true
    }
}

func runtimeMethodReflectionWorks(type: typeinfo, seed: s32)->bool
{
    ReflectionRuntimeMethodCalls += 1

    let method = Reflection.findMethod(type, "ping")
    if method == null do
        return false

    let pointedType = method.pointedType!
    let methodType  = cast(const *Swag.TypeInfoFunc) pointedType
    if method.name != "ping" or
       pointedType.kind != .Func or
       @countof(methodType.parameters) != 1 or
       methodType.parameters![0].pointedType != #type &ReflectionProbe or
       methodType.returnType != s32 or
       method.value == null or
       Reflection.findMethod(type, "visitMacro") != null do
        return false

    var probe: ReflectionProbe = {x: seed}
    let ping                   = cast(ReflectionProbePingFn) method.value!
    let result                 = ping(&probe)
    ReflectionRuntimePointerCalls += 1
    return result == seed + 1
}

#test
{
    let type = #typeof(ReflectionProbe)
    @assert(Reflection.isNamedStruct(type, "ReflectionProbe"))
    @assert(!Reflection.isNamedStruct(type, "Other"))

    let fieldX = Reflection.findField(type, "x")!
    @assert(fieldX.name == "x")
    @assert(fieldX.pointedType == s32)
    @assert(Reflection.findField(type, "missing") == null)
}

#test
{
    let type         = #typeof(ReflectionProbe)
    let fieldX       = Reflection.findField(type, "x")
    let fieldEnabled = Reflection.findField(type, "enabled")
    let typeStruct   = cast(const *Swag.TypeInfoStruct) type

    @assert(cast(#null string) Reflection.attributeValue(type, TypeMeta, "label") == "probe")
    @assert(cast(s32) Reflection.attributeValue(type, TypeMeta, "priority") == 3)
    for &it in typeStruct.fields where it.name == "x"
    {
        @assert(Reflection.hasAttribute(it, FieldMeta))
        let attrib = Reflection.attribute(it, FieldMeta)!
        let params = attrib.params!
        @assert(@countof(params) == 2)
        @assert(params[0].name == "fieldAlias")
        @assert(params[1].name == "rank")
        @assert(cast(#null string) params[0].value == "primary")
        @assert(cast(s32) params[1].value == 7)
    }

    @assert(cast(#null string) Reflection.attributeValue(fieldX, FieldMeta, "fieldAlias") == "primary")
    @assert(Reflection.attributeValue(fieldX, FieldMeta, "rank", 0) == 7)
    @assert(cast(#null string) Reflection.attributeValue(fieldEnabled, FieldMeta, "fieldAlias") == "switch")
    @assert(Reflection.attributeValue(fieldEnabled, FieldMeta, "rank", 0) == 0)
    @assert(Reflection.attributeValue(type, TypeMeta, "missing") == null)
}

#test
{
    var probe = ReflectionProbe{}

    let fieldX       = Reflection.findField(#typeof(probe), "x")
    let fieldEnabled = Reflection.findField(#typeof(probe), "enabled")
    let fieldLabel   = Reflection.findField(#typeof(probe), "label")

    var readX:       s32
    var readEnabled: bool
    var readLabel:   #null string

    Reflection.readFieldValue(&readX, fieldX, &probe)
    Reflection.readFieldValue(&readEnabled, fieldEnabled, &probe)
    Reflection.readFieldValue(&readLabel, fieldLabel, &probe)

    @assert(readX == 1)
    @assert(readEnabled)
    @assert(readLabel == "seed")

    let newX: s32  = 42
    let newEnabled = false
    let newLabel   = "patched"

    Reflection.writeFieldValue(&probe, fieldX, &newX)
    Reflection.writeFieldValue(&probe, fieldEnabled, &newEnabled)
    Reflection.writeFieldValue(&probe, fieldLabel, &newLabel)

    @assert(probe.x == 42)
    @assert(!probe.enabled)
    @assert(probe.label == "patched")
    @assert(probe.ping() == 43)
}

#test
{
    @assert(Reflection.isPod(#typeof(PodProbe)))
    @assert(Reflection.canCopy(#typeof(PodProbe)))
    @assert(!Reflection.hasDrop(#typeof(PodProbe)))
    @assert(!Reflection.hasPostCopy(#typeof(PodProbe)))
    @assert(!Reflection.hasPostMove(#typeof(PodProbe)))

    @assert(!Reflection.isPod(#typeof(LifecycleProbe)))
    @assert(Reflection.canCopy(#typeof(LifecycleProbe)))
    @assert(Reflection.hasDrop(#typeof(LifecycleProbe)))
    @assert(Reflection.hasPostCopy(#typeof(LifecycleProbe)))
    @assert(Reflection.hasPostMove(#typeof(LifecycleProbe)))
}

#test
{
    let arrayType = #typeof(Array's32)
    let arrayInfo = cast(const *Swag.TypeInfoStruct) arrayType
    @assert(Reflection.isDynamicArray(arrayType))
    @assert(Reflection.isGeneric(arrayType))
    @assert(@countof(arrayInfo.generics) == 1)
    @assert(arrayInfo.generics[0].pointedType == s32)
    @assert(Reflection.dynamicArrayElementType(arrayType) == s32)

    let hashType = #typeof(HashSet's32)
    @assert(!Reflection.isDynamicArray(hashType))
}

#test
{
    var values: Array'string
    values.add(String.from("11111111111111111111111111111111"))
    values.add(String.from("22222222222222222222222222222222"))
    values.add(String.from("33333333333333333333333333333333"))

    Reflection.removeDynamicArrayElement(&values, #typeof(string), 1)

    @assert(values.count == 2)
    @assert(values[0] == "11111111111111111111111111111111")
    @assert(values[1] == "33333333333333333333333333333333")
}

#test
{
    let type = #typeof(ReflectionProbe)
    ReflectionRuntimeMethodCalls  = 0
    ReflectionRuntimePointerCalls = 0

    @assert(runtimeMethodReflectionWorks(type, 1))
    @assert(ReflectionRuntimeMethodCalls == 1)
    @assert(ReflectionRuntimePointerCalls == 1)
    @assert(Reflection.hasMethod(type, "ping"))
    @assert(!Reflection.hasMethod(type, "visitMacro"))
    @assert(!Reflection.hasMethod(type, "missing"))
}

#test
{
    let type = #typeof(InterfaceProbe)

    @assert(Reflection.hasInterface(type, IReflectionScore))
    @assert(!Reflection.hasInterface(#typeof(ReflectionProbe), IReflectionScore))
}

#test
{
    let aliasType    = #typeof(ReflectionProbeAlias2)
    let concreteType = Reflection.resolveAliases(aliasType)

    @assert(concreteType == #typeof(ReflectionProbe))
    @assert(Reflection.maximumSize([#typeof(u8), #typeof(u16), #typeof(ReflectionProbe)]) == #sizeof(ReflectionProbe))
    @assert(Reflection.combinedFlags([#typeof(s32), #typeof(f32)]) & .Integer)
    @assert(Reflection.combinedFlags([#typeof(s32), #typeof(f32)]) & .Float)
}

#test
{
    var src = CopyProbe{value: 77}
    var dst = CopyProbe{}

    Reflection.assign(&dst, &src, #typeof(CopyProbe))
    @assert(dst.value == 77)
    @assert(dst.copied)
    @assert(!src.copied)
}

#test
{
    let enumType  = #typeof(ProbeState)
    let enumInfo  = cast(const *Swag.TypeInfoEnum) enumType
    let enumValue = Reflection.enumValue(enumType, "Busy")!
    var state     = ProbeState.Busy

    @assert(Reflection.enumUnderlyingType(enumType) == u32)
    @assert(enumValue.name == "Busy")
    @assert(cast(#null const *u32) enumValue.value != null)
    @assert((dref cast #unnull (const *u32) enumValue.value) == 1)
    @assert(Reflection.enumName(enumType, &state) == "ProbeState.Busy")
    @assert(Reflection.enumName(enumType, &state, fullyQualified: false) == "Busy")
    @assert(!Reflection.isFlagsEnum(enumType))
    @assert(Reflection.isFlagsEnum(#typeof(ProbeFlags)))
    @assert(enumInfo.attributes![0].type == EnumMeta)
    @assert(cast(#null string) Reflection.attributeValue(enumType, EnumMeta, "label") == "state")
}

#test
{
    var flags    = ProbeFlags.Read | ProbeFlags.Exec
    let enumType = #typeof(flags)
    let attrs    = Reflection.attributes(enumType, EnumMeta)
    @assert(attrs.count == 1)
    let params = attrs[0].params!
    @assert(cast(#null string) params[0].value == "flags")
}

#test
{
    let funcType = #typeof(makeRepeated'(u16, 3))
    let funcInfo = cast(const *Swag.TypeInfoFunc) funcType
    @assert(Reflection.isGeneric(funcType))
    @assert(@countof(funcInfo.generics) == 2)
    let generics = funcInfo.generics!
    @assert(generics[0].pointedType == u16)
    @assert(generics[1].pointedType == s32)
    @assert(cast(#null const *s32) generics[1].value != null)
    @assert((dref cast #unnull (const *s32) generics[1].value) == 3)
    @assert(funcInfo.attributes![0].type == FuncMeta)
    @assert(cast(#null string) Reflection.attributeValue(funcType, FuncMeta, "label") == "repeat")
    @assert(cast(s32) Reflection.attributeValue(funcType, FuncMeta, "arity") == 2)
}
