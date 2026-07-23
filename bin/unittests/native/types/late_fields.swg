#global private

struct NativeLateItem
{
    value: s32
}

struct NativeLateBox
{
    item:  #late *NativeLateItem
    name:  #late string
    count: s32
}

// Full life of late fields: unset, assigned, read, written through.
func nativeLateLifecycle()->bool
{
    var first = NativeLateItem{value: 7}
    var box: NativeLateBox

    if #isset(box.item) or #isset(box.name) do
        return false

    box.item = &first
    box.name = "hello"
    if !#isset(box.item) or !#isset(box.name) do
        return false

    let p: *NativeLateItem = box.item
    if p.value != 7 do
        return false
    if @countof(box.name) != 5 do
        return false

    box.item.value = 8
    return first.value == 8
}

// Address-of never reads the value: filling through a pointer works.
func nativeLateAddressOf()->bool
{
    var it = NativeLateItem{value: 3}
    var box: NativeLateBox
    let slot = &box.item
    dref slot = &it
    return #isset(box.item) and box.item.value == 3
}

// Struct literals omit late fields; they start unset.
func nativeLateLiteral()->bool
{
    let box = NativeLateBox{count: 4}
    return box.count == 4 and !#isset(box.item) and !#isset(box.name)
}

#test
{
    @assert(nativeLateLifecycle())
    @assert(nativeLateAddressOf())
    @assert(nativeLateLiteral())
}
