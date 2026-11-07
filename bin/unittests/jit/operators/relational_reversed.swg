#global private

struct JitReverseBox
{
    value: s32
}

impl JitReverseBox
{
    mtd const opEquals(other: s32)->bool => .value == other

    mtd const opCompare(other: s32)->s32
    {
        if .value < other do return -1
        if .value > other do return 1
        return 0
    }
}

#test
{
    let value = JitReverseBox{value: 5}
    Swag.require(5 == value)
    Swag.require(4 != value)
    Swag.require(4 < value)
    Swag.require(5 <= value)
    Swag.require(6 > value)
    Swag.require(5 >= value)
    Swag.require((4 <=> value) < 0)
    Swag.require((6 <=> value) > 0)
}
