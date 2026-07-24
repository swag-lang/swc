#global private

// '#late' global: accepted without an initializer (unlike a bare non-null global),
// exposed as a non-null type, guarded at every read, and inspectable with '@isset'.

struct LateGlobalSemaItem
{
    value: s32
}

var g_lateSemaStorage: LateGlobalSemaItem
var g_lateSemaItem:    #late *LateGlobalSemaItem
var g_lateSemaName:    #late string

// The exposed type is non-null.
#assert(#typeof(g_lateSemaItem) == *LateGlobalSemaItem)
#assert(#typeof(g_lateSemaName) == string)

// A guarded read yields the non-null type (usable where non-null is required).
func lateSemaTakesNonNull(p: *LateGlobalSemaItem)->s32 => p.value

func lateSemaRead()->s32
{
    return lateSemaTakesNonNull(g_lateSemaItem)
}

// '@isset' inspects the storage without reading the value.
func lateSemaIsSet()->bool
{
    return @isset(g_lateSemaItem) and @isset(g_lateSemaName)
}

// Assignment sets it; the target is not a guarded read.
func lateSemaAssign()
{
    g_lateSemaItem = &g_lateSemaStorage
    g_lateSemaName = "hi"
}
