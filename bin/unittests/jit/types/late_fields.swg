#global private

struct JitLateItem
{
    value: s32
}

struct JitLateBox
{
    item:  #late *JitLateItem
    name:  #late string
    count: s32
}

// Full life of late fields: unset, assigned, read, written through.
func jitLateLifecycle()->bool
{
    var first = JitLateItem{value: 7}
    var box: JitLateBox

    if #isset(box.item) or #isset(box.name) do
        return false

    box.item = &first
    box.name = "hello"
    if !#isset(box.item) or !#isset(box.name) do
        return false

    let p: *JitLateItem = box.item
    if p.value != 7 do
        return false
    if @countof(box.name) != 5 do
        return false

    box.item.value = 8
    return first.value == 8
}

// Address-of never reads the value: filling through a pointer works.
func jitLateAddressOf()->bool
{
    var it = JitLateItem{value: 3}
    var box: JitLateBox
    let slot = &box.item
    dref slot = &it
    return #isset(box.item) and box.item.value == 3
}

// Struct literals omit late fields; they start unset.
func jitLateLiteral()->bool
{
    let box = JitLateBox{count: 4}
    return box.count == 4 and !#isset(box.item) and !#isset(box.name)
}

#test
{
    @assert(jitLateLifecycle())
    @assert(jitLateAddressOf())
    @assert(jitLateLiteral())
}

// Regression: a struct with non-zero field defaults initializes through the
// partial per-field path. A '#late' field is typed non-null, so the generic
// implicit-default emitter used to SKIP it ("requires explicit init"), leaving
// whatever garbage the allocation carried: '#isset' then read true on a fresh
// object (seen as 0xD0 mimalloc poison on the heap). Late storage must be
// zeroed on every construction path.
struct JitLateDirty
{
    tag: s32 = 5
    item:  #late *JitLateItem
    ratio: f32 = 1.5
}

func jitLateDirtyMemoryInit()->bool
{
    let raw = notnull @alloc(#sizeof(JitLateDirty))
    @memset(raw, 0xD0, #sizeof(JitLateDirty))

    let box = cast(*JitLateDirty) raw
    @init(box, 1)

    let ok = box.tag == 5 and box.ratio == 1.5 and !#isset(box.item)
    @free(raw)
    return ok
}

#test
{
    @assert(jitLateDirtyMemoryInit())
}
