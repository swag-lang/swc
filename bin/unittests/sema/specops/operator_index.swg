#global private

struct ValueIndexBox
{
    first:  s32
    second: s32
}

impl ValueIndexBox
{
    mtd opIndex(index: s32)->s32
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
    mtd opIndex(index: s32)->&s32
    {
        return &.buffer[index]
    }

    mtd const opIndex(index: s32)->const &s32
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
    mtd opIndex(row: s32, col: s32)->s32
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

enum IndexedSlot { First, Second, Third }

enum ReorderedIndexedSlot: u8
{
    Third  = 2
    First  = 0
    Second = 1
}

enum SingletonIndexedSlot
{
    Only
}

func semaTest004()
{
    const values: [IndexedSlot] s32 = [0, 1, 2]
    let first = values[IndexedSlot.First]

    var index = IndexedSlot.Third
    let last = values[index]

    #assert(#typeof(first) == s32)
    #assert(#typeof(last) == s32)
}

func semaTestIndexedEnumValues()
{
    const reordered: [ReorderedIndexedSlot] s32 = [10, 20, 30]
    #assert(#typeof(reordered) == [ReorderedIndexedSlot] s32)
    let first  = reordered[ReorderedIndexedSlot.First]
    let second = reordered[ReorderedIndexedSlot.Second]
    let third  = reordered[ReorderedIndexedSlot.Third]
    #assert(#typeof(first) == s32)
    #assert(#typeof(second) == s32)
    #assert(#typeof(third) == s32)

    const singleton: [SingletonIndexedSlot] s32 = [42]
    #assert(#typeof(singleton) == [SingletonIndexedSlot] s32)
    let only = singleton[SingletonIndexedSlot.Only]
    #assert(#typeof(only) == s32)
}

enum IndexedByte: u8 { Zero, One, Two }

func semaTest005()
{
    var values: [IndexedByte] u8
    values[IndexedByte.Two] = 7

    #assert(#typeof(values) == [IndexedByte] u8)
    #assert(#typeof(values[IndexedByte.Two]) == u8)
}
