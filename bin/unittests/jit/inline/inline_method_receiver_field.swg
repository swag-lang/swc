#global private

// A method names its receiver's fields directly. Inlined at a call site, the body must read and
// write them through the caller's receiver, whatever expression the caller used for it.
struct InlineFieldHolder
{
    value: s32
    items: [2] s32
}

impl InlineFieldHolder
{
    mtd fetch()->s32 => value
    mtd first()->s32 => items[0]
    mtd bump() { value += 1 }

    #[Swag.Inline]
    mtd store(newValue: s32) { value = newValue }

    #[Swag.Inline]
    mtd total()->s32 => value + .fetch()
}

struct(T) InlineFieldBox
{
    item: T
}

impl InlineFieldBox
{
    mtd get()->T => item
}

#test
{
    var holders: [2] InlineFieldHolder
    holders[1].store(5)
    holders[1].bump()
    Swag.require(holders[1].fetch() == 6)
    Swag.require(holders[1].total() == 12)

    var index = 0
    holders[index].items[0] = 3
    holders[index].bump()
    Swag.require(holders[index].first() == 3)
    Swag.require(holders[0].fetch() == 1)

    var box: InlineFieldBox!{s32}
    box.item = 4
    Swag.require(box.get() == 4)
}
