#global private

struct JitLateItem
{
    value: s32
}

struct JitLateBox
{
    #[Swag.Late]
    item: *JitLateItem
    #[Swag.Late]
    name:  string
    count: s32
}

// Full life of late fields: unset, assigned, read, written through.
func jitLateLifecycle()->bool
{
    var first = JitLateItem{value: 7}
    var box: JitLateBox

    if Swag.isSet(box.item) or Swag.isSet(box.name) do
        return false

    box.item = &first
    box.name = "hello"
    if !Swag.isSet(box.item) or !Swag.isSet(box.name) do
        return false

    let p: *JitLateItem = box.item
    if p.value != 7 do
        return false
    if box.name.count != 5 do
        return false

    box.item.value = 8
    return first.value == 8
}

// Address-of never reads the value: filling through a pointer works.
func jitLateAddressOf()->bool
{
    var it   = JitLateItem{value: 3}
    var box: JitLateBox
    let slot = &box.item
    slot[] = &it
    return Swag.isSet(box.item) and box.item.value == 3
}

// Struct literals omit late fields; they start unset.
func jitLateLiteral()->bool
{
    let box = JitLateBox{count: 4}
    return box.count == 4 and !Swag.isSet(box.item) and !Swag.isSet(box.name)
}

#test
{
    Swag.assert(jitLateLifecycle())
    Swag.assert(jitLateAddressOf())
    Swag.assert(jitLateLiteral())
}

// Regression: a struct with non-zero field defaults initializes through the
// partial per-field path. A 'Swag.Late' field is typed non-null, so the generic
// implicit-default emitter used to SKIP it ("requires explicit init"), leaving
// whatever garbage the allocation carried: 'Swag.isSet' then read true on a fresh
// object (seen as 0xD0 mimalloc poison on the heap). Late storage must be
// zeroed on every construction path.
struct JitLateDirty
{
    tag: s32 = 5
    #[Swag.Late]
    item:  *JitLateItem
    ratio: f32 = 1.5
}

func jitLateDirtyMemoryInit()->bool
{
    let raw = testAlloc(#sizeof(JitLateDirty))!
    Swag.memset(raw, 0xD0, #sizeof(JitLateDirty))

    let box = cast(*JitLateDirty) raw
    Swag.init(box, 1)

    let ok = box.tag == 5 and box.ratio == 1.5 and !Swag.isSet(box.item)
    testFree(raw)
    return ok
}

#test
{
    Swag.assert(jitLateDirtyMemoryInit())
}
