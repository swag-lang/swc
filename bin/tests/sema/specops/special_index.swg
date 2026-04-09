#global fileprivate

struct ValueIndexBox
{
    first:  s32
    second: s32
}

impl ValueIndexBox
{
    #[Swag.Overload]
    mtd opIndex(index: s32) -> s32
    {
        if index == 0 do
            return .first
        return .second
    }
}

struct RefIndexBox
{
    buffer: [2] s32
}

impl RefIndexBox
{
    #[Swag.Overload]
    mtd opIndex(index: s32) -> &s32
    {
        return &.buffer[index]
    }

    #[Swag.Overload]
    mtd const opIndex(index: s32) -> const &s32
    {
        return &.buffer[index]
    }
}

#test
{
    var box = ValueIndexBox{first: 7, second: 9}
    let first = box[0]
    let second = box[1]
    #assert(#typeof(first) == s32)
    #assert(#typeof(second) == s32)
}

#test
{
    var box = RefIndexBox{buffer: [3, 5]}
    let first = box[1]
    #assert(#typeof(first) == s32)

    const cbox = RefIndexBox{buffer: [11, 13]}
    let second = cbox[0]
    #assert(#typeof(second) == s32)
}

#[Swag.EnumIndex]
enum IndexedSlot { First, Second, Third }

#test
{
    const values = [0, 1, 2]
    let first = values[IndexedSlot.First]

    var index = IndexedSlot.Third
    let last = values[index]

    #assert(#typeof(first) == s32)
    #assert(#typeof(last) == s32)
}
