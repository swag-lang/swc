#global if #command == Swag.CompilerCommand.Test
#global private

struct CoreNonNullDynamicItem
{
    value: s32
}

union CoreNonNullZeroUnion
{
    bits: u64

    // The pointer view of the same bits: it starts null so the union keeps a valid zero
    // default, which is exactly what the reflection guards below are written against.
    late pointer: *CoreNonNullDynamicItem
}

#[Swag.Strict]
alias CoreNonNullZeroUnionAlias = CoreNonNullZeroUnion

struct CoreNonNullRuntimeDefault
{
    value: string = "fallback"
}

alias CoreNonNullRuntimeDefaultPair  = [2] CoreNonNullRuntimeDefault

#[Swag.Strict]
alias CoreNonNullRuntimeDefaultAlias = CoreNonNullRuntimeDefault

// Each guard panics before it touches its target, so the target is checked after the catch.
func testCoreNonNullDynamicInitialization()->bool
{
    var item         = CoreNonNullDynamicItem{value: 71}
    let requiredType = #typeof(*CoreNonNullDynamicItem)

    let rejectedNew = Swag.catchPanic(func|requiredType|() { discard Memory.new(requiredType) }).raised

    var resetSentinel: *CoreNonNullDynamicItem = &item
    let rejectedReset  = Swag.catchPanic(func|&resetSentinel, requiredType|() { Reflection.reset(&resetSentinel, requiredType) }).raised
    let preservedReset = rejectedReset and resetSentinel == &item

    var rejectedArray: Array'(*CoreNonNullDynamicItem)
    let rejectedAppend = Swag.catchPanic(func|&rejectedArray, requiredType|() { discard Reflection.appendDynamicArrayElement(&rejectedArray, requiredType) }).raised
    let preservedArray = rejectedAppend and rejectedArray.buffer == null and not rejectedArray.count and not rejectedArray.capacity

    let zeroType       = #typeof(CoreNonNullZeroUnion)
    let zeroStructType = assume cast(const *Swag.TypeInfoStruct, zeroType)
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

    let rejectedZeroNew = Swag.catchPanic(func|zeroType|() { discard Memory.new(zeroType) }).raised

    var resetZero          = CoreNonNullZeroUnion{bits: 0xFFFF}
    let rejectedZeroReset  = Swag.catchPanic(func|&resetZero, zeroType|() { Reflection.reset(&resetZero, zeroType) }).raised
    let preservedZeroReset = rejectedZeroReset and resetZero.bits == 0xFFFF

    var zeroArray: Array'CoreNonNullZeroUnion
    let rejectedZeroAppend = Swag.catchPanic(func|&zeroArray, zeroType|() { discard Reflection.appendDynamicArrayElement(&zeroArray, zeroType) }).raised and
                             zeroArray.buffer == null and
                             not zeroArray.count and
                             not zeroArray.capacity

    let defaultArrayType = #typeof([2] CoreNonNullRuntimeDefault)
    let defaultAliasType = #typeof(CoreNonNullRuntimeDefaultAlias)
    if defaultArrayType.kind != Swag.TypeInfoKind.Array or defaultAliasType.kind != Swag.TypeInfoKind.Alias do
        return false
    if defaultArrayType.flags & Swag.TypeInfoFlags.RequiresExplicitInit or defaultAliasType.flags & Swag.TypeInfoFlags.RequiresExplicitInit do
        return false

    let allocatedDefaults      = Memory.new(defaultArrayType)
    let allocatedDefaultValues = cast(*[2] CoreNonNullRuntimeDefault?, allocatedDefaults)
    let initializedNewArray    = allocatedDefaultValues != null and
                                 allocatedDefaultValues[][0].value == "fallback" and
                                 allocatedDefaultValues[][1].value == "fallback"
    Memory.free(cast([*] void?, allocatedDefaults), cast(u64, defaultArrayType.sizeof))

    let allocatedAlias      = Memory.new(defaultAliasType)
    let allocatedAliasValue = cast(*CoreNonNullRuntimeDefault?, allocatedAlias)
    let initializedNewAlias = allocatedAliasValue != null and allocatedAliasValue.value == "fallback"
    Memory.free(cast([*] void?, allocatedAlias), cast(u64, defaultAliasType.sizeof))

    let nestedAliasArrayType        = #typeof([3] CoreNonNullRuntimeDefaultPair)
    let allocatedNestedAliasArray   = Memory.new(nestedAliasArrayType)
    let nestedAliasValues           = cast([*] CoreNonNullRuntimeDefault?, allocatedNestedAliasArray)
    let initializedNestedAliasArray = nestedAliasValues != null and
                                      nestedAliasValues[0].value == "fallback" and
                                      nestedAliasValues[5].value == "fallback"
    Memory.free(cast([*] void?, allocatedNestedAliasArray), cast(u64, nestedAliasArrayType.sizeof))

    let nestedArrayType        = #typeof([3][2] CoreNonNullRuntimeDefault)
    let allocatedNestedArray   = Memory.new(nestedArrayType)
    let nestedValues           = cast([*] CoreNonNullRuntimeDefault?, allocatedNestedArray)
    let initializedNestedArray = nestedValues != null and
                                 nestedValues[0].value == "fallback" and
                                 nestedValues[5].value == "fallback"
    Memory.free(cast([*] void?, allocatedNestedArray), cast(u64, nestedArrayType.sizeof))

    var resetDefaults: [2] CoreNonNullRuntimeDefault
    resetDefaults[0].value = "changed-0"
    resetDefaults[1].value = "changed-1"
    Reflection.reset(&resetDefaults, defaultArrayType)
    let initializedResetArray = resetDefaults[0].value == "fallback" and resetDefaults[1].value == "fallback"

    var resetAlias = CoreNonNullRuntimeDefault{value: "changed"}
    Reflection.reset(&resetAlias, defaultAliasType)
    let initializedResetAlias = resetAlias.value == "fallback"

    var appendedDefaults: Array'CoreNonNullRuntimeDefaultPair
    let appendedDefaultsPtr    = Reflection.appendDynamicArrayElement(&appendedDefaults, defaultArrayType)
    let appendedDefaultValues  = cast(*[2] CoreNonNullRuntimeDefault?, appendedDefaultsPtr)
    let initializedAppendArray = appendedDefaultValues != null and
                                 appendedDefaultValues[][0].value == "fallback" and
                                 appendedDefaultValues[][1].value == "fallback"

    var appendedAliases: Array'CoreNonNullRuntimeDefaultAlias
    let appendedAliasPtr       = Reflection.appendDynamicArrayElement(&appendedAliases, defaultAliasType)
    let appendedAliasValue     = cast(*CoreNonNullRuntimeDefault?, appendedAliasPtr)
    let initializedAppendAlias = appendedAliasValue != null and appendedAliasValue.value == "fallback"

    Swag.assert(rejectedNew)
    Swag.assert(preservedReset)
    Swag.assert(preservedArray)
    Swag.assert(rejectedZeroNew)
    Swag.assert(preservedZeroReset)
    Swag.assert(rejectedZeroAppend)
    Swag.assert(initializedNewArray)
    Swag.assert(initializedNewAlias)
    Swag.assert(initializedNestedAliasArray)
    Swag.assert(initializedNestedArray)
    Swag.assert(initializedResetArray)
    Swag.assert(initializedResetAlias)
    Swag.assert(initializedAppendArray)
    Swag.assert(initializedAppendAlias)
    return true
}

#test
{
    Swag.assert(testCoreNonNullDynamicInitialization())
}
