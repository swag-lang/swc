#global private

struct NativeLateItem
{
    value: s32
}

struct NativeLateBox
{
    #[Swag.Late]
    item: *NativeLateItem
    #[Swag.Late]
    name:  string
    count: s32
}

// Full life of late fields: unset, assigned, read, written through.
func nativeLateLifecycle()->bool
{
    var first = NativeLateItem{value: 7}
    var box: NativeLateBox

    if Swag.isSet(box.item) or Swag.isSet(box.name) do
        return false

    box.item = &first
    box.name = "hello"
    if !Swag.isSet(box.item) or !Swag.isSet(box.name) do
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
    return Swag.isSet(box.item) and box.item.value == 3
}

// Struct literals omit late fields; they start unset.
func nativeLateLiteral()->bool
{
    let box = NativeLateBox{count: 4}
    return box.count == 4 and !Swag.isSet(box.item) and !Swag.isSet(box.name)
}

#test
{
    Swag.assert(nativeLateLifecycle())
    Swag.assert(nativeLateAddressOf())
    Swag.assert(nativeLateLiteral())
}
