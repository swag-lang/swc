#global #if #command == Swag.CompilerCommand.Test
#global private

struct CoreNonNullDynamicItem
{
    value: s32
}

union CoreNonNullZeroUnion
{
    bits:    u64
    pointer: *CoreNonNullDynamicItem = undefined
}

#[Swag.Strict]
alias CoreNonNullZeroUnionAlias = CoreNonNullZeroUnion

struct CoreNonNullRuntimeDefault
{
    value: string = "fallback"
}

alias CoreNonNullRuntimeDefaultPair = [2] CoreNonNullRuntimeDefault

#[Swag.Strict]
alias CoreNonNullRuntimeDefaultAlias = CoreNonNullRuntimeDefault

func recordCoreNonNullGuardPanic(message: #null string, loc: Swag.SourceCodeLocation)
{
    @getcontext().user0 += 1
}

func testCoreNonNullDynamicInitialization()->bool
{
    var item = CoreNonNullDynamicItem{value: 71}
    let requiredType = #typeof(*CoreNonNullDynamicItem)
    let cxt = @getcontext()
    let previousPanic = cxt.panic
    let previousUser0 = cxt.user0
    cxt.user0 = 0
    cxt.panic = &recordCoreNonNullGuardPanic
    defer cxt.panic = previousPanic
    defer cxt.user0 = previousUser0

    let allocatedRequired = Memory.new(requiredType)
    let rejectedNew = allocatedRequired == null
    if allocatedRequired do
        Memory.free(cast(#null [*] void) allocatedRequired, cast(u64) requiredType.sizeof)

    var resetSentinel: *CoreNonNullDynamicItem = &item
    Reflection.reset(&resetSentinel, requiredType)
    let preservedReset = resetSentinel == &item

    var rejectedArray: Array'(*CoreNonNullDynamicItem)
    let rejectedAppend = Reflection.appendValueStructArray(&rejectedArray, requiredType)
    let preservedArray = rejectedAppend == null and rejectedArray.buffer == null and !rejectedArray.count and !rejectedArray.capacity

    let zeroType = #typeof(CoreNonNullZeroUnion)
    let zeroStructType = cast(const *Swag.TypeInfoStruct) zeroType
    if zeroStructType.opInit != null or zeroType.flags & Swag.TypeInfoFlags.RequiresExplicitInit do
        return false

    let zeroAliasType = #typeof(CoreNonNullZeroUnionAlias)
    let zeroArrayType = #typeof([2] CoreNonNullZeroUnion)
    let zeroTupleType = #typeof({value: CoreNonNullZeroUnion{bits: 0}})
    if Memory.canDefaultInit(zeroType) or
       Memory.canDefaultInit(zeroAliasType) or
       Memory.canDefaultInit(zeroArrayType) or
       Memory.canDefaultInit(zeroTupleType) do
        return false

    let allocatedZero = Memory.new(zeroType)
    let rejectedZeroNew = allocatedZero == null
    if allocatedZero do
        Memory.free(cast(#null [*] void) allocatedZero, cast(u64) zeroType.sizeof)

    var resetZero = CoreNonNullZeroUnion{bits: 0xFFFF}
    Reflection.reset(&resetZero, zeroType)
    let preservedZeroReset = resetZero.bits == 0xFFFF

    var zeroArray: Array'CoreNonNullZeroUnion
    let appendedZero = Reflection.appendValueStructArray(&zeroArray, zeroType)
    let rejectedZeroAppend = appendedZero == null and zeroArray.buffer == null and !zeroArray.count and !zeroArray.capacity

    let defaultArrayType = #typeof([2] CoreNonNullRuntimeDefault)
    let defaultAliasType = #typeof(CoreNonNullRuntimeDefaultAlias)
    if defaultArrayType.kind != Swag.TypeInfoKind.Array or defaultAliasType.kind != Swag.TypeInfoKind.Alias do
        return false
    if defaultArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit or defaultAliasType.flags & Swag.TypeInfoFlags.RequiresExplicitInit do
        return false

    let allocatedDefaults = Memory.new(defaultArrayType)
    let allocatedDefaultValues = cast(#null *[2] CoreNonNullRuntimeDefault) allocatedDefaults
    let initializedNewArray = allocatedDefaults and
                              (dref allocatedDefaultValues)[0].value == "fallback" and
                              (dref allocatedDefaultValues)[1].value == "fallback"
    if allocatedDefaults do
        Memory.free(cast(#null [*] void) allocatedDefaults, cast(u64) defaultArrayType.sizeof)

    let allocatedAlias = Memory.new(defaultAliasType)
    let initializedNewAlias = allocatedAlias and (cast(#null *CoreNonNullRuntimeDefault) allocatedAlias).value == "fallback"
    if allocatedAlias do
        Memory.free(cast(#null [*] void) allocatedAlias, cast(u64) defaultAliasType.sizeof)

    let nestedAliasArrayType = #typeof([3] CoreNonNullRuntimeDefaultPair)
    let allocatedNestedAliasArray = Memory.new(nestedAliasArrayType)
    let nestedAliasValues = cast(#null [*] CoreNonNullRuntimeDefault) allocatedNestedAliasArray
    let initializedNestedAliasArray = allocatedNestedAliasArray and
                                      nestedAliasValues[0].value == "fallback" and
                                      nestedAliasValues[5].value == "fallback"
    if allocatedNestedAliasArray do
        Memory.free(cast(#null [*] void) allocatedNestedAliasArray, cast(u64) nestedAliasArrayType.sizeof)

    let nestedArrayType = #typeof([3][2] CoreNonNullRuntimeDefault)
    let allocatedNestedArray = Memory.new(nestedArrayType)
    let nestedValues = cast(#null [*] CoreNonNullRuntimeDefault) allocatedNestedArray
    let initializedNestedArray = allocatedNestedArray and
                                 nestedValues[0].value == "fallback" and
                                 nestedValues[5].value == "fallback"
    if allocatedNestedArray do
        Memory.free(cast(#null [*] void) allocatedNestedArray, cast(u64) nestedArrayType.sizeof)

    var resetDefaults: [2] CoreNonNullRuntimeDefault
    resetDefaults[0].value = "changed-0"
    resetDefaults[1].value = "changed-1"
    Reflection.reset(&resetDefaults, defaultArrayType)
    let initializedResetArray = resetDefaults[0].value == "fallback" and resetDefaults[1].value == "fallback"

    var resetAlias = CoreNonNullRuntimeDefault{value: "changed"}
    Reflection.reset(&resetAlias, defaultAliasType)
    let initializedResetAlias = resetAlias.value == "fallback"

    var appendedDefaults: Array'CoreNonNullRuntimeDefaultPair
    let appendedDefaultsPtr = Reflection.appendValueStructArray(&appendedDefaults, defaultArrayType)
    let appendedDefaultValues = cast(#null *[2] CoreNonNullRuntimeDefault) appendedDefaultsPtr
    let initializedAppendArray = appendedDefaultsPtr and
                                 (dref appendedDefaultValues)[0].value == "fallback" and
                                 (dref appendedDefaultValues)[1].value == "fallback"

    var appendedAliases: Array'CoreNonNullRuntimeDefaultAlias
    let appendedAliasPtr = Reflection.appendValueStructArray(&appendedAliases, defaultAliasType)
    let initializedAppendAlias = appendedAliasPtr and (cast(#null *CoreNonNullRuntimeDefault) appendedAliasPtr).value == "fallback"

    @assert(cxt.user0 == 6)
    @assert(rejectedNew)
    @assert(preservedReset)
    @assert(preservedArray)
    @assert(rejectedZeroNew)
    @assert(preservedZeroReset)
    @assert(rejectedZeroAppend)
    @assert(initializedNewArray)
    @assert(initializedNewAlias)
    @assert(initializedNestedAliasArray)
    @assert(initializedNestedArray)
    @assert(initializedResetArray)
    @assert(initializedResetAlias)
    @assert(initializedAppendArray)
    @assert(initializedAppendAlias)
    return true
}

#test
{
    @assert(testCoreNonNullDynamicInitialization())
}
