#global private

struct SelectionError
{
    using base: Swag.BaseError
}

struct SelectionValue
{
    value: s32
}

var g_Selected:      s32
var g_FallbackCalls: s32
var g_LeftCalls:     s32
var g_RightCalls:    s32
var g_Fallback:      s32 = 17

#[Swag.NoInline]
func fallbackValue()->s32
{
    g_FallbackCalls += 1
    return 19
}

#[Swag.NoInline]
func selectedValue(left: bool)->s32
{
    if left
    {
        g_LeftCalls += 1
        return 23
    }

    g_RightCalls += 1
    return 29
}

#[Swag.NoInline]
func selectionMayFail(raise: bool) fail
{
    if raise do
        fail SelectionError{base: Swag.BaseError{"selection"}}
}

// Cleanup is emitted separately for the failed call and the successful return.
#[Swag.NoInline]
func deferredSelections(value: *s32?, box: *SelectionValue?, left: bool, raise: bool) fail
{
    defer
    {
        g_Selected += (value orelse &g_Fallback)[]
        g_Selected += box?.value orelse fallbackValue()
        g_Selected += left ? selectedValue(true) : selectedValue(false)
    }

    try selectionMayFail(raise)
}

#test
{
    var value: s32 = 3
    var box        = SelectionValue{5}
    g_Selected      = 0
    g_FallbackCalls = 0
    g_LeftCalls     = 0
    g_RightCalls    = 0

    try deferredSelections(&value, &box, true, false)
    Swag.assert(g_Selected == 31)
    Swag.assert(g_FallbackCalls == 0 and g_LeftCalls == 1 and g_RightCalls == 0)

    discard catch deferredSelections(null, null, false, true)
    Swag.assert(g_Selected == 96)
    Swag.assert(g_FallbackCalls == 1 and g_LeftCalls == 1 and g_RightCalls == 1)

    try deferredSelections(null, null, false, false)
    Swag.assert(g_Selected == 161)
    Swag.assert(g_FallbackCalls == 2 and g_LeftCalls == 1 and g_RightCalls == 2)

    discard catch deferredSelections(&value, &box, true, true)
    Swag.assert(g_Selected == 192)
    Swag.assert(g_FallbackCalls == 2 and g_LeftCalls == 2 and g_RightCalls == 2)
}
