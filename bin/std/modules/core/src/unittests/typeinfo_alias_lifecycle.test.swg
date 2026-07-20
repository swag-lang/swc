#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

var CoreAliasLifecycleDropCount: s32
var CoreAliasLifecyclePostCopyCount: s32
var CoreAliasLifecyclePostMoveCount: s32

struct CoreAliasLifecycleProbe
{
    value: s32
}

impl CoreAliasLifecycleProbe
{
    mtd opDrop()
    {
        CoreAliasLifecycleDropCount += 1
    }

    mtd opPostCopy()
    {
        CoreAliasLifecyclePostCopyCount += 1
    }

    mtd opPostMove()
    {
        CoreAliasLifecyclePostMoveCount += 1
    }
}

#[Swag.Strict]
alias CoreAliasLifecycleStrict = CoreAliasLifecycleProbe

func resetCoreAliasLifecycleCounters()
{
    CoreAliasLifecycleDropCount     = 0
    CoreAliasLifecyclePostCopyCount = 0
    CoreAliasLifecyclePostMoveCount = 0
}

func hasCoreAliasLifecycleFlags(type: #nonull typeinfo)->bool
{
    return (type.flags & TypeInfoFlags.HasDrop) and
           (type.flags & TypeInfoFlags.HasPostCopy) and
           (type.flags & TypeInfoFlags.HasPostMove)
}

func testCoreAliasLifecycleRuntimeFlags()->bool
{
    let aliasType = #typeof(CoreAliasLifecycleStrict)
    let arrayType = #typeof([2] CoreAliasLifecycleStrict)
    if aliasType.kind != TypeInfoKind.Alias or arrayType.kind != TypeInfoKind.Array do
        return false
    if !hasCoreAliasLifecycleFlags(aliasType) or !hasCoreAliasLifecycleFlags(arrayType) do
        return false

    let directRaw = Memory.alloc(#sizeof(CoreAliasLifecycleProbe))
    defer Memory.free(directRaw, #sizeof(CoreAliasLifecycleProbe))
    let direct = cast(#nonull *CoreAliasLifecycleProbe) directRaw
    direct.value = 7

    resetCoreAliasLifecycleCounters()
    Memory.postCopyType(directRaw, aliasType)
    Memory.postMoveType(directRaw, aliasType)
    Memory.dropType(directRaw, aliasType)
    if CoreAliasLifecyclePostCopyCount != 1 or CoreAliasLifecyclePostMoveCount != 1 or CoreAliasLifecycleDropCount != 1 do
        return false

    let arrayRaw = Memory.alloc(#sizeof([2] CoreAliasLifecycleProbe))
    defer Memory.free(arrayRaw, #sizeof([2] CoreAliasLifecycleProbe))
    let values = cast(#nonull [*] CoreAliasLifecycleProbe) arrayRaw
    values[0].value = 11
    values[1].value = 22

    resetCoreAliasLifecycleCounters()
    Memory.postCopyType(arrayRaw, arrayType)
    Memory.postMoveType(arrayRaw, arrayType)
    Memory.dropType(arrayRaw, arrayType)
    if CoreAliasLifecyclePostCopyCount != 2 or CoreAliasLifecyclePostMoveCount != 2 or CoreAliasLifecycleDropCount != 2 do
        return false

    let nestedArrayType = #typeof([3][2] CoreAliasLifecycleStrict)
    if nestedArrayType.kind != TypeInfoKind.Array or !hasCoreAliasLifecycleFlags(nestedArrayType) do
        return false

    let nestedArrayRaw = Memory.alloc(#sizeof([3][2] CoreAliasLifecycleProbe))
    defer Memory.free(nestedArrayRaw, #sizeof([3][2] CoreAliasLifecycleProbe))

    resetCoreAliasLifecycleCounters()
    Memory.postCopyType(nestedArrayRaw, nestedArrayType)
    Memory.postMoveType(nestedArrayRaw, nestedArrayType)
    Memory.dropType(nestedArrayRaw, nestedArrayType)
    return CoreAliasLifecyclePostCopyCount == 6 and
           CoreAliasLifecyclePostMoveCount == 6 and
           CoreAliasLifecycleDropCount == 6
}

#test
{
    @assert(testCoreAliasLifecycleRuntimeFlags())
}
