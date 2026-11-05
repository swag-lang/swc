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
    mtd ping()->s32 => .x + 1

    #[Macro]
    mtd visitMacro(stmt: #code) { #inject(stmt) }
}

alias ReflectionProbePingFn = func(*ReflectionProbe)->s32

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

enum ProbeStringState: string
{
    Idle = "idle"
    Busy = "busy"
}

enum ProbeArrayState: const [3] u32
{
    Idle = [1, 2, 3]
    Busy = [4, 5, 6]
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
    for i in N do
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

    let pointedType = unwrap method.pointedType
    let methodType  = assume cast(const *Swag.TypeInfoFunc, pointedType)
    if method.name != "ping" or
       pointedType.kind != .Func or
       methodType.parameters.count != 1 or
       methodType.parameters![0].pointedType != #type *ReflectionProbe or
       methodType.returnType != s32 or
       method.value == null or
       Reflection.findMethod(type, "visitMacro") != null do
        return false

    var probe: ReflectionProbe = ReflectionProbe{x: seed}
    let ping   = cast(ReflectionProbePingFn, method.value)
    let result = ping(&probe)
    ReflectionRuntimePointerCalls += 1
    return result == seed + 1
}

#test
{
    let type = #typeof(ReflectionProbe)
    Swag.require(Reflection.isNamedStruct(type, "ReflectionProbe"))
    Swag.require(not Reflection.isNamedStruct(type, "Other"))

    let fieldX = unwrap Reflection.findField(type, "x")
    Swag.require(fieldX.name == "x")
    Swag.require(fieldX.pointedType == s32)
    Swag.require(Reflection.findField(type, "missing") == null)
}

#test
{
    let type         = #typeof(ReflectionProbe)
    let fieldX       = Reflection.findField(type, "x")
    let fieldEnabled = Reflection.findField(type, "enabled")
    let typeStruct   = assume cast(const *Swag.TypeInfoStruct, type)

    Swag.require(assume cast (string?, Reflection.attributeValue(type, TypeMeta, "label")) == "probe")
    Swag.require(assume cast (s32, Reflection.attributeValue(type, TypeMeta, "priority")) == 3)
    for &it in typeStruct.fields where it.name == "x"
    {
        Swag.require(Reflection.hasAttribute(it, FieldMeta))
        let attrib = unwrap Reflection.attribute(it, FieldMeta)
        let params = unwrap attrib.params
        Swag.require(params.count == 2)
        Swag.require(params[0].name == "fieldAlias")
        Swag.require(params[1].name == "rank")
        Swag.require(assume cast (string?, params[0].value) == "primary")
        Swag.require(assume cast (s32, params[1].value) == 7)
    }

    Swag.require(assume cast (string?, Reflection.attributeValue(fieldX, FieldMeta, "fieldAlias")) == "primary")
    Swag.require(Reflection.attributeValue(fieldX, FieldMeta, "rank", 0) == 7)
    Swag.require(assume cast (string?, Reflection.attributeValue(fieldEnabled, FieldMeta, "fieldAlias")) == "switch")
    Swag.require(Reflection.attributeValue(fieldEnabled, FieldMeta, "rank", 0) == 0)
    Swag.require(Reflection.attributeValue(type, TypeMeta, "missing") == null)
}

#test
{
    var probe = ReflectionProbe{}

    let fieldX       = Reflection.findField(#typeof(probe), "x")
    let fieldEnabled = Reflection.findField(#typeof(probe), "enabled")
    let fieldLabel   = Reflection.findField(#typeof(probe), "label")

    var readX:       s32
    var readEnabled: bool
    var readLabel:   string?

    Reflection.readFieldValue(&readX, fieldX, &probe)
    Reflection.readFieldValue(&readEnabled, fieldEnabled, &probe)
    Reflection.readFieldValue(&readLabel, fieldLabel, &probe)

    Swag.require(readX == 1)
    Swag.require(readEnabled)
    Swag.require(readLabel == "seed")

    let newX: s32  = 42
    let newEnabled = false
    let newLabel   = "patched"

    Reflection.writeFieldValue(&probe, fieldX, &newX)
    Reflection.writeFieldValue(&probe, fieldEnabled, &newEnabled)
    Reflection.writeFieldValue(&probe, fieldLabel, &newLabel)

    Swag.require(probe.x == 42)
    Swag.require(not probe.enabled)
    Swag.require(probe.label == "patched")
    Swag.require(probe.ping() == 43)
}

#test
{
    Swag.require(Reflection.isPod(#typeof(PodProbe)))
    Swag.require(Reflection.canCopy(#typeof(PodProbe)))
    Swag.require(not Reflection.hasDrop(#typeof(PodProbe)))
    Swag.require(not Reflection.hasPostCopy(#typeof(PodProbe)))
    Swag.require(not Reflection.hasPostMove(#typeof(PodProbe)))

    Swag.require(not Reflection.isPod(#typeof(LifecycleProbe)))
    Swag.require(Reflection.canCopy(#typeof(LifecycleProbe)))
    Swag.require(Reflection.hasDrop(#typeof(LifecycleProbe)))
    Swag.require(Reflection.hasPostCopy(#typeof(LifecycleProbe)))
    Swag.require(Reflection.hasPostMove(#typeof(LifecycleProbe)))
}

#test
{
    let arrayType = #typeof(Array's32)
    let arrayInfo = assume cast(const *Swag.TypeInfoStruct, arrayType)
    Swag.require(Reflection.isDynamicArray(arrayType))
    Swag.require(Reflection.isGeneric(arrayType))
    Swag.require(arrayInfo.generics.count == 1)
    Swag.require(arrayInfo.generics[0].pointedType == s32)
    Swag.require(Reflection.dynamicArrayElementType(arrayType) == s32)

    let hashType = #typeof(HashSet's32)
    Swag.require(not Reflection.isDynamicArray(hashType))
}

#test
{
    // The array holds views: the literals are static, so the elements stay valid. A
    // temporary 'String' here would leave every element pointing at a freed buffer.
    var values: Array'string
    values.add("11111111111111111111111111111111")
    values.add("22222222222222222222222222222222")
    values.add("33333333333333333333333333333333")

    Reflection.removeDynamicArrayElement(&values, #typeof(string), 1)

    Swag.require(values.count == 2)
    Swag.require(values[0] == "11111111111111111111111111111111")
    Swag.require(values[1] == "33333333333333333333333333333333")
}

#test
{
    let type = #typeof(ReflectionProbe)
    ReflectionRuntimeMethodCalls  = 0
    ReflectionRuntimePointerCalls = 0

    Swag.require(runtimeMethodReflectionWorks(type, 1))
    Swag.require(ReflectionRuntimeMethodCalls == 1)
    Swag.require(ReflectionRuntimePointerCalls == 1)
    Swag.require(Reflection.hasMethod(type, "ping"))
    Swag.require(not Reflection.hasMethod(type, "visitMacro"))
    Swag.require(not Reflection.hasMethod(type, "missing"))
}

#test
{
    let type = #typeof(InterfaceProbe)

    Swag.require(Reflection.hasInterface(type, IReflectionScore))
    Swag.require(not Reflection.hasInterface(#typeof(ReflectionProbe), IReflectionScore))
}

#test
{
    let aliasType    = #typeof(ReflectionProbeAlias2)
    let concreteType = Reflection.resolveAliases(aliasType)

    Swag.require(concreteType == #typeof(ReflectionProbe))
    Swag.require(Reflection.maximumSize([#typeof(u8), #typeof(u16), #typeof(ReflectionProbe)]) == #sizeof(ReflectionProbe))
    Swag.require(Reflection.combinedFlags([#typeof(s32), #typeof(f32)]) & .Integer)
    Swag.require(Reflection.combinedFlags([#typeof(s32), #typeof(f32)]) & .Float)
}

#test
{
    var src = CopyProbe{value: 77}
    var dst = CopyProbe{}

    Reflection.assign(&dst, &src, #typeof(CopyProbe))
    Swag.require(dst.value == 77)
    Swag.require(dst.copied)
    Swag.require(not src.copied)
}

#test
{
    let enumType  = #typeof(ProbeState)
    let enumInfo  = assume cast(const *Swag.TypeInfoEnum, enumType)
    let enumValue = unwrap Reflection.enumValue(enumType, "Busy")
    var state     = ProbeState.Busy
    var invalidStateValue: u32 = 99

    Swag.require(Reflection.enumUnderlyingType(enumType) == u32)
    Swag.require(enumValue.name == "Busy")
    Swag.require(cast(const *u32?, enumValue.value) != null)
    Swag.require(cast(const *u32, enumValue.value)[] == 1)
    Swag.require(Reflection.enumName(enumType, &state) == "ProbeState.Busy")
    Swag.require(Reflection.enumName(enumType, &state, fullyQualified: false) == "Busy")
    Swag.require(Reflection.hasDeclaredValue(enumType, &state))
    Swag.require(not Reflection.hasDeclaredValue(enumType, &invalidStateValue))
    var stringState        = ProbeStringState.Busy
    var invalidStringState = "missing"
    Swag.require(Reflection.hasDeclaredValue(#typeof(ProbeStringState), &stringState))
    Swag.require(not Reflection.hasDeclaredValue(#typeof(ProbeStringState), &invalidStringState))
    var arrayState = ProbeArrayState.Busy
    var invalidArrayState: [3] u32 = [4, 5, 7]
    Swag.require(Reflection.hasDeclaredValue(#typeof(ProbeArrayState), &arrayState))
    Swag.require(not Reflection.hasDeclaredValue(#typeof(ProbeArrayState), &invalidArrayState))
    Swag.require(not Reflection.isFlagsEnum(enumType))
    Swag.require(Reflection.isFlagsEnum(#typeof(ProbeFlags)))
    Swag.require(enumInfo.attributes![0].type == EnumMeta)
    Swag.require(assume cast (string?, Reflection.attributeValue(enumType, EnumMeta, "label")) == "state")
}

#test
{
    var flags    = ProbeFlags.Read | ProbeFlags.Exec
    let enumType = #typeof(flags)
    let attrs    = Reflection.attributes(enumType, EnumMeta)
    Swag.require(attrs.count == 1)
    let params = unwrap attrs[0].params
    Swag.require(assume cast (string?, params[0].value) == "flags")
}

#test
{
    let funcType = #typeof(makeRepeated'(u16, 3))
    let funcInfo = assume cast(const *Swag.TypeInfoFunc, funcType)
    Swag.require(Reflection.isGeneric(funcType))
    Swag.require(funcInfo.generics.count == 2)
    let generics = unwrap funcInfo.generics
    Swag.require(generics[0].pointedType == u16)
    Swag.require(generics[1].pointedType == s32)
    Swag.require(cast(const *s32?, generics[1].value) != null)
    Swag.require((cast(const *s32, unwrap generics[1].value)[]) == 3)
    Swag.require(funcInfo.attributes![0].type == FuncMeta)
    Swag.require(assume cast (string?, Reflection.attributeValue(funcType, FuncMeta, "label")) == "repeat")
    Swag.require(assume cast (s32, Reflection.attributeValue(funcType, FuncMeta, "arity")) == 2)
}

#[Swag.EnumFlags]
enum ProbeAccess: u8
{
    None      = 0
    Read      = 1
    Write     = 2
    ReadWrite = Read | Write
    Default   = Read
}

// A flags value names each case whose bits are all set, once, and zero names the zero case.
#test
{
    var none      = ProbeAccess.None
    var read      = ProbeAccess.Read
    var readWrite = ProbeAccess.ReadWrite
    Swag.require(Reflection.enumName(ProbeAccess, &none, fullyQualified: false) == "None")
    Swag.require(Reflection.enumName(ProbeAccess, &read, fullyQualified: false) == "Read")
    Swag.require(Reflection.enumName(ProbeAccess, &readWrite, fullyQualified: false) == "Read | Write")
}

namespace ReflectionBareA
{
    struct Twin { a: s32 }
}

namespace ReflectionBareB
{
    struct Twin { b: f32 }
}

struct ReflectionTwinHolder
{
    first:  ReflectionBareA.Twin
    second: ReflectionBareB.Twin
}

// Two namespaces may each declare a type of the same bare name, and one graph may hold both:
// registering it keeps each type under its full name and leaves the shared bare name to none.
#test
{
    Reflection.registerType(#typeof(ReflectionTwinHolder))

    let first  = unwrap #typeof(ReflectionBareA.Twin).fullname
    let second = unwrap #typeof(ReflectionBareB.Twin).fullname
    let bare   = unwrap #typeof(ReflectionBareA.Twin).name
    Swag.require(Reflection.typeFromCrc(Hash.Crc32.compute(first))!.fullname == first)
    Swag.require(Reflection.typeFromCrc(Hash.Crc32.compute(second))!.fullname == second)
    Swag.require(Reflection.typeFromCrc(Hash.Crc32.compute(bare)) == null)
}
