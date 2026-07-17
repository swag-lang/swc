#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

var CoreTupleLifecycleDropOrder:     s32
var CoreTupleLifecyclePostCopyOrder: s32
var CoreTupleLifecyclePostMoveOrder: s32

struct CoreTupleLifecycleProbe
{
    id:    s32 = 7
    value: #nonull string = "tuple-default"
}

impl CoreTupleLifecycleProbe
{
    mtd opDrop()
    {
        CoreTupleLifecycleDropOrder = CoreTupleLifecycleDropOrder * 10 + .id
    }

    mtd opPostCopy()
    {
        CoreTupleLifecyclePostCopyOrder = CoreTupleLifecyclePostCopyOrder * 10 + .id
    }

    mtd opPostMove()
    {
        CoreTupleLifecyclePostMoveOrder = CoreTupleLifecyclePostMoveOrder * 10 + .id
    }
}

#[Swag.Strict]
alias CoreTupleLifecycleStrict = #decltype({first: CoreTupleLifecycleProbe{}, second: CoreTupleLifecycleProbe{}})

func coreTupleLifecycleProbeAt(base: [*] u8, type: const *TypeInfoStruct, index: u64)->*CoreTupleLifecycleProbe
{
    return cast(*CoreTupleLifecycleProbe) (base + type.fields[index].offset)
}

func testCoreTupleRuntimeLifecycle()->bool
{
    let tupleType = #typeof({first: CoreTupleLifecycleProbe{}, second: CoreTupleLifecycleProbe{}})
    if tupleType.kind != TypeInfoKind.Struct or !(tupleType.flags & TypeInfoFlags.Tuple) do
        return false

    let tupleStruct = cast(const *TypeInfoStruct) tupleType
    if tupleStruct.opInit or tupleStruct.opDrop or tupleStruct.opPostCopy or tupleStruct.opPostMove do
        return false

    let source = Memory.new(tupleType)
    let target = Memory.new(tupleType)
    if !source or !target do
        return false
    defer Memory.free(cast([*] void) source, cast(u64) tupleType.sizeof)
    defer Memory.free(cast([*] void) target, cast(u64) tupleType.sizeof)

    let sourceFirst  = coreTupleLifecycleProbeAt(cast([*] u8) source, tupleStruct, 0)
    let sourceSecond = coreTupleLifecycleProbeAt(cast([*] u8) source, tupleStruct, 1)
    let targetFirst  = coreTupleLifecycleProbeAt(cast([*] u8) target, tupleStruct, 0)
    let targetSecond = coreTupleLifecycleProbeAt(cast([*] u8) target, tupleStruct, 1)
    if sourceFirst.id != 7 or sourceSecond.id != 7 or
       sourceFirst.value != "tuple-default" or sourceSecond.value != "tuple-default" do
        return false

    sourceFirst.id  = 1
    sourceSecond.id = 2
    CoreTupleLifecyclePostCopyOrder = 0
    Reflection.copy(target, source, tupleType)
    if CoreTupleLifecyclePostCopyOrder != 12 or targetFirst.id != 1 or targetSecond.id != 2 do
        return false

    CoreTupleLifecyclePostMoveOrder = 0
    Memory.postMoveType(target, tupleType)
    if CoreTupleLifecyclePostMoveOrder != 12 do
        return false

    CoreTupleLifecycleDropOrder = 0
    Reflection.reset(target, tupleType)
    if CoreTupleLifecycleDropOrder != 21 or
       targetFirst.id != 7 or targetSecond.id != 7 or
       targetFirst.value != "tuple-default" or targetSecond.value != "tuple-default" do
        return false

    CoreTupleLifecycleDropOrder = 0
    Memory.dropType(source, tupleType)
    if CoreTupleLifecycleDropOrder != 21 do
        return false

    CoreTupleLifecycleDropOrder = 0
    Memory.dropType(target, tupleType)
    return CoreTupleLifecycleDropOrder == 77
}

func testCoreTupleArrayRuntimeLifecycle()->bool
{
    let arrayType = #typeof([
        {first: CoreTupleLifecycleProbe{}, second: CoreTupleLifecycleProbe{}},
        {first: CoreTupleLifecycleProbe{}, second: CoreTupleLifecycleProbe{}}])
    if arrayType.kind != TypeInfoKind.Array do
        return false

    let arrayStruct = cast(const *TypeInfoArray) arrayType
    if !(arrayStruct.pointedType.flags & TypeInfoFlags.Tuple) do
        return false

    let tupleStruct = cast(const *TypeInfoStruct) arrayStruct.pointedType
    let values      = Memory.new(arrayType)
    if !values do
        return false
    defer Memory.free(cast([*] void) values, cast(u64) arrayType.sizeof)

    let tuple0 = cast([*] u8) values
    let tuple1 = tuple0 + arrayStruct.pointedType.sizeof
    let first0  = coreTupleLifecycleProbeAt(tuple0, tupleStruct, 0)
    let second0 = coreTupleLifecycleProbeAt(tuple0, tupleStruct, 1)
    let first1  = coreTupleLifecycleProbeAt(tuple1, tupleStruct, 0)
    let second1 = coreTupleLifecycleProbeAt(tuple1, tupleStruct, 1)
    if first0.value != "tuple-default" or second0.value != "tuple-default" or
       first1.value != "tuple-default" or second1.value != "tuple-default" do
        return false

    first0.id  = 1
    second0.id = 2
    first1.id  = 3
    second1.id = 4

    CoreTupleLifecyclePostCopyOrder = 0
    Memory.postCopyType(values, arrayType)
    if CoreTupleLifecyclePostCopyOrder != 1234 do
        return false

    CoreTupleLifecyclePostMoveOrder = 0
    Memory.postMoveType(values, arrayType)
    if CoreTupleLifecyclePostMoveOrder != 1234 do
        return false

    CoreTupleLifecycleDropOrder = 0
    Memory.dropType(values, arrayType)
    return CoreTupleLifecycleDropOrder == 2143
}

func testCoreTupleAliasRuntimeLifecycle()->bool
{
    let aliasType = #typeof(CoreTupleLifecycleStrict)
    if aliasType.kind != TypeInfoKind.Alias or
       !(aliasType.flags & TypeInfoFlags.HasDrop) or
       !(aliasType.flags & TypeInfoFlags.HasPostCopy) or
       !(aliasType.flags & TypeInfoFlags.HasPostMove) do
        return false

    let rawType = (cast(const *TypeInfoAlias) aliasType).rawType
    if !(rawType.flags & TypeInfoFlags.Tuple) do
        return false

    let tupleStruct = cast(const *TypeInfoStruct) rawType
    let value       = Memory.new(aliasType)
    if !value do
        return false
    defer Memory.free(cast([*] void) value, cast(u64) aliasType.sizeof)

    let first  = coreTupleLifecycleProbeAt(cast([*] u8) value, tupleStruct, 0)
    let second = coreTupleLifecycleProbeAt(cast([*] u8) value, tupleStruct, 1)
    if first.id != 7 or second.id != 7 or
       first.value != "tuple-default" or second.value != "tuple-default" do
        return false

    first.id  = 1
    second.id = 2
    CoreTupleLifecyclePostCopyOrder = 0
    Memory.postCopyType(value, aliasType)
    if CoreTupleLifecyclePostCopyOrder != 12 do
        return false

    CoreTupleLifecyclePostMoveOrder = 0
    Memory.postMoveType(value, aliasType)
    if CoreTupleLifecyclePostMoveOrder != 12 do
        return false

    CoreTupleLifecycleDropOrder = 0
    Memory.dropType(value, aliasType)
    return CoreTupleLifecycleDropOrder == 21
}

#test
{
    @assert(testCoreTupleRuntimeLifecycle())
    @assert(testCoreTupleArrayRuntimeLifecycle())
    @assert(testCoreTupleAliasRuntimeLifecycle())
}
