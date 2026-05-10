#global #if #command == Swag.CompilerCommand.Test
#global fileprivate

attr TypeMeta(label: string, priority: s32 = 0)
attr FieldMeta(fieldAlias: string, rank: s32 = 0)

#[TypeMeta("probe", 3)]
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
}

struct PodProbe
{
    value: s32
}

struct LifecycleProbe
{
    value: s32
}

impl LifecycleProbe
{
    mtd opDrop() {}
    mtd opPostCopy() {}
    mtd opPostMove() {}
}

#test
{
    let type = #typeof(ReflectionProbe)
    @assert(Reflection.isStructOfName(type, "ReflectionProbe"))
    @assert(!Reflection.isStructOfName(type, "Other"))

    let fieldX = Reflection.getField(type, "x")
    @assert(fieldX != null)
    @assert(fieldX.name == "x")
    @assert(fieldX.pointedType == s32)
    @assert(Reflection.getField(type, "missing") == null)

}

#test
{
    let type = #typeof(ReflectionProbe)
    let fieldX = Reflection.getField(type, "x")
    let fieldEnabled = Reflection.getField(type, "enabled")
    let typeStruct = cast(const *Swag.TypeInfoStruct) type

    @assert(cast(string) Reflection.getAttributeValue(type, TypeMeta, "label") == "probe")
    @assert(cast(s32) Reflection.getAttributeValue(type, TypeMeta, "priority") == 3)
    foreach &it in typeStruct.fields where it.name == "x"
    {
        @assert(Reflection.hasAttribute(it, FieldMeta))
        let attrib = Reflection.getAttribute(it, FieldMeta)
        @assert(attrib != null)
        @assert(@countof(attrib.params) == 2)
        @assert(attrib.params[0].name == "fieldAlias")
        @assert(attrib.params[1].name == "rank")
        @assert(cast(string) attrib.params[0].value == "primary")
        @assert(cast(s32) attrib.params[1].value == 7)
    }
    @assert(cast(string) Reflection.getAttributeValue(fieldX, FieldMeta, "fieldAlias") == "primary")
    @assert(Reflection.getAttributeValue(fieldX, FieldMeta, "rank", 0) == 7)
    @assert(cast(string) Reflection.getAttributeValue(fieldEnabled, FieldMeta, "fieldAlias") == "switch")
    @assert(Reflection.getAttributeValue(fieldEnabled, FieldMeta, "rank", 0) == 0)
    @assert(Reflection.getAttributeValue(type, TypeMeta, "missing") == null)
}

#test
{
    var probe = ReflectionProbe{}

    let fieldX = Reflection.getField(#typeof(probe), "x")
    let fieldEnabled = Reflection.getField(#typeof(probe), "enabled")
    let fieldLabel = Reflection.getField(#typeof(probe), "label")

    var readX: s32
    var readEnabled: bool
    var readLabel: string

    Reflection.getFieldValue(&readX, fieldX, &probe)
    Reflection.getFieldValue(&readEnabled, fieldEnabled, &probe)
    Reflection.getFieldValue(&readLabel, fieldLabel, &probe)

    @assert(readX == 1)
    @assert(readEnabled)
    @assert(readLabel == "seed")

    let newX: s32 = 42
    let newEnabled = false
    let newLabel = "patched"

    Reflection.setFieldValue(&probe, fieldX, &newX)
    Reflection.setFieldValue(&probe, fieldEnabled, &newEnabled)
    Reflection.setFieldValue(&probe, fieldLabel, &newLabel)

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
    @assert(Reflection.isStructArray(arrayType))

    let hashType = #typeof(HashSet's32)
    @assert(!Reflection.isStructArray(hashType))
}
