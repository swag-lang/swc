#global private

// Reading a 'late' global before its first assignment panics under Null safety: no
// static cross-function proof is possible, so the guard always runs at runtime. Driven
// through '#run' so the guard executes at compile time and the panic is observed.

struct LateGlobalSafetyItem
{
    value: s32
}

late var g_lateSafetyUnset: *LateGlobalSafetyItem

#[Swag.Safety(.Null, true)]
func lateSafetyReadUnset()->s32
{
    return g_lateSafetyUnset.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyReadUnset()
    discard x
}

// The same read after assignment is fine.
var g_lateSafetyStorage:  LateGlobalSafetyItem
late var g_lateSafetySet: *LateGlobalSafetyItem

#[Swag.Safety(.Null, true)]
func lateSafetyReadSet()->s32
{
    return g_lateSafetySet.value
}

#test
{
    g_lateSafetyStorage.value = 5
    g_lateSafetySet = &g_lateSafetyStorage
    Swag.assert(lateSafetyReadSet() == 5)
}

// A read that runs proves the global set for the statements after it, so their guards are
// dropped. A read that may not run proves nothing: each read below that may have been skipped
// leaves the guard on the next one.

#[Swag.Safety(.Null, true)]
func lateSafetyAfterShortCircuit(flag: bool)->s32
{
    if flag and g_lateSafetyUnset.value > 0 do
        return 1
    return g_lateSafetyUnset.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyAfterShortCircuit(false)
    discard x
}

#[Swag.Safety(.Null, true)]
func lateSafetyAfterConditional(flag: bool)->s32
{
    let first = flag ? g_lateSafetyUnset.value : 0
    return first + g_lateSafetyUnset.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyAfterConditional(false)
    discard x
}

#[Swag.Safety(.Null, true)]
func lateSafetyAfterBranch(flag: bool)->s32
{
    var total = 0
    if flag do
        total = g_lateSafetyUnset.value
    return total + g_lateSafetyUnset.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyAfterBranch(false)
    discard x
}

#[Swag.Safety(.Null, true)]
func lateSafetyAfterEmptyLoop(count: u32)->s32
{
    var total = 0
    for count do
        total += g_lateSafetyUnset.value
    return total + g_lateSafetyUnset.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyAfterEmptyLoop(0)
    discard x
}

#[Swag.Safety(.Null, true), Swag.Safety(.Assert, false)]
func lateSafetyAfterDisabledAssert()->s32
{
    Swag.assert(g_lateSafetyUnset.value == 0)
    return g_lateSafetyUnset.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyAfterDisabledAssert()
    discard x
}

// Once a store or a read has run, the later reads observe the value.
var g_lateSafetyOther:     LateGlobalSafetyItem
late var g_lateSafetyMany: *LateGlobalSafetyItem

#[Swag.Safety(.Null, true)]
func lateSafetyReadMany(count: u32)->s32
{
    g_lateSafetyOther.value = 3
    g_lateSafetyMany        = &g_lateSafetyOther
    var total = g_lateSafetyMany.value
    for count do
        total += g_lateSafetyMany.value
    return total
}

#test
{
    Swag.assert(lateSafetyReadMany(4) == 15)
}

// A qualified read runs the same guard.
namespace LateSafetyStore
{
    late var item: *LateGlobalSafetyItem
}

#[Swag.Safety(.Null, true)]
func lateSafetyReadQualified()->s32
{
    return LateSafetyStore.item.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyReadQualified()
    discard x
}

// An inlined callee that may return before its read proves nothing to its caller.
#[Swag.Inline]
func lateSafetyMaybeRead(flag: bool)->s32
{
    if not flag do
        return 0
    return g_lateSafetyUnset.value
}

#[Swag.Safety(.Null, true)]
func lateSafetyAfterInlineReturn(flag: bool)->s32
{
    let first = lateSafetyMaybeRead(flag)
    return first + g_lateSafetyUnset.value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    let x = #run lateSafetyAfterInlineReturn(false)
    discard x
}
