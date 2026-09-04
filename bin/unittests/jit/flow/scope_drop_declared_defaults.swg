#global private

// A struct local declared without an initializer takes part in scope drops whatever its
// implicit default looks like. A field carrying a declared default value changes the shape
// of that default; it does not change who owns the storage, so the owning field is still
// released when the local leaves scope.

var g_scopeDropCount: s32

struct ScopeDropHandle
{
    live: bool
}

impl ScopeDropHandle
{
    mtd opDrop()
    {
        if .live do
            g_scopeDropCount += 1
        .live = false
    }
}

// Every field defaults to zero.
struct ScopeAllZero
{
    handle: ScopeDropHandle
    count:  s32
}

// One field carries a declared default, so the implicit default is no longer all zero.
struct ScopeDeclaredDefault
{
    handle: ScopeDropHandle
    count:  s32 = 3
}

// Same, with the default's type inferred from the initializer.
struct ScopeInferredDefault
{
    handle: ScopeDropHandle
    count = 3
}

// A field with no valid implicit default: the local is proved initialized instead.
struct ScopeRequiresInit
{
    handle: ScopeDropHandle
    target: *s32
}

#test
{
    g_scopeDropCount = 0
    {
        var value: ScopeAllZero
        value.handle.live = true
    }
    Swag.assert(g_scopeDropCount == 1)
}

#test
{
    g_scopeDropCount = 0
    {
        var value: ScopeDeclaredDefault
        value.handle.live = true
        Swag.assert(value.count == 3)
    }
    Swag.assert(g_scopeDropCount == 1)
}

#test
{
    g_scopeDropCount = 0
    {
        var value: ScopeInferredDefault
        value.handle.live = true
        Swag.assert(value.count == 3)
    }
    Swag.assert(g_scopeDropCount == 1)
}

#test
{
    var slot = 0's32
    g_scopeDropCount = 0
    {
        var value: ScopeRequiresInit
        value.handle = ScopeDropHandle{live: true}
        value.target = &slot
    }
    Swag.assert(g_scopeDropCount == 1)
}
