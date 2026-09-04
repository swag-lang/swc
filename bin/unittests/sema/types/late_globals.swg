#global private

// 'late' global: accepted without an initializer (unlike a bare non-null global),
// exposed as a non-null type, guarded at every read, and inspectable with a null comparison.

struct LateGlobalSemaItem
{
    value: s32
}

var g_lateSemaStorage:   LateGlobalSemaItem
late var g_lateSemaItem: *LateGlobalSemaItem
late var g_lateSemaName: string

// The exposed type is non-null.
#assert(#typeof(g_lateSemaItem) == *LateGlobalSemaItem)
#assert(#typeof(g_lateSemaName) == string)

// A guarded read yields the non-null type (usable where non-null is required).
func lateSemaTakesNonNull(p: *LateGlobalSemaItem)->s32 => p.value

func lateSemaRead()->s32
{
    return lateSemaTakesNonNull(g_lateSemaItem)
}

// A null comparison inspects the storage without reading the value.
func lateSemaPresence()->bool
{
    return (g_lateSemaItem != null) and (g_lateSemaName != null)
}

// Assignment sets it; the target is not a guarded read.
func lateSemaAssign()
{
    g_lateSemaItem = &g_lateSemaStorage
    g_lateSemaName = "hi"
}
