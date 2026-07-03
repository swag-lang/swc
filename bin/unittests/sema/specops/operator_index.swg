#global private

struct ValueIndexBox
{
    first:  s32
    second: s32
}

impl ValueIndexBox
{
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
    mtd opIndex(index: s32) -> &s32
    {
        return &.buffer[index]
    }

    mtd const opIndex(index: s32) -> const &s32
    {
        return &.buffer[index]
    }
}

struct MultiIndexBox
{
    values: [4] s32
}

impl MultiIndexBox
{
    mtd opIndex(row: s32, col: s32) -> s32
    {
        return .values[row * 2 + col]
    }
}

func semaTest001()
{
    var box = ValueIndexBox{first: 7, second: 9}
    let first = box[0]
    let second = box[1]
    #assert(#typeof(first) == s32)
    #assert(#typeof(second) == s32)
}

func semaTest002()
{
    var box = RefIndexBox{buffer: [3, 5]}
    let first = box[1]
    #assert(#typeof(first) == s32)

    const cbox = RefIndexBox{buffer: [11, 13]}
    let second = cbox[0]
    #assert(#typeof(second) == s32)
}

func semaTest003()
{
    var box = MultiIndexBox{}
    let value = box[1, 0]

    #assert(#typeof(value) == s32)
}

#[Swag.EnumIndex]
enum IndexedSlot { First, Second, Third }

func semaTest004()
{
    const values = [0, 1, 2]
    let first = values[IndexedSlot.First]

    var index = IndexedSlot.Third
    let last = values[index]

    #assert(#typeof(first) == s32)
    #assert(#typeof(last) == s32)
}

#[Swag.EnumIndex]
enum IndexedByte: u8 { Zero, One, Two }

func semaTest005(flag: bool)
{
    var raw: u8 = IndexedByte.Two
    let selectedByte = flag ? 0'u8 : IndexedByte.One
    let selectedSlot = flag ? 0's32 : IndexedSlot.Second

    #assert(#typeof(raw) == u8)
    #assert(#typeof(selectedByte) == u8)
    #assert(#typeof(selectedSlot) == s32)
}
