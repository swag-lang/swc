#global private

struct ReverseCompareBox
{
    value: s32
}

impl ReverseCompareBox
{
    #[Swag.NoInline]
    mtd const opEquals(other: s32)->bool => .value == other

    #[Swag.NoInline]
    mtd const opCompare(other: s32)->s32
    {
        if .value < other do return -1
        if .value > other do return 1
        return 0
    }
}

const ReverseCompileBox = ReverseCompareBox{value: 2}
#assert(1 < ReverseCompileBox)
#assert(2 == ReverseCompileBox)
#assert((1 <=> ReverseCompileBox) == -1)
#assert((2 <=> ReverseCompileBox) == 0)
#assert((3 <=> ReverseCompileBox) == 1)

#test
{
    let box = ReverseCompareBox{value: 2}

    Swag.require(2 == box)
    Swag.require(box == 2)
    Swag.require(1 != box)
    Swag.require(not (2 != box))
    Swag.require(not (1 == box))

    Swag.require(1 < box)
    Swag.require(1 <= box)
    Swag.require(2 <= box)
    Swag.require(not (3 < box))
    Swag.require(not (3 <= box))
    Swag.require(3 > box)
    Swag.require(3 >= box)
    Swag.require(2 >= box)
    Swag.require(not (1 > box))
    Swag.require(not (1 >= box))

    Swag.require((1 <=> box) < 0)
    Swag.require((2 <=> box) == 0)
    Swag.require((3 <=> box) > 0)
}

struct LeftCompareOwner {}
struct RightCompareOwner {}

impl LeftCompareOwner
{
    mtd const opEquals(_: RightCompareOwner)->bool => true
    mtd const opCompare(_: RightCompareOwner)->s32 => -1
}

impl RightCompareOwner
{
    mtd const opEquals(_: LeftCompareOwner)->bool => false
    mtd const opCompare(_: LeftCompareOwner)->s32 => 1
}

#test
{
    let left = LeftCompareOwner{}
    let right = RightCompareOwner{}
    Swag.require(left == right)
    Swag.require(right != left)
    Swag.require(left < right)
    Swag.require(right > left)
}

struct LeftMismatchOwner {}
struct RightFallbackOwner {}

impl LeftMismatchOwner
{
    mtd const opEquals(_: u8)->bool => false
}

impl RightFallbackOwner
{
    mtd const opEquals(_: LeftMismatchOwner)->bool => true
}

#test
{
    Swag.require(LeftMismatchOwner{} == RightFallbackOwner{})
}
