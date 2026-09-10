#global private

struct NativeLateItem
{
    value: s32
}

struct NativeLateBox
{
    late item: *NativeLateItem
    late name: string
    count:     s32
}

// Full life of late fields: unset, assigned, read, written through.
func nativeLateLifecycle()->bool
{
    var first = NativeLateItem{value: 7}
    var box: NativeLateBox

    if (box.item != null) or (box.name != null) do
        return false

    box.item = &first
    box.name = "hello"
    if not (box.item != null) or not (box.name != null) do
        return false

    let p: *NativeLateItem = box.item
    if p.value != 7 do
        return false
    if box.name.count != 5 do
        return false

    box.item.value = 8
    return first.value == 8
}

// Address-of never reads the value: filling through a pointer works.
func nativeLateAddressOf()->bool
{
    var it   = NativeLateItem{value: 3}
    var box: NativeLateBox
    let slot = &box.item
    slot[] = &it
    return (box.item != null) and box.item.value == 3
}

// Struct literals omit late fields; they start unset.
func nativeLateLiteral()->bool
{
    let box = NativeLateBox{count: 4}
    return box.count == 4 and not (box.item != null) and not (box.name != null)
}

// A slot is released by writing null back, which is the inverse of the store that filled
// it. A container needs that store to hand its storage away, and the null it leaves is what
// stops a second release from running.
func nativeLateRelease()->bool
{
    var first = NativeLateItem{value: 3}
    var box: NativeLateBox

    box.item = &first
    if box.item == null do
        return false

    box.item = null
    if box.item != null do
        return false

    // Refilling after a release works like the first fill.
    box.item = &first
    return box.item != null and box.item.value == 3
}

#test
{
    Swag.assert(nativeLateLifecycle())
    Swag.assert(nativeLateRelease())
    Swag.assert(nativeLateAddressOf())
    Swag.assert(nativeLateLiteral())
}
