#global private

// 'Swag.Late' also qualifies a GLOBAL variable: its zero (null) storage is the 'unset'
// sentinel, its exposed type is non-null, and every read is guarded (a runtime null
// panic when still unset). No static cross-function proof is possible, so the guard
// always runs. 'Swag.isSet' tests the storage without reading the value.

struct LateGlobalItem
{
    value: s32
}

var g_lateGlobalStorage: LateGlobalItem
#[Swag.Late]
var g_lateGlobalItem: *LateGlobalItem
#[Swag.Late]
var g_lateGlobalName: string

// Full life: unset, assigned, read (guarded), written through.
func lateGlobalLifecycle()->bool
{
    if Swag.isSet(g_lateGlobalItem) or Swag.isSet(g_lateGlobalName) do
        return false

    g_lateGlobalStorage.value = 7
    g_lateGlobalItem          = &g_lateGlobalStorage
    g_lateGlobalName          = "hello"

    if !Swag.isSet(g_lateGlobalItem) or !Swag.isSet(g_lateGlobalName) do
        return false

    let p: *LateGlobalItem = g_lateGlobalItem
    if p.value != 7 do
        return false
    if g_lateGlobalName.count != 5 do
        return false

    g_lateGlobalItem.value = 8
    return g_lateGlobalStorage.value == 8
}

// Address-of never reads the value: filling through a pointer works without a guard.
#[Swag.Late]
var g_lateGlobalAddr:        *LateGlobalItem
var g_lateGlobalAddrStorage: LateGlobalItem

func lateGlobalAddressOf()->bool
{
    g_lateGlobalAddrStorage.value = 3
    let slot = &g_lateGlobalAddr
    slot[] = &g_lateGlobalAddrStorage
    return Swag.isSet(g_lateGlobalAddr) and g_lateGlobalAddr.value == 3
}

// A 'Swag.Late' global read auto-inlined through an accessor stays guarded and non-null.
#[Swag.Late]
var g_lateGlobalInline:        *LateGlobalItem
var g_lateGlobalInlineStorage: LateGlobalItem

func lateGlobalRead()->s32 => g_lateGlobalInline.value

func lateGlobalThroughAccessor()->bool
{
    g_lateGlobalInlineStorage.value = 42
    g_lateGlobalInline              = &g_lateGlobalInlineStorage
    return lateGlobalRead() == 42
}

#test
{
    Swag.assert(lateGlobalLifecycle())
    Swag.assert(lateGlobalAddressOf())
    Swag.assert(lateGlobalThroughAccessor())
}
