#global private

// Reading a '#late' global before its first assignment panics under Null safety: no
// static cross-function proof is possible, so the guard always runs at runtime. Driven
// through '#run' so the guard executes at compile time and the panic is observed.

struct LateGlobalSafetyItem
{
    value: s32
}

var g_lateSafetyUnset: #late *LateGlobalSafetyItem

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
var g_lateSafetyStorage: LateGlobalSafetyItem
var g_lateSafetySet:     #late *LateGlobalSafetyItem

#[Swag.Safety(.Null, true)]
func lateSafetyReadSet()->s32
{
    return g_lateSafetySet.value
}

#test
{
    g_lateSafetyStorage.value = 5
    g_lateSafetySet           = &g_lateSafetyStorage
    @assert(lateSafetyReadSet() == 5)
}
